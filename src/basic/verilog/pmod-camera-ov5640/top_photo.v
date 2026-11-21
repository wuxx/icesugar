// ============================================================================
//  top_photo.v -- OV5640 拍照模式顶层 (iCE40UP5K / iCESugar)
//
//  和 top.v (功能自检) 的区别: 这里不统计、不判定, 只做一件事 —— 把相机看到的
//  图像原样通过串口送出去, 让 PC 端拼成一张 PNG。
//
//  为什么是"分段扫描"而不是"整帧缓冲":
//    640x480 YUYV 一帧 = 614400 字节, 而 iCE40UP5K 全部 BRAM 只有
//    30 x 4Kbit = 15KB, 整帧根本放不下。
//    所以每帧只采 KROWS=8 行 (10240 字节) 存进片上 BRAM, 串口再慢慢发;
//    主机端按行号把 60 段拼成一整幅图。
//
//  时序 (460800 baud):
//    一行 1280 字节 -> 27.8ms 串口时间, 而相机一行只有 135us, 所以
//    "边收边发"物理上做不到, 必须一段一段来。
//    一段 8 行 = 10240 字节 -> 222ms; 加上等相机转到目标行的等待
//    (一帧约 406ms), 一帧 60 段大约要 25~30 秒。
//
//  遥测: 每发完一段就发一个"状态包"(row=0xFFFF), 内容是状态机状态、
//  配置结果、已采行数/字节数等, 主机端直接打印。这样"卡在哪一步"一目了然。
//
//  引脚与 top.v 完全相同 (见 top.pcf / top_photo.pcf)。
// ============================================================================
`default_nettype none

//  串口波特率。可以用 make photo PHOTO_BAUD=xxxx 覆盖。
//  [实测] DAPLink 的 CDC 会按主机请求设置它自己 UART 的波特率, 所以 FPGA
//  必须和主机设成同一个值, 否则全是乱码。
//  这里默认 115200 而不是 460800: DAPLink 的 MCU 如果是 48MHz 时钟,
//  460800 的 BRR = 6.51 (取 6 或 7) 会产生 7~8% 的波特率误差, 8N1 直接
//  收不到数据; 115200 的 BRR = 26, 误差只有 0.16%, 稳。
`ifndef PHOTO_BAUD
`define PHOTO_BAUD 115200
`endif

//  行缓冲大小也可以在构建时改 (make photo PHOTO_KROWS=1 ...),
//  用来做"是不是 BRAM 拖垮了设计"的二分定位。
`ifndef PHOTO_KROWS
`define PHOTO_KROWS 8
`endif
`ifndef PHOTO_LINEB
`define PHOTO_LINEB 1280
`endif

