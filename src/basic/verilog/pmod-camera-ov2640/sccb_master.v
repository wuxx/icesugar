// ============================================================================
//  sccb_master.v -- OV2640 SCCB 主机 (类 I2C, 8 位寄存器地址)
//
//  ADDR8 = 1 (OV2640 默认):
//  写: START + ADDR_W + reg[7:0] + data + STOP
//  读方式A(重复起始 Sr): START + ADDR_W + reg + Sr + ADDR_R + data + NACK + STOP
//  读方式B(STOP+START):  START + ADDR_W + reg + STOP + START + ADDR_R + data + NACK + STOP
//  探测: START + ADDR_W + STOP            (只发地址字节, 看从机有没有应答)
//
//  ADDR8 = 0 (OV5640 那种 16 位寄存器地址):
//  写: START + ADDR_W + reg[15:8] + reg[7:0] + data + STOP
//  读方式A(重复起始 Sr): START + ADDR_W + reg_hi + reg_lo + Sr + ADDR_R + data + NACK + STOP
//  读方式B(STOP+START):  START + ADDR_W + reg_hi + reg_lo + STOP + START + ADDR_R + data + NACK + STOP
//
//  物理层为开漏: scl_low / sda_low = 1 表示拉低, 0 表示释放(高阻)
//  顶层用 SB_IO 三态实现: D_OUT_0 恒 0, OUTPUT_ENABLE = *_low, PULLUP=1
//
//  位时序 (每半位 HALF 个系统时钟):
//     相0: SCL 拉低, 同时把数据位放上 SDA, 等 HALF 拍
//     相1: SCL 释放(变高), 等 HALF 拍, 在中点采样
//  [重要] 相0 必须真的等 HALF 拍。之前的版本相0 只等 1 拍, 于是 SCL 低电平
//     只有 1 个系统时钟(24MHz 下 42ns), 从机根本识别不出 SCL 下降沿,
//     因此永远不会回 ACK (现象: acks=0, failed=全部)。
//
//  应答极性: 从机收到自己的地址后把 SDA 拉低(0)表示应答, 仍为高(1)才是没应答。
//
//  引脚诊断 (为了不再靠猜):
//     sda_pin_ok      自检: 释放 SDA 后引脚能回到高(上拉有效, 没被短路)
//     scl_pin_ok      自检 + 应答窗口内回读 SCL 确实为高
//     cam_drive_cnt   我们释放 SDA 时引脚仍为低的周期数 -> 相机在拉 SDA
//     scl_mismatch_cnt 应答窗口内 SCL 回读不为高的次数
// ============================================================================
`default_nettype none

module sccb_master #(
    parameter CLK_HZ = 24_000_000,   // 系统时钟
    parameter BIT_HZ = 50_000,       // SCCB 位时钟 (<=400kHz)
    parameter ADDR8  = 1             // 1 = 寄存器地址只有 1 个字节 (OV2640)
                              // 0 = 寄存器地址 2 个字节 (OV5640 的 0x3xxx)
)(
    input  wire        clk,
    input  wire        rst_n,

    // 命令接口
    input  wire        start,         // 单周期脉冲
    input  wire        is_read,       // 0=写 1=读
    input  wire [15:0] reg_addr,
    input  wire [7:0]  wr_data,
    input  wire [7:0]  slave_addr,    // 从机地址字节(写位=0); 读地址 = slave_addr|1
    input  wire        probe_only,    // 1 = 只发地址字节做探测
    input  wire        read_stop_start, // 1 = 读用 STOP+START, 0 = 用重复起始 Sr
    output wire        busy,
    output reg         done,          // 单周期脉冲, done 时 rd_data 有效
    output reg  [7:0]  rd_data,
    output reg         ack_err,       // 本次事务里有过没应答的字节
    output reg  [15:0] ack_ok_cnt,    // 累计收到应答的次数
    output reg  [15:0] ack_chk_cnt,   // 累计做了多少次应答检查
    output reg  [15:0] ack_fail_cnt,  // 累计有多少次没收到应答
    output reg         sda_idle,      // 总线空闲(已释放)时 SDA 的电平
    output reg         scl_idle,      // 总线空闲(已释放)时 SCL 的电平

    // 引脚诊断
    output reg  [31:0] cam_drive_cnt,
    output reg  [31:0] scl_mismatch_cnt,
    output reg         sda_pin_ok,
    output reg         scl_pin_ok,

    // 物理接口 (开漏)
    output reg         scl_low,
    output reg         sda_low,
    input  wire        sda_in,
    input  wire        scl_in
);

    localparam HALF = CLK_HZ / (BIT_HZ * 2);   // 半位周期(系统时钟数)
    localparam HALF_MID = HALF / 2;            // 高电平中点(采样点)

    localparam [4:0] ST_IDLE   = 0,
                     ST_BT0    = 1,   // 自检: 拉低 SCL+SDA
                     ST_BT1    = 2,   // 自检: 释放 SDA, 回读
                     ST_BT2    = 3,   // 自检: 释放 SCL, 回读
                     ST_START1 = 4,   // 总线空闲
                     ST_START2 = 5,   // SCL 高时 SDA 拉低 -> START
                     ST_START3 = 6,   // SCL 拉低
                     ST_TX     = 7,   // 发送一位
                     ST_TXACK  = 8,   // 等从机 ACK
                     ST_RX     = 9,   // 接收一位
                     ST_RXACK  = 10,  // 主机回 NACK
                     ST_STOP1  = 11,  // SCL 低 + SDA 低
                     ST_STOP2  = 12,  // 释放 SCL (SDA 仍低)
                     ST_STOP3  = 13,  // 释放 SDA -> STOP
                     ST_FIN    = 14,
                     //  重复起始 (Sr): SCL 先拉低 -> SDA 释放 -> SCL 拉高 -> SDA 拉低
                     ST_RST1   = 15,  // SCL 低, SDA 释放
                     ST_RST2   = 16,  // SCL 高, SDA 仍释放
                     ST_RST3   = 17,  // SCL 高时 SDA 拉低 -> Sr
                     ST_RST4   = 18;  // SCL 拉低, 准备发读地址

    reg [4:0]  st;
    reg [15:0] cnt;        // 半位计数
    reg        phase;      // 0=准备相位(SCL 低) 1=有效相位(SCL 高)
    reg [7:0]  sh;         // 发送移位寄存器 (MSB first)
    reg [7:0]  rx;         // 接收移位寄存器
    reg [3:0]  bitn;       // 位计数
    reg [2:0]  bi;         // 已完成发送的字节序号
    reg [15:0] ra;
    reg [7:0]  wd;
    reg        is_rd;
    reg        probe_r;     // 本次事务是"只发地址"的探测
    reg        ss_r;        // 本次读用 STOP+START
    reg [1:0]  rdst;        // 读序列阶段: 0 = 地址阶段, 1 = 读第二阶段, 2 = 读完成
    reg        bt_done;     // 自检是否做过

    wire tick = (cnt >= HALF-1);

    assign busy = (st != ST_IDLE);

    // ------------------------------------------------------------------
    //  引脚观测 (系统时钟域自由计数)
    //  cam_drive_cnt: 我们已释放 SDA, 但引脚仍被拉低 -> 是从机在驱动
    //  [注意] sda_pin_ok / scl_pin_ok / scl_mismatch_cnt 只能在下面那个
    //  主状态机 always 块里赋值。早先版本把它们放在这个块里复位, 而主
    //  状态机块里又有赋值 -> 同一个 reg 两个 always 块驱动, 结果不确定
    //  (表现为自检永远是 FAIL, 不匹配计数永远是 0)。
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            cam_drive_cnt <= 32'd0;
        end else begin
            if (!sda_low && !sda_in) cam_drive_cnt <= cam_drive_cnt + 1'b1;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            st <= ST_IDLE; cnt <= 0; phase <= 0;
            sh <= 8'h60; rx <= 0; bitn <= 0; bi <= 0;
            scl_low <= 1'b0; sda_low <= 1'b0;      // 复位后总线释放
            done <= 1'b0; rd_data <= 0; ack_err <= 1'b0;
            rdst <= 2'd0;
            ack_ok_cnt <= 16'd0; sda_idle <= 1'b1; scl_idle <= 1'b1;
            ack_chk_cnt <= 16'd0; ack_fail_cnt <= 16'd0;
            is_rd <= 1'b0; probe_r <= 1'b0; ss_r <= 1'b0; bt_done <= 1'b0;
            scl_mismatch_cnt <= 32'd0;
            sda_pin_ok <= 1'b0; scl_pin_ok <= 1'b0;
        end else begin
            done <= 1'b0;
            case (st)
            //---------------------------------------------------------------
            ST_IDLE: begin
                scl_low <= 1'b0; sda_low <= 1'b0;   // 总线空闲(释放)
                sda_idle <= sda_in;                 // 空闲时记录 SDA 电平(上拉是否有效)
                scl_idle <= scl_in;
                if (!bt_done) begin
                    st   <= ST_BT0;
                    cnt  <= 16'd0;
                end else if (start) begin
                    ra       <= reg_addr;
                    wd       <= wr_data;
                    is_rd    <= is_read;
                    probe_r  <= probe_only;
                    ss_r     <= read_stop_start;
                    bi       <= 3'd0;
                    //  第一段地址字节永远是"写地址"(OV2640 = 0x60)。
                    //  读事务是 START + ADDR_W + reg + (Sr 或 STOP+START) + ADDR_R + data
                    sh       <= slave_addr;
                    bitn     <= 4'd0;
                    ack_err  <= 1'b0;
                    rdst     <= 2'd0;
                    phase    <= 1'b0;
                    st       <= ST_START1;
                    cnt      <= 16'd0;
                end
            end
            //--------------------------------------------------------------- 引脚自检
            ST_BT0: begin                           // 同时拉低 SCL 和 SDA
                scl_low <= 1'b1; sda_low <= 1'b1;
                if (tick) begin st <= ST_BT1; cnt <= 0; end else cnt <= cnt+1;
            end
            ST_BT1: begin                           // 释放 SDA (SCL 仍低), 回读 SDA
                scl_low <= 1'b1; sda_low <= 1'b0;
                if (tick) begin
                    sda_pin_ok <= sda_in;           // 期望 1 (上拉有效)
                    st   <= ST_BT2;
                    cnt  <= 0;
                end else cnt <= cnt+1;
            end
            ST_BT2: begin                           // 释放 SCL, 回读 SCL
                scl_low <= 1'b0; sda_low <= 1'b0;
                if (tick) begin
                    scl_pin_ok <= scl_in;           // 期望 1 (上拉有效)
                    bt_done <= 1'b1;
                    st   <= ST_IDLE;
                    cnt  <= 0;
                end else cnt <= cnt+1;
            end
            //--------------------------------------------------------------- START
            ST_START1: begin                        // SCL/SDA 都释放
                scl_low <= 1'b0; sda_low <= 1'b0;
                if (tick) begin st <= ST_START2; cnt <= 0; end else cnt <= cnt+1;
            end
            ST_START2: begin                        // SCL 高, SDA 拉低 -> START
                sda_low <= 1'b1;
                if (tick) begin st <= ST_START3; cnt <= 0; end else cnt <= cnt+1;
            end
            ST_START3: begin                        // SCL 拉低 -> 进入第一位
                scl_low <= 1'b1;
                if (tick) begin st <= ST_TX; cnt <= 0; phase <= 1'b0; end else cnt <= cnt+1;
            end
            //--------------------------------------------------------------- 重复起始 Sr
            ST_RST1: begin                          // SCL 拉低, SDA 释放(从机交回 SDA)
                scl_low <= 1'b1; sda_low <= 1'b0;
                if (tick) begin st <= ST_RST2; cnt <= 0; end else cnt <= cnt+1;
            end
            ST_RST2: begin                          // SCL 拉高, SDA 保持释放
                scl_low <= 1'b0; sda_low <= 1'b0;
                if (tick) begin st <= ST_RST3; cnt <= 0; end else cnt <= cnt+1;
            end
            ST_RST3: begin                          // SCL 高时 SDA 拉低 -> 重复起始
                scl_low <= 1'b0; sda_low <= 1'b1;
                if (tick) begin st <= ST_RST4; cnt <= 0; end else cnt <= cnt+1;
            end
            ST_RST4: begin                          // SCL 拉低, 准备发读地址
                scl_low <= 1'b1; sda_low <= 1'b0;
                if (tick) begin st <= ST_TX; cnt <= 0; phase <= 1'b0; end else cnt <= cnt+1;
            end
            //--------------------------------------------------------------- 发送一位
            ST_TX: begin
                if (!phase) begin
                    scl_low <= 1'b1;                // SCL 低, 期间放上数据
                    sda_low <= sh[7] ? 1'b0 : 1'b1; // 1 -> 释放, 0 -> 拉低
                    if (tick) begin                 // 低电平期必须等满 HALF 拍
                        phase <= 1'b1;
                        cnt   <= 16'd0;
                    end else cnt <= cnt+1'b1;
                end else begin
                    scl_low <= 1'b0;                // 释放 SCL, 本位被采样
                    if (tick) begin
                        phase <= 1'b0;
                        cnt   <= 16'd0;
                        sh    <= {sh[6:0], 1'b1};
                        if (bitn == 4'd7) begin
                            bitn <= 4'd0;
                            st   <= ST_TXACK;
                        end else begin
                            bitn <= bitn + 1'b1;
                        end
                    end else cnt <= cnt+1;
                end
            end
            //--------------------------------------------------------------- 从机 ACK
            ST_TXACK: begin
                if (!phase) begin
                    scl_low <= 1'b1;
                    sda_low <= 1'b0;                // 释放 SDA, 等从机应答
                    if (tick) begin
                        phase <= 1'b1; cnt <= 16'd0;
                    end else cnt <= cnt+1'b1;
                end else begin
                    scl_low <= 1'b0;
                    //  在 SCL 高电平中点采样应答
                    if (cnt == HALF_MID) begin
                        ack_chk_cnt <= ack_chk_cnt + 1'b1;
                        if (sda_in) begin
                            ack_err     <= 1'b1;
                            ack_fail_cnt <= ack_fail_cnt + 1'b1;
                        end else begin
                            ack_ok_cnt <= ack_ok_cnt + 1'b1;
                        end
                        //  同一时刻回读 SCL: 必须是高, 否则从机根本看不到时钟
                        if (scl_in == 1'b0) begin
                            scl_pin_ok       <= 1'b0;
                            scl_mismatch_cnt <= scl_mismatch_cnt + 1'b1;
                        end
                    end
                    if (tick) begin
                        phase <= 1'b0; cnt <= 16'd0;
                        if (rdst == 2'd1) begin
                            st   <= ST_RX;               // 读地址已发完 -> 开始收数据
                            bitn <= 4'd0;
                            rx   <= 8'h00;
                        end else if (probe_r && bi == 3'd0) begin
                            st <= ST_STOP1;              // 探测: 地址发完就停
                        end else if (!is_rd && (bi == (ADDR8 ? 3'd2 : 3'd3))) begin
                            st <= ST_STOP1;              // 写: 数据字节已发完
                        end else if (is_rd && (bi == (ADDR8 ? 3'd1 : 3'd2))) begin
                            //  读: 寄存器地址已发完 ->
                            //    方式A: 重复起始 Sr 再发读地址
                            //    方式B: 先 STOP, 再重新 START 发读地址
                            rdst <= 2'd1;
                            sh   <= (slave_addr | 8'h01);
                            bitn <= 4'd0;
                            bi   <= 3'd0;
                            cnt  <= 16'd0;
                            if (ss_r) st <= ST_STOP1;     // 走 STOP, ST_STOP3 会转去 START
                            else    st <= ST_RST1;
                        end else begin
                            // 装载下一个要发的字节 (已发 bi, 下一个是 bi+1)
                            case (bi)
                            3'd0: sh <= ADDR8 ? ra[7:0] : ra[15:8];
                            3'd1: sh <= ADDR8 ? wd : ra[7:0];
                            3'd2: sh <= (is_rd ? (slave_addr | 8'h01) : wd);
                            default: sh <= slave_addr;
                            endcase
                            bi    <= bi + 1'b1;
                            st    <= ST_TX;
                            phase <= 1'b0;
                        end
                    end else cnt <= cnt+1;
                end
            end
            //--------------------------------------------------------------- 接收一位
            ST_RX: begin
                if (!phase) begin
                    scl_low <= 1'b1;
                    sda_low <= 1'b0;                // 释放 SDA, 由从机驱动
                    if (tick) begin
                        phase <= 1'b1; cnt <= 16'd0;
                    end else cnt <= cnt+1'b1;
                end else begin
                    scl_low <= 1'b0;
                    if (tick) begin
                        phase <= 1'b0; cnt <= 16'd0;
                        rx    <= {rx[6:0], sda_in};
                        if (bitn == 4'd7) begin
                            bitn <= 4'd0;
                            st   <= ST_RXACK;
                        end else bitn <= bitn + 1'b1;
                    end else cnt <= cnt+1;
                end
            end
            //--------------------------------------------------------------- 主机回 NACK
            ST_RXACK: begin
                if (!phase) begin
                    scl_low <= 1'b1;
                    sda_low <= 1'b0;                // 释放 SDA = NACK(不拉低)
                    if (tick) begin
                        phase <= 1'b1; cnt <= 16'd0;
                    end else cnt <= cnt+1'b1;
                end else begin
                    scl_low <= 1'b0;
                    if (tick) begin
                        phase <= 1'b0; cnt <= 16'd0;
                        rd_data <= rx;
                        rdst    <= 2'd2;              // 读数据阶段完成
                        st     <= ST_STOP1;
                    end else cnt <= cnt+1;
                end
            end
            //--------------------------------------------------------------- STOP
            ST_STOP1: begin                        // SCL 低, SDA 低
                scl_low <= 1'b1; sda_low <= 1'b1;
                if (tick) begin st <= ST_STOP2; cnt <= 0; end else cnt <= cnt+1;
            end
            ST_STOP2: begin                        // 释放 SCL (SDA 仍低)
                scl_low <= 1'b0; sda_low <= 1'b1;
                if (tick) begin st <= ST_STOP3; cnt <= 0; end else cnt <= cnt+1;
            end
            ST_STOP3: begin                        // 释放 SDA -> STOP
                scl_low <= 1'b0; sda_low <= 1'b0;
                if (tick) begin
                    cnt <= 0;
                    //  读方式B: STOP 之后重新 START, 继续读阶段
                    if (rdst == 2'd1) st <= ST_START1;
                    else             st <= ST_FIN;
                end else cnt <= cnt+1;
            end
            ST_FIN: begin
                if (tick) begin
                    st   <= ST_IDLE;
                    done <= 1'b1;
                end else cnt <= cnt+1;
            end
            default: st <= ST_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
