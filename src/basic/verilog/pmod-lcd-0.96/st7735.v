// ============================================================================
//  st7735.v -- ST7735S 0.96" TFT (160x80) 纯逻辑驱动 (不需要 CPU)
//
//  上电流程:
//      复位拉低 20ms -> 释放复位等 100ms -> 跑初始化 ROM -> 设地址窗口
//      -> 全屏刷 8 条竖直色条 -> done
//
//  SPI 时序 (与 iceZ0mb1e 参考固件保持一致):
//      SCLK 空闲为高; 每个 bit 先拉低 SCLK 并把新数据放到 MOSI,
//      再拉高 SCLK, ST7735 在 SCLK 上升沿采样.  MSB first.
//
//  初始化 ROM (st7735_init.hex, 每行 16bit):
//      [15:14] op : 0=命令 1=数据 2=延时(低 8 位 = 毫秒) 3=结束
//      [7:0]   字节
//
//  引脚 (iCESugar PMOD3, 见 top.pcf):
//      lcd_cs_n  34   片选 (低有效)
//      lcd_sck   25   时钟
//      lcd_mosi  31   数据
//      lcd_dc    27   0=命令 1=数据
//      lcd_rst_n 23   复位 (低有效)
// ============================================================================
`default_nettype none

module st7735 #(
    parameter integer CLK_HZ  = 24_000_000,
    parameter integer SCK_DIV = 4,                 // SCLK = CLK_HZ/(2*SCK_DIV)
    parameter         INIT_HEX = "st7735_init.hex"
)(
    input  wire clk,
    input  wire rst_n,          // 外部复位 (低有效)
    output reg  lcd_rst_n,      // LCD 复位 (低有效)
    output reg  lcd_cs_n,       // LCD 片选 (低有效)
    output reg  lcd_dc,         // 0=命令, 1=数据
    output reg  lcd_sck,
    output reg  lcd_mosi,
    output reg  busy,           // 1 = 正在初始化/刷屏
    output reg  done            // 刷完一帧后拉高一拍
);

    // ------------------------------------------------------------------
    //  常量
    // ------------------------------------------------------------------
    localparam integer MS_TICKS = CLK_HZ / 1000;   // 1ms 对应多少拍
    localparam integer T_RST_LOW = 20 * MS_TICKS;  // 复位低电平 20ms
    localparam integer T_RST_REL = 100 * MS_TICKS; // 释放复位后等 100ms

    localparam [1:0] OP_CMD = 2'd0, OP_DAT = 2'd1, OP_DLY = 2'd2, OP_END = 2'd3;

    localparam [3:0] ST_RST_LOW = 4'd0,
                     ST_RST_REL = 4'd1,
                     ST_F0     = 4'd2,   // 取 ROM (下一拍 rom_q 有效)
                     ST_F1     = 4'd3,   // 解析 ROM
                     ST_EXEC   = 4'd4,   // 等字节发完
                     ST_DELAY  = 4'd5,   // ROM 里的毫秒延时
                     ST_PIX    = 4'd6,   // 刷像素
                     ST_DONE   = 4'd7;

    reg [3:0]  st;
    reg [23:0] ms_cnt;
    reg [23:0] ms_top;

    // ------------------------------------------------------------------
    //  初始化 ROM (同步读, 与 ov2640_cfg.v 同一套写法)
    // ------------------------------------------------------------------
    reg [15:0] rom [0:127];
    initial $readmemh(INIT_HEX, rom);

    reg [15:0] rom_q;
    reg [6:0]  rom_idx;
    always @(posedge clk) rom_q <= rom[rom_idx];

    // ------------------------------------------------------------------
    //  SPI 字节发送引擎
    // ------------------------------------------------------------------
    reg        snd_req;      // 主状态机的请求 (电平, 由主状态机清零)
    reg [7:0]  snd_data;
    reg        snd_dc;
    wire       snd_taken;    // 引擎已取走该字节 (脉冲)
    wire       snd_busy;     // 正在发送
    wire       snd_done;     // 该字节全部移完 (脉冲)

    reg        eng_busy, eng_taken, eng_done;
    reg [3:0]  bit_cnt;      // 7..0
    reg        phase;        // 0 = 拉低 SCLK 并装载数据, 1 = 拉高 SCLK(采样点)

    localparam [3:0] DIV_LAST = SCK_DIV - 1;
    reg [3:0] div_cnt;
    always @(posedge clk) begin
        if (!rst_n) div_cnt <= 4'd0;
        else        div_cnt <= (div_cnt == DIV_LAST) ? 4'd0 : div_cnt + 4'd1;
    end
    wire tick = (div_cnt == DIV_LAST);

    assign snd_busy  = eng_busy;
    assign snd_taken = eng_taken;
    assign snd_done  = eng_done;

    //  注意: lcd_cs_n / lcd_dc / lcd_sck / lcd_mosi 只在这里驱动一次。
    //  主状态机不要再碰这四根线, 否则 yosys 会报 "multiple conflicting
    //  drivers" 并把信号解析成常量 (片选恒高 -> 屏永远不亮, 而且不报错)。
    always @(posedge clk) begin
        if (!rst_n) begin
            eng_busy  <= 1'b0;
            eng_taken <= 1'b0;
            eng_done  <= 1'b0;
            bit_cnt   <= 4'd0;
            phase     <= 1'b0;
            lcd_cs_n  <= 1'b1;
            lcd_dc    <= 1'b0;
            lcd_sck   <= 1'b1;
            lcd_mosi  <= 1'b0;
        end else begin
            eng_taken <= 1'b0;
            eng_done  <= 1'b0;
            if (tick) begin
                if (!eng_busy) begin
                    lcd_sck  <= 1'b1;      // 空闲高
                    lcd_mosi <= 1'b0;
                    if (snd_req) begin
                        eng_busy  <= 1'b1;
                        eng_taken <= 1'b1;
                        bit_cnt   <= 4'd7;
                        phase     <= 1'b0;
                        lcd_cs_n  <= 1'b0;
                        lcd_dc    <= snd_dc;
                        lcd_mosi  <= snd_data[7];  // 第一个 bit
                        lcd_sck   <= 1'b0;          // 下降沿
                    end
                end else begin
                    if (!phase) begin
                        lcd_sck <= 1'b1;             // 上升沿: 从机在此采样
                        phase   <= 1'b1;
                    end else begin
                        if (bit_cnt == 4'd0) begin
                            eng_busy <= 1'b0;
                            eng_done <= 1'b1;
                            lcd_cs_n <= 1'b1;
                        end else begin
                            bit_cnt  <= bit_cnt - 4'd1;
                            lcd_mosi <= snd_data[bit_cnt-1];
                            lcd_sck  <= 1'b0;        // 下降沿 + 装载下一个 bit
                            phase    <= 1'b0;
                        end
                    end
                end
            end
        end
    end

    // ------------------------------------------------------------------
    //  色条: 8 条竖直色条, 每条 20 像素 (160/8)
    //  经典测试图顺序: 白 黄 青 绿 品红 红 蓝 黑
    // ------------------------------------------------------------------
    function [15:0] bar_color;
        input [2:0] i;
        begin
            case (i)
                3'd0: bar_color = 16'hFFFF;  // 白
                3'd1: bar_color = 16'hFFE0;  // 黄
                3'd2: bar_color = 16'h07FF;  // 青
                3'd3: bar_color = 16'h07E0;  // 绿
                3'd4: bar_color = 16'hF81F;  // 品红
                3'd5: bar_color = 16'hF800;  // 红
                3'd6: bar_color = 16'h001F;  // 蓝
                default: bar_color = 16'h0000; // 黑
            endcase
        end
    endfunction

    reg        pix_hi;       // 当前发的是高字节?
    reg [7:0]  x;            // 0..159
    reg [6:0]  y;            // 0..79
    reg [2:0]  bar_idx;      // 当前色条 0..7
    reg [4:0]  bar_pos;      // 色条内位置 0..19

    wire [15:0] cur_color  = bar_color(bar_idx);
    //  下一像素的色条: 每 20 像素换一条 (3 位自然回绕, 行尾 7+1=8 -> 0)
    wire [2:0]  next_idx   = (bar_pos == 5'd19) ? (bar_idx + 3'd1) : bar_idx;
    wire [15:0] next_color = bar_color(next_idx);

    // ------------------------------------------------------------------
    //  主状态机
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            st        <= ST_RST_LOW;
            lcd_rst_n <= 1'b0;
            snd_req   <= 1'b0;
            snd_data  <= 8'h00;
            snd_dc    <= 1'b0;
            rom_idx   <= 7'd0;
            ms_cnt    <= 24'd0;
            ms_top    <= 24'd0;
            pix_hi    <= 1'b0;
            x         <= 8'd0;
            y         <= 7'd0;
            bar_idx   <= 3'd0;
            bar_pos   <= 5'd0;
            busy      <= 1'b1;
            done      <= 1'b0;
        end else begin
            done <= 1'b0;
            if (snd_taken) snd_req <= 1'b0;   // 引擎已取走, 撤销请求

            case (st)
            // ---------------------------------------------------------
            //  复位拉低 20ms
            // ---------------------------------------------------------
            ST_RST_LOW: begin
                lcd_rst_n <= 1'b0;
                if (ms_cnt >= T_RST_LOW - 1) begin
                    ms_cnt <= 24'd0;
                    st     <= ST_RST_REL;
                end else begin
                    ms_cnt <= ms_cnt + 24'd1;
                end
            end
            // ---------------------------------------------------------
            //  释放复位, 等 100ms
            // ---------------------------------------------------------
            ST_RST_REL: begin
                lcd_rst_n <= 1'b1;
                if (ms_cnt >= T_RST_REL - 1) begin
                    ms_cnt  <= 24'd0;
                    rom_idx <= 7'd0;
                    st      <= ST_F0;
                end else begin
                    ms_cnt <= ms_cnt + 24'd1;
                end
            end
            // ---------------------------------------------------------
            //  取 ROM: 此拍之后 rom_q 才是新的一条
            // ---------------------------------------------------------
            ST_F0: begin
                st <= ST_F1;
            end
            // ---------------------------------------------------------
            //  解析 ROM
            // ---------------------------------------------------------
            ST_F1: begin
                case (rom_q[15:14])
                    OP_CMD: begin
                        snd_data <= rom_q[7:0];
                        snd_dc   <= 1'b0;
                        snd_req  <= 1'b1;
                        st       <= ST_EXEC;
                    end
                    OP_DAT: begin
                        snd_data <= rom_q[7:0];
                        snd_dc   <= 1'b1;
                        snd_req  <= 1'b1;
                        st       <= ST_EXEC;
                    end
                    OP_DLY: begin
                        ms_cnt <= 24'd0;
                        ms_top <= rom_q[7:0] * MS_TICKS;
                        st     <= ST_DELAY;
                    end
                    default: begin   // OP_END
                        pix_hi <= 1'b0;
                        x      <= 8'd0;
                        y      <= 7'd0;
                        bar_idx<= 3'd0;
                        bar_pos<= 5'd0;
                        st     <= ST_PIX;
                    end
                endcase
            end
            // ---------------------------------------------------------
            //  等这个字节发完
            // ---------------------------------------------------------
            ST_EXEC: begin
                if (snd_done) begin
                    rom_idx <= rom_idx + 7'd1;
                    st      <= ST_F0;
                end
            end
            // ---------------------------------------------------------
            //  ROM 里的毫秒延时
            // ---------------------------------------------------------
            ST_DELAY: begin
                if (ms_cnt >= ms_top - 24'd1) begin
                    ms_cnt  <= 24'd0;
                    rom_idx <= rom_idx + 7'd1;
                    st      <= ST_F0;
                end else begin
                    ms_cnt <= ms_cnt + 24'd1;
                end
            end
            // ---------------------------------------------------------
            //  刷像素: 每行 160 个, 共 80 行, 每像素高字节在前
            // ---------------------------------------------------------
            ST_PIX: begin
                if (snd_done) begin
                    if (pix_hi) begin
                        // 高字节发完 -> 发低字节
                        snd_data <= cur_color[7:0];
                        snd_dc   <= 1'b1;
                        snd_req  <= 1'b1;
                        pix_hi   <= 1'b0;
                    end else begin
                        // 一个像素发完 -> 前进
                        if (x == 8'd159) begin
                            x       <= 8'd0;
                            y       <= y + 7'd1;
                            bar_idx <= 3'd0;
                            bar_pos <= 5'd0;
                            if (y == 7'd79) begin
                                st   <= ST_DONE;
                                busy <= 1'b0;
                                done <= 1'b1;
                            end else begin
                                snd_data <= next_color[15:8];
                                snd_dc   <= 1'b1;
                                snd_req  <= 1'b1;
                                pix_hi   <= 1'b1;
                            end
                        end else begin
                            x <= x + 8'd1;
                            if (bar_pos == 5'd19) begin
                                bar_pos <= 5'd0;
                                bar_idx <= bar_idx + 3'd1;
                            end else begin
                                bar_pos <= bar_pos + 5'd1;
                            end
                            snd_data <= next_color[15:8];
                            snd_dc   <= 1'b1;
                            snd_req  <= 1'b1;
                            pix_hi   <= 1'b1;
                        end
                    end
                end else if (!snd_busy && !snd_req) begin
                    // 本状态的第一字节
                    snd_data <= cur_color[15:8];
                    snd_dc   <= 1'b1;
                    snd_req  <= 1'b1;
                    pix_hi   <= 1'b1;
                end
            end
            // ---------------------------------------------------------
            ST_DONE: begin
                busy <= 1'b0;
            end
            // ---------------------------------------------------------
            default: st <= ST_RST_LOW;
            endcase
        end
    end

endmodule

`default_nettype wire