module top_photo (
    input  wire       clk12,
    output wire       TX,
    output wire       LED_R,
    output wire       LED_G,
    output wire       LED_B,

    // 摄像头 (PMOD)
    output wire       XMCLK,
    inout  wire       SCL,
    inout  wire       SDA,
    input  wire       PCLK,
    input  wire       VSYNC,
    input  wire       HREF,
    input  wire [7:0] D
);

    localparam integer SYS_HZ = 24_000_000;
    localparam integer KROWS  = `PHOTO_KROWS;  // 每段多少行
    localparam integer LINEB  = `PHOTO_LINEB;  // 每行字节数
    localparam integer NSEG   = 480 / KROWS;   // 段数
    localparam integer BAUD   = `PHOTO_BAUD;
    localparam integer AW     = 14;         // 行缓冲地址位宽

    // ------------------------------------------------------------------
    //  PLL: 12MHz -> 24MHz (同时用作系统时钟和摄像头 XMCLK)
    // ------------------------------------------------------------------
    wire clk24;
    SB_PLL40_PAD #(
        .FEEDBACK_PATH("SIMPLE"),
        .DIVR(4'b0000),
        .DIVF(7'b0111111),
        .DIVQ(3'b101),
        .FILTER_RANGE(3'b001)
    ) u_pll (
        .RESETB(1'b1),
        .BYPASS(1'b0),
        .PACKAGEPIN(clk12),
        .PLLOUTCORE(clk24)
    );

    reg [15:0] rst_cnt = 16'd0;
    always @(posedge clk24) begin
        if (rst_cnt != 16'hFFFF) rst_cnt <= rst_cnt + 1'b1;
    end
    wire rst_n = (rst_cnt >= 16'd1000);

    // ------------------------------------------------------------------
    //  XMCLK: IOB DDR 输出, 24MHz 50% 占空
    // ------------------------------------------------------------------
    SB_IO #(
        .PIN_TYPE(6'b0100_01),
        .PULLUP(1'b0)
    ) u_xmclk (
        .PACKAGE_PIN(XMCLK),
        .OUTPUT_CLK(clk24),
        .D_OUT_0(1'b1),
        .D_OUT_1(1'b0)
    );

    // ------------------------------------------------------------------
    //  SCCB 开漏物理层
    // ------------------------------------------------------------------
    wire scl_low, sda_low, sda_in, scl_in;

    SB_IO #(
        .PIN_TYPE(6'b1010_01),
        .PULLUP(1'b1)
    ) u_scl (
        .PACKAGE_PIN(SCL),
        .OUTPUT_ENABLE(scl_low),
        .D_OUT_0(1'b0),
        .D_IN_0(scl_in)
    );

    SB_IO #(
        .PIN_TYPE(6'b1010_01),
        .PULLUP(1'b1)
    ) u_sda (
        .PACKAGE_PIN(SDA),
        .OUTPUT_ENABLE(sda_low),
        .D_OUT_0(1'b0),
        .D_IN_0(sda_in)
    );

    // ------------------------------------------------------------------
    //  SCCB 主机 + 寄存器配置
    // ------------------------------------------------------------------
    wire        sccb_start, sccb_is_read, sccb_done, sccb_ack_err;
    wire [15:0] sccb_reg;
    wire [7:0]  sccb_wdata, sccb_rdata;

    reg  [7:0]  sccb_addr = 8'h78;      // OV5640 的 SCCB 从机地址 (7 位 0x3c << 1)

    sccb_master #(.CLK_HZ(SYS_HZ), .BIT_HZ(50_000)) u_sccb (
        .clk(clk24),
        .rst_n(rst_n),
        .start(sccb_start),
        .is_read(sccb_is_read),
        .reg_addr(sccb_reg),
        .wr_data(sccb_wdata),
        .slave_addr(sccb_addr),
        .probe_only(1'b0),
        .read_stop_start(1'b0),
        .busy(),
        .done(sccb_done),
        .rd_data(sccb_rdata),
        .ack_err(sccb_ack_err),
        .ack_ok_cnt(),
        .ack_chk_cnt(),
        .ack_fail_cnt(),
        .sda_idle(),
        .scl_idle(),
        .cam_drive_cnt(),
        .scl_mismatch_cnt(),
        .sda_pin_ok(),
        .scl_pin_ok(),
        .scl_low(scl_low),
        .sda_low(sda_low),
        .sda_in(sda_in),
        .scl_in(scl_in)
    );

    wire        cfg_start, cfg_busy, cfg_done, cfg_fail;
    wire        cfg_sccb_start, cfg_sccb_is_read;
    wire [15:0] cfg_sccb_reg;
    wire [7:0]  cfg_sccb_wdata;
    reg         cfg_start_r;

    assign sccb_start    = cfg_sccb_start;
    assign sccb_reg      = cfg_sccb_reg;
    assign sccb_wdata    = cfg_sccb_wdata;
    assign sccb_is_read  = cfg_sccb_is_read;
    assign cfg_start     = cfg_start_r;

    ov5640_cfg #(.CLK_HZ(SYS_HZ), .POWERUP_MS(300)) u_cfg (
        .clk(clk24),
        .rst_n(rst_n),
        .start(cfg_start),
        .busy(cfg_busy),
        .done(cfg_done),
        .fail(cfg_fail),
        .sccb_start(cfg_sccb_start),
        .sccb_is_read(cfg_sccb_is_read),
        .sccb_reg(cfg_sccb_reg),
        .sccb_wdata(cfg_sccb_wdata),
        .sccb_done(sccb_done),
        .sccb_ack_err(sccb_ack_err),
        .sccb_rdata(sccb_rdata),
        .rd0(), .rd1(), .rd2(), .rd3(), .rd4(), .rd5(), .rd6(), .rd7(),
        .rd8(), .rd9(), .rd10(), .rd11(),
        .nack_cnt(),
        .wr_cnt(),
        .rd_ok_cnt()
    );

    // ------------------------------------------------------------------
    //  DVP 采集 + 行缓冲
    // ------------------------------------------------------------------
    reg         req_tog;      // 翻转一次 = 采一段
    reg  [8:0]  req_row0;
    wire        ack_tog;
    wire [15:0] lb_lines;
    wire [31:0] lb_bytes;
    wire [10:0] lb_row_bytes;
    wire [AW-1:0] rb_addr;
    wire        rb_adv;
    wire [7:0]  rb_data;

`ifdef PHOTO_MINIMAL
    //  最小验证版: 不例化行缓冲 (因此没有那 20 个双时钟 BRAM),
    //  只循环发信标包 —— 用来二分"是不是 BRAM/内存把设计搞挂了"。
    assign lb_lines     = 16'd0;
    assign lb_bytes     = 32'd0;
    assign lb_row_bytes = 11'd0;
    assign rb_data      = 8'h80;
`else
    dvp_linebuf #(
        .KROWS(KROWS), .LINEB(LINEB), .FRAME_L(480), .AW(AW)
    ) u_lb (
        .pclk(PCLK),
        .clk24(clk24),
        .rst_n(rst_n),
        .d(D),
        .href(HREF),
        .vsync(VSYNC),
        .req_tog(req_tog),
        .req_row0(req_row0),
        .ack_tog(ack_tog),
        .lines_seen(lb_lines),
        .bytes_seen(lb_bytes),
        .last_row_bytes(lb_row_bytes),
        .rb_addr(rb_addr),
        .rb_data(rb_data)
    );
`endif

    //  ack_tog 从 PCLK 域同步到 clk24 域
    //  注意: 必须用 XOR 做边沿检测 (不是 & ~), 否则第 2 次以后的 ack
    //  (toggle 1->0) 永远检测不到, 采到第 2 段就卡死。
    reg ack_s1, ack_s2, ack_s2d;
    always @(posedge clk24) begin
        ack_s1  <= ack_tog;
        ack_s2  <= ack_s1;
        ack_s2d <= ack_s2;
    end
    wire ack_pulse = ack_s2 ^ ack_s2d;

    // ------------------------------------------------------------------
    //  串口打包发送
    // ------------------------------------------------------------------
    reg         tx_go;
    reg         tx_stat;
    reg  [8:0]  tx_row0;
    wire        tx_done;

    photo_tx #(
        .CLK_HZ(SYS_HZ), .BAUD(BAUD), .LINEB(LINEB), .KROWS(KROWS), .AW(AW)
    ) u_tx (
        .clk(clk24),
        .rst_n(rst_n),
        .go(tx_go),
        .stat_ena(tx_stat),
        .stat_data(stat_data),
        .row0(tx_row0),
        .done(tx_done),
        .rb_addr(rb_addr),
        .rb_adv(rb_adv),
        .rb_data(rb_data),
        .tx(TX)
    );

    // ------------------------------------------------------------------
    //  主状态机
    // ------------------------------------------------------------------
    localparam [3:0] ST_HELLO    = 0,  ST_CFG      = 1, ST_CFGWAIT  = 2,
                     ST_SETTLE   = 3,  ST_STAT     = 4, ST_WAITSTAT = 5,
                     ST_REQ      = 6,  ST_REQW     = 7, ST_WAITACK  = 8,
                     ST_GO       = 9,  ST_WAITTX   = 10, ST_DONE    = 11;

    reg [3:0]  st;
    reg [25:0] wait_cnt;      // 26 位 -> 最长 2.8 秒 (24MHz)
    reg [5:0]  seg_idx;       // 0..59
    reg [2:0]  req_delay;     // req_row0 先稳定几拍再翻 req_tog
    reg        stat_phase;    // 0 = 配置后的状态包, 1 = 每段之后的状态包
    reg        stop_flag;     // 发完状态包就停
    reg        hello_sent;    // 上电信标已经发过
    reg [7:0]  diag_code;     // 0=正常 1=配置失败 2=配置超时 3=上电信标
    reg [7:0]  ack_retry;     // ack 超时重试次数 (饱和)

    //  本段起始行号 = seg_idx * KROWS (9 位)
    wire [8:0] seg_row0 = seg_idx * KROWS;

    //  状态包内容 (16 字节, 小端, byte0 在前)
    //    byte0  = 诊断码 (0 正常 / 1 配置写失败 / 2 配置超时 / 3 上电信标)
    //    byte1  = flags: bit0=stop_flag bit1=stat_phase bit[6:2]=ack 重试次数
    //    byte2  = 当前段号
    //    byte3  = 保留
    //    byte4-5  = 累计采到的行数
    //    byte6-9  = 累计采到的字节数
    //    byte10-11= 最后一行采到的字节数
    //  注意每个字段都要补齐成 8/16/32 位, 否则拼接总宽对不上 128 位,
    //  字节位置会整体错位。
    wire [127:0] stat_data = {
        32'd0,                                        // byte15..12
        {5'd0, lb_row_bytes},                         // byte11..10 (16 位)
        lb_bytes,                                     // byte9..6   (32 位)
        lb_lines,                                     // byte5..4   (16 位)
        8'd0,                                         // byte3
        {2'd0, seg_idx},                              // byte2
        {1'b0, ack_retry[4:0], stat_phase, stop_flag},// byte1 = flags
        diag_code                                     // byte0
    };

    always @(posedge clk24) begin
        if (!rst_n) begin
            st         <= ST_HELLO;
            wait_cnt   <= 26'd0;
            seg_idx    <= 6'd0;
            req_tog    <= 1'b0;
            req_row0   <= 9'd0;
            req_delay  <= 3'd0;
            tx_go      <= 1'b0;
            tx_stat    <= 1'b0;
            tx_row0    <= 9'd0;
            cfg_start_r<= 1'b0;
            stat_phase <= 1'b0;
            stop_flag  <= 1'b0;
            hello_sent <= 1'b0;
            diag_code  <= 8'd0;
            ack_retry  <= 8'd0;
        end else begin
            tx_go       <= 1'b0;
            tx_stat     <= 1'b0;
            cfg_start_r <= 1'b0;

            case (st)
            //-----------------------------------------------------------
            ST_HELLO: begin
                //  上电信标: 复位后立刻发一个状态包, 用来确认"比特流跑起来了
                //  且 UART 通路是通的"。主机端一收到这个包就知道 FPGA 是活的,
                //  后面没数据就不是链路问题而是采集/配置问题。
                diag_code <= 8'd3;
                tx_go     <= 1'b1;
                tx_stat   <= 1'b1;
                st        <= ST_WAITSTAT;
            end
            //-----------------------------------------------------------
            ST_CFG: begin
                cfg_start_r <= 1'b1;
                wait_cnt    <= 26'd0;
                st          <= ST_CFGWAIT;
            end
            //-----------------------------------------------------------
            ST_CFGWAIT: begin
                //  等 271 个寄存器写完 (正常 ~0.5 秒)
                wait_cnt <= wait_cnt + 26'd1;
                if (cfg_done) begin
                    wait_cnt <= 26'd0;
                    st       <= ST_SETTLE;
                end else if (cfg_fail) begin
                    diag_code <= 8'd1;        // 有寄存器写失败
                    stop_flag <= 1'b1;
                    st        <= ST_STAT;
                end else if (wait_cnt >= 26'd48_000_000) begin
                    diag_code <= 8'd2;        // 配置根本没跑完
                    stop_flag <= 1'b1;
                    st        <= ST_STAT;
                end
            end
            //-----------------------------------------------------------
            ST_SETTLE: begin
                //  等相机进视频模式并稳定出流 (1 秒)
                wait_cnt <= wait_cnt + 26'd1;
                if (wait_cnt >= 26'd24_000_000) begin
                    wait_cnt  <= 26'd0;
                    stat_phase <= 1'b0;
                    st        <= ST_STAT;
                end
            end
            //-----------------------------------------------------------
            ST_STAT: begin
                tx_go   <= 1'b1;
                tx_stat <= 1'b1;
                st      <= ST_WAITSTAT;
            end
            //-----------------------------------------------------------
            ST_WAITSTAT: begin
                if (tx_done) begin
`ifdef PHOTO_MINIMAL
                    st <= ST_HELLO;           // 最小验证版: 循环发信标
`else
                    if (!hello_sent) begin
                        //  信标发完 -> 正式开始配置
                        hello_sent <= 1'b1;
                        diag_code  <= 8'd0;
                        wait_cnt   <= 26'd0;
                        st         <= ST_CFG;
                    end else if (stop_flag) begin
                        st <= ST_DONE;
                    end else if (!stat_phase) begin
                        seg_idx <= 6'd0;
                        st      <= ST_REQ;
                    end else if (seg_idx == NSEG-1) begin
                        st <= ST_DONE;
                    end else begin
                        seg_idx <= seg_idx + 6'd1;
                        st      <= ST_REQ;
                    end
`endif
                end
            end
            //-----------------------------------------------------------
            ST_REQ: begin
                //  先把行号放好, 等几拍再翻 req_tog, 保证跨域采样时数据已稳定
                req_row0  <= seg_row0;
                req_delay <= 3'd4;
                st        <= ST_REQW;
            end
            //-----------------------------------------------------------
            ST_REQW: begin
                req_delay <= req_delay - 3'd1;
                if (req_delay == 3'd0) begin
                    req_tog <= ~req_tog;
                    st      <= ST_WAITACK;
                end
            end
            //-----------------------------------------------------------
            ST_WAITACK: begin
                //  等行缓冲把这一段采完。超时 (2 秒) 就重新发一次请求 ——
                //  段在帧边界被打断时 linebuf 会作废本段, 这里重试即可。
                wait_cnt <= wait_cnt + 26'd1;
                if (ack_pulse) begin
                    wait_cnt <= 26'd0;
                    tx_row0  <= seg_row0;
                    st       <= ST_GO;
                end else if (wait_cnt >= 26'd48_000_000) begin
                    wait_cnt <= 26'd0;
                    if (ack_retry != 8'hFF) ack_retry <= ack_retry + 8'd1;
                    st       <= ST_REQ;
                end
            end
            //-----------------------------------------------------------
            ST_GO: begin
                tx_go <= 1'b1;
                tx_stat <= 1'b0;
                st    <= ST_WAITTX;
            end
            //-----------------------------------------------------------
            ST_WAITTX: begin
                if (tx_done) begin
                    stat_phase <= 1'b1;
                    st         <= ST_STAT;
                end
            end
            //-----------------------------------------------------------
            ST_DONE: begin
                //  保持
            end
            default: st <= ST_CFG;
            endcase
        end
    end

    // ------------------------------------------------------------------
    //  LED: 蓝=工作中, 绿=扫完一帧, 红=配置失败
    // ------------------------------------------------------------------
    wire cfg_failed = (st == ST_DONE) && (diag_code != 8'd0);
    assign LED_G = (st == ST_DONE) && !cfg_failed;
    assign LED_R = cfg_failed;
    assign LED_B = (st != ST_DONE);

endmodule

`default_nettype wire
