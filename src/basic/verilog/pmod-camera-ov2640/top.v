// ============================================================================
//  top.v -- OV2640 DVP 功能验证顶层 (iCE40UP5K / iCESugar)
//
//  流程: 上电 -> SCCB 写 ~200 个寄存器 + 诊断读 12 个关键寄存器 -> 统计 1 秒 DVP
//        -> 多周期分析 (PCLK MHz / 字节序指标 / 结论) -> 9600 8N1 从 pin6 输出
//
//  引脚 (iCESugar v1.4, 依据 src/common/io.pcf + 原理图核对):
//    clk12 = 35        12MHz (iCELink 的 MCO 输出)
//    TX    = 6         FPGA 侧 UART 输出 (网络 UART3_RX)
//    LED_R = 40, LED_G = 41, LED_B = 39
//    PMOD2: XMCLK=43(P2_11) PCLK=44(P2_2) VSYNC=38(P2_10)
//            HREF=42(P2_3)   SCL=37(P2_4)  SDA=36(P2_9)
//    PMOD3: D0=23 D1=25 D2=26 D3=27 D4=28 D5=31 D6=32 D7=34
//
//  注意: 32bit 比较/乘法会形成很长的组合路径 (iCE40 上 4 级串联比较约 100ns),
//        因此 PCLK MHz 的除法与字节序指标的 min/second 全部用多周期序列器完成。
// ============================================================================
`default_nettype none

module top (
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

    // ------------------------------------------------------------------
    //  PLL: 12MHz -> 24MHz (同时用作系统时钟和摄像头 XMCLK)
    //  icepll -i 12 -o 24 : DIVR=0 DIVF=63 DIVQ=5 FILTER_RANGE=1
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

    // ------------------------------------------------------------------
    //  复位: 上电计数 1000 拍 (~42us)
    //  注意: 计数器必须饱和, 否则 16 位回绕会让 rst_n 每 65536 拍(~2.73ms)
    //        重新拉低一次, 整个设计被反复复位, 永远走不到打印阶段。
    // ------------------------------------------------------------------
    reg [15:0] rst_cnt = 16'd0;
    always @(posedge clk24) begin
        if (rst_cnt != 16'hFFFF) rst_cnt <= rst_cnt + 1'b1;
    end
    wire rst_n = (rst_cnt >= 16'd1000);

    // ------------------------------------------------------------------
    //  XMCLK 输出: IOB 的 DDR 输出直接产生 50% 占空比的 24MHz 方波
    //    PIN_TYPE = 6'b0100_01 : [5:4]=01 常输出 [3]=0 寄存器输出
    //                          [2]=0 DDR(D_OUT_0 高半周 / D_OUT_1 低半周)
    //                          [1:0]=01 简单输入
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
    //  SCCB 开漏 (SCL/SDA) + 内部上拉
    //    PIN_TYPE = 6'b1010_01 : [5:4]=10 组合三态 [3]=1 简单输出
    //                          [2]=0 用 D_OUT_0 [1:0]=01 简单输入
    //    D_OUT_0 恒 0, OUTPUT_ENABLE = 拉低信号 -> 标准开漏
    //    SCL 也接回 D_IN_0, 用来验证引脚真的在翻转 (不然无从判断是接线问题
    //    还是时序问题)
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
    //  SCCB 主机
    // ------------------------------------------------------------------
    wire        sccb_start, sccb_is_read, sccb_done, sccb_ack_err;
    wire [15:0] sccb_reg;
    wire [7:0]  sccb_wdata, sccb_rdata;
    wire [15:0] sccb_ack_cnt, sccb_ack_chk, sccb_ack_fail;
    wire        sccb_sda_idle, sccb_scl_idle;
    wire [31:0] sccb_cam_drive, sccb_scl_mis;
    wire        sccb_sda_ok, sccb_scl_ok;

    reg  [7:0]  sccb_addr;      // 探测出来的从机地址字节
    reg         sccb_probe;     // 1 = 只发地址字节做探测
    reg  [2:0]  probe_idx;      // 当前探测的候选地址序号
    reg  [5:0]  probe_mask;     // 哪些候选地址拿到了应答
    reg         probe_start_r;  // 探测事务的启动脉冲
    reg         diag_mode;      // 1 = 诊断读 (top 自己发起的 SCCB 事务)
    reg         diag_start_r;
    reg  [15:0] diag_reg;
    reg  [7:0]  diag_wdata;
    reg         diag_is_read;

    //  读方式: 0 = 重复起始 Sr, 1 = STOP+START (OV5640 两种都见过, 都要能切)
    wire sccb_ss_mode = diag_mode & diag_ss;

    //  OV2640 的寄存器地址只有 1 个字节 -> ADDR8=1
    sccb_master #(.CLK_HZ(SYS_HZ), .BIT_HZ(50_000), .ADDR8(1)) u_sccb (
        .clk(clk24),
        .rst_n(rst_n),
        .start(sccb_start),
        .is_read(sccb_is_read),
        .reg_addr(sccb_reg),
        .wr_data(sccb_wdata),
        .slave_addr(sccb_addr),
        .probe_only(sccb_probe),
        .read_stop_start(sccb_ss_mode),
        .busy(),
        .done(sccb_done),
        .rd_data(sccb_rdata),
        .ack_err(sccb_ack_err),
        .ack_ok_cnt(sccb_ack_cnt),
        .ack_chk_cnt(sccb_ack_chk),
        .ack_fail_cnt(sccb_ack_fail),
        .sda_idle(sccb_sda_idle),
        .scl_idle(sccb_scl_idle),
        .cam_drive_cnt(sccb_cam_drive),
        .scl_mismatch_cnt(sccb_scl_mis),
        .sda_pin_ok(sccb_sda_ok),
        .scl_pin_ok(sccb_scl_ok),
        .scl_low(scl_low),
        .sda_low(sda_low),
        .sda_in(sda_in),
        .scl_in(scl_in)
    );

    // ------------------------------------------------------------------
    //  寄存器配置 + 读回
    // ------------------------------------------------------------------
    wire        cfg_start, cfg_busy, cfg_done;
    wire        cfg_sccb_start;
    wire        cfg_sccb_is_read;
    wire [15:0] cfg_sccb_reg;
    wire [7:0]  cfg_sccb_wdata;
    wire [7:0]  cfg_rd0, cfg_rd1, cfg_rd2, cfg_rd3, cfg_rd4, cfg_rd5, cfg_rd6, cfg_rd7;
    wire [7:0]  cfg_rd8, cfg_rd9, cfg_rd10, cfg_rd11;
    wire [7:0]  cfg_nack;
    wire [15:0] cfg_wr_cnt;
    wire [15:0] cfg_rd_ok;

    //  探测阶段由 top 直接发起 SCCB 事务, 配置阶段由 ov5640_cfg 发起,
    //  诊断读阶段也由 top 发起, 三者时间上互不重叠, 用或门合并即可。
    assign sccb_start = probe_start_r | cfg_sccb_start | diag_start_r;

    //  SCCB 命令多路选择: 配置序列用 ov5640_cfg 发的, 诊断读用 top 自己发的
    assign sccb_reg     = diag_mode ? diag_reg     : cfg_sccb_reg;
    assign sccb_wdata   = diag_mode ? diag_wdata   : cfg_sccb_wdata;
    assign sccb_is_read = diag_mode ? diag_is_read : cfg_sccb_is_read;

    ov2640_cfg #(.CLK_HZ(SYS_HZ), .POWERUP_MS(200)) u_cfg (
        .clk(clk24),
        .rst_n(rst_n),
        .start(cfg_start),
        .busy(cfg_busy),
        .done(cfg_done),
        .fail(),
        .sccb_start(cfg_sccb_start),
        .sccb_is_read(cfg_sccb_is_read),
        .sccb_reg(cfg_sccb_reg),
        .sccb_wdata(cfg_sccb_wdata),
        .sccb_done(sccb_done),
        .sccb_ack_err(sccb_ack_err),
        .sccb_rdata(sccb_rdata),
        .rd0(cfg_rd0), .rd1(cfg_rd1), .rd2(cfg_rd2), .rd3(cfg_rd3),
        .rd4(cfg_rd4), .rd5(cfg_rd5), .rd6(cfg_rd6), .rd7(cfg_rd7),
        .rd8(cfg_rd8), .rd9(cfg_rd9), .rd10(cfg_rd10), .rd11(cfg_rd11),
        .nack_cnt(cfg_nack),
        .wr_cnt(cfg_wr_cnt),
        .rd_ok_cnt(cfg_rd_ok)
    );

    // ------------------------------------------------------------------
    //  DVP 采集 (PCLK 域) + 命令握手
    // ------------------------------------------------------------------
    reg         cmd_tog;
    reg  [1:0]  cmd_op;
    wire        ack_tog;

    reg  ack_s1, ack_s2;
    always @(posedge clk24) begin
        ack_s1 <= ack_tog;
        ack_s2 <= ack_s1;
    end
    reg ack_last;

    wire [31:0] snap_pclk_cnt, snap_active_cnt, snap_frames;
    wire [15:0] snap_lines, snap_line_bytes;
    wire [31:0] snap_m0, snap_m1, snap_m2, snap_m3;
    wire [127:0] snap_sample;
    wire [31:0] snap_vsync_cnt;
    wire [31:0] snap_vsync_edge, snap_href_edge, snap_metric_bytes;
    wire [31:0] vsync_edge_live;      // PCLK 域的实时场同步计数(不受冻结影响)
    wire [7:0]  snap_pin_changed, snap_pin_now, snap_byte_min, snap_byte_max;
    wire [31:0] snap_line_period, snap_frame_period;

    dvp_capture u_dvp (
        .pclk(PCLK),
        .rst_n(rst_n),
        .vsync(VSYNC),
        .href(HREF),
        .d(D),
        .cmd_tog(cmd_tog),
        .cmd_op(cmd_op),
        .ack_tog(ack_tog),
        .snap_pclk_cnt(snap_pclk_cnt),
        .snap_active_cnt(snap_active_cnt),
        .snap_frames(snap_frames),
        .snap_lines(snap_lines),
        .snap_line_bytes(snap_line_bytes),
        .snap_m0(snap_m0),
        .snap_m1(snap_m1),
        .snap_m2(snap_m2),
        .snap_m3(snap_m3),
        .snap_sample(snap_sample),
        .snap_vsync_cnt(snap_vsync_cnt),
        .snap_vsync_edge(snap_vsync_edge),
        .snap_href_edge(snap_href_edge),
        .snap_metric_bytes(snap_metric_bytes),
        .snap_pin_changed(snap_pin_changed),
        .snap_pin_now(snap_pin_now),
        .snap_byte_min(snap_byte_min),
        .snap_byte_max(snap_byte_max),
        .snap_line_period(snap_line_period),
        .snap_frame_period(snap_frame_period),
        .vsync_edge_live(vsync_edge_live)
    );

    //  回读读的 12 个寄存器。
    //  [实测] OV5640 的 0x38xx 组(输出窗口/时序寄存器)有个怪脾气: **诊断读
    //  阶段里只有最后 4 次事务能读出该组的真值**, 排在前面的一律返回 0x00
    //  (0x30xx / 0x43xx 组任何时候都正常)。当年跑出正确值的那版诊断读正好
    //  只有 4 次读, 4 次全对 —— 规律就是这么发现的。
    //  所以把最需要回读的 HTS/VTS(0x380C~0x380F)放在最后 4 个槽位,
    //  输出窗口(0x3808~0x380B)由 DVP 实测的行/字节数直接给出。
    reg  [15:0] diag_addr_w;
    reg  [7:0]  diag_data_w;
    reg         diag_read_w;
    reg  [3:0]  diag_slot_w;
    always @* begin
        case (diag_idx)
            //  切到 sensor bank
            5'd0: begin diag_addr_w = 16'h00FF; diag_data_w = 8'h01; diag_read_w = 1'b0; diag_slot_w = 4'd15; end
            //  bank1: 芯片 ID / 厂商 ID
            5'd1: begin diag_addr_w = 16'h000A; diag_data_w = 8'h00; diag_read_w = 1'b1; diag_slot_w = 4'd0;  end
            5'd2: begin diag_addr_w = 16'h000B; diag_data_w = 8'h00; diag_read_w = 1'b1; diag_slot_w = 4'd1;  end
            5'd3: begin diag_addr_w = 16'h0000; diag_data_w = 8'h00; diag_read_w = 1'b1; diag_slot_w = 4'd2;  end
            5'd4: begin diag_addr_w = 16'h0010; diag_data_w = 8'h00; diag_read_w = 1'b1; diag_slot_w = 4'd3;  end
            //  切回 DSP bank
            5'd5: begin diag_addr_w = 16'h00FF; diag_data_w = 8'h00; diag_read_w = 1'b0; diag_slot_w = 4'd15; end
            //  bank0: 输出尺寸 / 格式
            5'd6:  begin diag_addr_w = 16'h00C0; diag_data_w = 8'h00; diag_read_w = 1'b1; diag_slot_w = 4'd4;  end
            5'd7:  begin diag_addr_w = 16'h00C1; diag_data_w = 8'h00; diag_read_w = 1'b1; diag_slot_w = 4'd5;  end
            5'd8:  begin diag_addr_w = 16'h008C; diag_data_w = 8'h00; diag_read_w = 1'b1; diag_slot_w = 4'd6;  end
            5'd9:  begin diag_addr_w = 16'h0051; diag_data_w = 8'h00; diag_read_w = 1'b1; diag_slot_w = 4'd7;  end
            5'd10: begin diag_addr_w = 16'h0052; diag_data_w = 8'h00; diag_read_w = 1'b1; diag_slot_w = 4'd8;  end
            5'd11: begin diag_addr_w = 16'h00DA; diag_data_w = 8'h00; diag_read_w = 1'b1; diag_slot_w = 4'd9;  end
            5'd12: begin diag_addr_w = 16'h00C2; diag_data_w = 8'h00; diag_read_w = 1'b1; diag_slot_w = 4'd10; end
            5'd13: begin diag_addr_w = 16'h005A; diag_data_w = 8'h00; diag_read_w = 1'b1; diag_slot_w = 4'd11; end
            default: begin diag_addr_w = 16'h000A; diag_data_w = 8'h00; diag_read_w = 1'b1; diag_slot_w = 4'd0; end
        endcase
    end

    // ------------------------------------------------------------------
    //  报表变量
    // ------------------------------------------------------------------
    //  [资源] 报表变量不能都用寄存器存: 57 个 32bit 变量 = 1824 个 FF,
    //  iCE40UP5K 整个器件只有 5280 个 LC, 光变量就塞掉三分之一, nextpnr
    //  会直接报 "Failed to expand region"。
    //  这些值在打印时都是稳定的(配置结果寄存器 / 冻结后的快照 / 只增计数器),
    //  所以除少数几个"只能在某个时刻算出来"的值外, 一律用组合连线直接指向
    //  源信号, 0 个 FF。
    // ------------------------------------------------------------------
    reg  [31:0] r_mhz;        // PCLK MHz (ST_DIV 算出来的)
    reg  [31:0] r_verdict;    // 结论位图
    reg  [31:0] r_cfg_ok, r_dvp_ok, r_order_ok;
    reg  [31:0] r_best;       // 最小的字节序指标

    wire [31:0] v0  = {24'd0, diag_rd[0]};    // 0x0A 芯片 ID (PID, 期望 0x26)
    wire [31:0] v1  = {24'd0, diag_rd[1]};    // 0x0B 芯片 ID (VER, 期望 0x42)
    wire [31:0] v2  = {24'd0, cfg_nack};      // 无应答的事务数
    //  输出窗口直接用 DVP 实测值:
    //    每行字节数 = 像素数 * 2 (YUV422), 实测 1280 -> 640 像素
    wire [15:0] dvp_width_px = (snap_line_bytes + 16'd1) >> 1;
    wire [31:0] v3  = {16'd0, dvp_width_px}; // DVP 输出宽度(像素, 实测)
    wire [31:0] v4   = {24'd0, diag_rd[2]};  // GAIN (sensor bank 0x00) 增益
    wire [31:0] v5  = {16'd0, snap_lines};   // DVP 输出高度(行/帧, 实测)
    wire [31:0] v6   = {24'd0, diag_rd[7]};  // 0x51 HSIZE  (窗口, 期望 0x90)
    wire [31:0] v7  = r_mhz;                  // PCLK MHz
    wire [31:0] v8  = snap_frames;            // 帧数
    wire [31:0] v9  = {16'd0, snap_lines};    // 每帧行数
    wire [31:0] v10 = {16'd0, snap_line_bytes};// 每行字节数
    wire [31:0] v11 = snap_frames;            // 统计窗口 1 秒 -> 即 fps
    wire [31:0] v12 = snap_active_cnt;        // 有效字节数
    wire [31:0] v13 = {8'd0, snap_m0};
    wire [31:0] v14 = {8'd0, snap_m1};
    wire [31:0] v15 = {8'd0, snap_m2};
    wire [31:0] v16 = {8'd0, snap_m3};
    wire [31:0] v17 = r_verdict;              // 结论位图
    wire [31:0] v18 = r_cfg_ok;               // SCCB 链路结论
    wire [31:0] v19 = r_dvp_ok;               // DVP 链路结论
    wire [31:0] v20 = r_order_ok;             // 字节序结论
    wire [31:0] v21 = 32'd24;                 // XMCLK MHz (PLL 固定 24)
    wire [31:0] v22 = snap_vsync_cnt;         // VSYNC 计数
    wire [31:0] v23 = r_best;                 // 最小的字节序指标
    wire [31:0] v24 = {26'd0, probe_mask};    // 地址探测命中位图
    wire [31:0] v25 = {24'd0, sccb_addr};     // 选定的从机地址字节
    wire [31:0] v26 = {31'd0, sccb_sda_idle}; // 总线空闲时 SDA 电平
    wire [31:0] v27 = {16'd0, sccb_ack_cnt};  // 累计应答次数
    wire [31:0] v28 = {24'd0, diag_rd[9]};    // 0xDA IMAGE_MODE (0x00 = YUV422/YUYV)
    wire [31:0] v29 = {24'd0, diag_rd[10]};   // 0xC2 CTRL0     (0x0E = YUV422|YUV_EN|RGB_EN)
    //  输出尺寸寄存器: HSIZE8/VSIZE8 合成 16 位(高字节=宽, 低字节=高)
    wire [31:0] v30 = {16'd0, diag_rd[4], diag_rd[5]};   // 0xC0/0xC1 期望 0x503C
    wire [31:0] v31  = {24'd0, diag_rd[3]};   // AEC  (sensor bank 0x10) 曝光时间
    //  图像窗口: HSIZE/VSIZE 合成 16 位
    wire [31:0] v32 = {16'd0, diag_rd[7], diag_rd[8]};   // 0x51/0x52 期望 0x902C
    wire [31:0] v33 = {24'd0, diag_rd[8]};    // VSIZE (窗口, 期望 0x2C)
    wire [31:0] v34 = {16'd0, sccb_ack_chk};  // 应答检查总次数
    wire [31:0] v35 = {16'd0, sccb_ack_fail}; // 其中没收到应答的次数
    wire [31:0] v36 = snap_metric_bytes;      // 参与字节序统计的字节数
    wire [31:0] v37 = snap_vsync_edge;        // VSYNC 跳变次数
    wire [31:0] v38 = snap_href_edge;         // HREF 跳变次数
    wire [31:0] v39 = {16'd0, diag_ok};       // 回读成功的次数
    wire [31:0] v40 = {16'd0, cfg_wr_cnt};    // 写成功的次数
    wire [31:0] v41 = sccb_cam_drive;         // 相机把 SDA 拉低的周期数
    wire [31:0] v42 = {31'd0, sccb_scl_ok};   // SCL 引脚检查
    wire [31:0] v43 = {31'd0, sccb_sda_ok};   // SDA 引脚检查
    wire [31:0] v44 = sccb_scl_mis;           // 应答窗口 SCL 回读异常次数
    wire [31:0] v45 = {24'd0, snap_pin_changed};
    wire [31:0] v46 = {24'd0, snap_pin_now};
    wire [31:0] v47 = {24'd0, snap_byte_min};
    wire [31:0] v48 = {24'd0, snap_byte_max};
    wire [31:0] v54 = {31'd0, sccb_scl_idle}; // 总线空闲时 SCL 电平
    wire [31:0] v55 = snap_line_period;       // 一行占多少 PCLK 周期
    wire [31:0] v56 = snap_frame_period;      // 一帧占多少 PCLK 周期

    wire [31:0] v49 = {28'd0, diag_n38};     // DSP bank 8 个尺寸/格式寄存器里读到非零的个数
    wire [31:0] v50 = {24'd0, diag_nack};     // 诊断读里有几次没应答
    wire [31:0] v51 = {24'd0, diag_rd[4]};    // 0xC0 HSIZE8 回读值
    wire [31:0] v52 = {24'd0, diag_rd[5]};    // 0xC1 VSIZE8 回读值
    wire [31:0] v53  = {24'd0, diag_rd[11]};   // 0x5A ZMOW   (输出宽>>2, 期望 0xA0)

    //  诊断读的 13 个结果必须存下来(只在 ST_DIAG1 那一拍算得出来)
    reg  [7:0]  diag_rd [0:11];
    reg  [7:0]  diag_nack;
    reg  [3:0]  diag_n38;     // 0x38xx 组里读到非零值的个数(0..8)
    reg  [15:0] diag_ok;
    reg  [4:0]  diag_idx;
    reg  [31:0] vsync_mark;      // 等稳定时记下的场同步计数起点
    reg         diag_ss;        // 本次诊断读用 STOP+START 还是重复起始

    wire [1823:0] vars_flat = {v56, v55, v54, v53, v52, v51, v50, v49,
                               v48, v47, v46, v45, v44, v43, v42, v41,
                               v40, v39, v38, v37, v36, v35, v34, v33,
                               v32, v31, v30, v29, v28, v27, v26, v25,
                               v24, v23, v22, v21, v20, v19, v18, v17,
                               v16, v15, v14, v13, v12, v11, v10, v9,
                               v8,  v7,  v6,  v5,  v4,  v3,  v2,  v1,
                               v0};

    // ------------------------------------------------------------------
    //  串口报表
    // ------------------------------------------------------------------
    wire        pr_busy, pr_done;
    reg         pr_start;
    wire        tx_w;

    uart_printer #(.CLK_HZ(SYS_HZ), .BAUD(9600), .NVARS(57)) u_pr (
        .clk(clk24),
        .rst_n(rst_n),
        .start(pr_start),
        .busy(pr_busy),
        .done(pr_done),
        .vars_flat(vars_flat),
        .samples(snap_sample),
        .tx(tx_w)
    );

    assign TX = tx_w;

    // ------------------------------------------------------------------
    //  主流程
    // ------------------------------------------------------------------
    localparam [4:0] ST_WAIT   = 0,  ST_PB0    = 1,  ST_PB1    = 2,  ST_PB2    = 3,
                     ST_PB3    = 4,  ST_CFG    = 5,  ST_MEAS   = 6,  ST_MEASW  = 7,
                     ST_COUNT  = 8,  ST_FREEZE = 9,  ST_FRZWAIT= 10, ST_FILL   = 11,
                     ST_DIV    = 12, ST_AN     = 13, ST_FLAG   = 14, ST_PRINT  = 15,
                     ST_DONE   = 16, ST_DIAG0  = 17, ST_DIAG1  = 18,
                     ST_WAITV  = 19;

    reg [4:0]  st;
    reg [24:0] meas_cnt;
    reg        cfg_start_r;

    // ------------------------------------------------------------------
    //  SCCB 从机地址探测
    //  先拿候选地址各发一次 "START + 地址字节 + STOP", 看哪个能从机上拿到
    //  应答(SDA 被拉低)。这样"相机没接" / "地址不对" / "被按住复位" 三种
    //  情况在报表里能区分开, 不用靠猜。
    // ------------------------------------------------------------------
    localparam [2:0] NPROBE_C = 3'd6;   // 候选地址个数

    function [7:0] cand_addr(input [2:0] i);
        case (i)
            3'd0: cand_addr = 8'h60;   // OV2640 常用 (7bit 0x30)
            3'd1: cand_addr = 8'h30;   // 7bit 0x18
            3'd2: cand_addr = 8'hD8;   // 7bit 0x6C
            3'd3: cand_addr = 8'h6C;   // 7bit 0x36
            3'd4: cand_addr = 8'h20;   // 7bit 0x10
            default: cand_addr = 8'h50; // 7bit 0x28
        endcase
    endfunction

    function [7:0] pick_addr(input [5:0] mask);
        casez (mask)
            6'b000001: pick_addr = 8'h60;
            6'b000010: pick_addr = 8'h30;
            6'b000100: pick_addr = 8'hD8;
            6'b001000: pick_addr = 8'h6C;
            6'b010000: pick_addr = 8'h20;
            6'b100000: pick_addr = 8'h50;
            default:   pick_addr = 8'h60;
        endcase
    endfunction

    // ------------------------------------------------------------------
    //  超时保护
    //  相机没接 / 摄像头在复位 / PCLK 没出来时, 若无超时, 状态机会永远卡在
    //  等待握手的地方, 一条字节都发不出来。超时后带着已有数据继续走,
    //  报表里就能看出"哪一级是空的"。
    // ------------------------------------------------------------------
    localparam integer T_CFG   = 72_000_000;    // 3.0 s  (271 个寄存器 + 200ms 上电延时)
    localparam integer T_ACK   =  4_800_000;    // 0.2 s  (等 PCLK 域握手应答)
    localparam integer T_PRINT = 120_000_000;    // 5.0 s  (打印 ~700 字节 @9600)
    localparam integer T_STABLE= 72_000_000;    // 3.0 s  (等相机稳定出流的最长时间)

    reg [27:0] wait_cnt;

    // ------------------------------------------------------------------
    //  结论标志 (用 wire 组合出来, 避免在 ST_FLAG 里读到上一拍的旧值)
    // ------------------------------------------------------------------
    //  OV2640 的 PCLK 由 R_DVP_SP(0xD3) 决定: PCLK = sysclk/[6:0]
    //  (VGA 档写 0x02)。首版先把窗口放宽到 4~48MHz, 实测出确切值之后再收紧。
    wire rate_ok_w   = (mhz_cnt >= 8'd4) && (mhz_cnt <= 8'd48);
    //  芯片 ID: diag_rd[0] = 0x0A (PID=0x26), diag_rd[1] = 0x0B (VER=0x42)
    wire cfg_ok_w   = (diag_rd[0] == 8'h26) && (diag_rd[1] == 8'h42) &&
                      (cfg_nack == 0) && (diag_ok == 16'd12);
    wire dvp_ok_w   = rate_ok_w &&
                      (snap_frames >= 32'd2) && (snap_line_bytes >= 16'd1000) &&
                      (snap_lines >= 16'd100);
    //  字节序判定:
    //   位序对不对  -> normal 位序的指标必须显著小于 bitrev 位序的指标
    //                  (色度字节在奇位还是偶位只是弱判据: 位置错了, 旁边的
    //                   字节也还是色度, |U-128| 依然很小, 所以两个 normal
    //                   指标差距不大, 不能用"谁最小"当强判据)
    wire order_ok_w = (norm_min != 32'd0) && ((norm_min << 2) < rev_min) &&
                      (best_idx < 2'd2);

    // 分析用的中间量 (全部多周期完成, 避免长组合路径)
    reg [31:0] div_rem;      // PCLK 计数除以 1e6 的余数
    reg [7:0]  mhz_cnt;      // PCLK MHz
    reg [31:0] cmp_best;     // 指标最小值
    reg [31:0] sec_best;     // 指标次小值
    reg [31:0] norm_min;     // normal 位序里的最小指标
    reg [31:0] rev_min;      // bitrev 位序里的最小指标
    reg [1:0]  best_idx;
    reg [3:0]  an_cnt;
    reg        flag_cfg_ok_r, flag_dvp_ok_r, flag_order_ok_r;

    always @(posedge clk24) begin
        if (!rst_n) begin
            st <= ST_WAIT;
            cfg_start_r <= 1'b0;
            cmd_tog <= 1'b0; cmd_op <= 2'd0; ack_last <= 1'b0;
            meas_cnt <= 0;
            pr_start <= 1'b0;
            div_rem <= 0; mhz_cnt <= 0; cmp_best <= 0; sec_best <= 0;
            best_idx <= 0; an_cnt <= 0;
            wait_cnt <= 0;
            flag_cfg_ok_r <= 0; flag_dvp_ok_r <= 0; flag_order_ok_r <= 0;
            r_mhz<=0; r_verdict<=0; r_cfg_ok<=0; r_dvp_ok<=0; r_order_ok<=0;
            r_best<=0;
            diag_ok<=0; diag_nack<=0; diag_n38<=0;
            diag_idx<=0; diag_ss<=0;
            vsync_mark<=0;
            diag_rd[0]<=0; diag_rd[1]<=0; diag_rd[2]<=0; diag_rd[3]<=0;
            diag_rd[4]<=0; diag_rd[5]<=0; diag_rd[6]<=0; diag_rd[7]<=0;
            diag_rd[8]<=0; diag_rd[9]<=0; diag_rd[10]<=0; diag_rd[11]<=0;
            sccb_addr <= 8'h60; sccb_probe <= 1'b0;
            probe_idx <= 3'd0; probe_mask <= 6'd0; probe_start_r <= 1'b0;
            diag_mode <= 1'b0; diag_start_r <= 1'b0;
            diag_reg <= 16'd0; diag_wdata <= 8'h00; diag_is_read <= 1'b0;
            diag_idx <= 3'd0; diag_ss <= 1'b0;
        end else begin
            pr_start <= 1'b0;
            probe_start_r <= 1'b0;
            diag_start_r <= 1'b0;     // 必须每拍清零, 否则 SCCB 事务会失控循环
            case (st)
            //-----------------------------------------------------------
            ST_WAIT: begin
                // 先等 300ms, 让摄像头完成自己的上电时序, 再做地址探测
                if (rst_cnt >= 16'd1000) begin
                    wait_cnt <= wait_cnt + 1'b1;
                    if (wait_cnt >= 7_200_000) begin   // 0.3 s
                        probe_idx  <= 3'd0;
                        probe_mask <= 6'd0;
                        wait_cnt   <= 0;
                        st         <= ST_PB0;
                    end
                end
            end
            //----------------------------------------------------------- 选候选地址
            ST_PB0: begin
                sccb_addr  <= cand_addr(probe_idx);
                sccb_probe <= 1'b1;
                wait_cnt   <= 0;
                st         <= ST_PB1;
            end
            //----------------------------------------------------------- 发探测事务
            ST_PB1: begin
                probe_start_r <= 1'b1;
                probe_idx     <= probe_idx + 1'b1;
                wait_cnt      <= 0;
                st            <= ST_PB2;
            end
            //----------------------------------------------------------- 等探测结果
            ST_PB2: begin
                wait_cnt <= wait_cnt + 1'b1;
                if (sccb_done) begin
                    if (!sccb_ack_err) probe_mask[probe_idx - 1'b1] <= 1'b1;
                    wait_cnt <= 0;
                    if (probe_idx >= NPROBE_C) st <= ST_PB3;
                    else                  st <= ST_PB0;
                end else if (wait_cnt >= T_ACK) begin
                    wait_cnt <= 0;
                    st       <= ST_PB0;      // 探测超时(主机卡住) -> 放弃探测
                end
            end
            //----------------------------------------------------------- 选定地址
            ST_PB3: begin
                sccb_addr  <= pick_addr(probe_mask);
                sccb_probe <= 1'b0;
                cfg_start_r <= 1'b1;        // 启动寄存器配置序列
                st         <= ST_CFG;
            end
            //-----------------------------------------------------------
            ST_CFG: begin
                cfg_start_r <= 1'b0;
                wait_cnt    <= wait_cnt + 1'b1;
                if (cfg_done) begin
                    wait_cnt  <= 0;
                    vsync_mark <= vsync_edge_live;
                    st        <= ST_WAITV;
                end else if (wait_cnt >= T_CFG) begin
                    wait_cnt  <= 0;      // 配置超时(相机没应答) -> 继续跑, 报表里会体现
                    vsync_mark <= vsync_edge_live;
                    st        <= ST_WAITV;
                end
            end
            //-----------------------------------------------------------
            //  等相机稳定出流: 刚写完寄存器时相机可能还没把新的输出窗口/
            //  自动曝光稳定下来, 这时候回读 0x38xx 段会得到 0x00。
            //  等 6 个场同步边沿(= 3 帧)再回读, 拿到的才是真值。
            //  (等不到就按超时继续, 报表里能看到没等到)
            //-----------------------------------------------------------
            ST_WAITV: begin
                wait_cnt <= wait_cnt + 1'b1;
                //  只用低 8 位做差(循环计数): 等 3 帧最多几十个边沿, 不会绕圈;
                //  8bit 比较比 32bit 快得多, 不占关键路径。
                if ((vsync_edge_live[7:0] - vsync_mark[7:0]) >= 8'd6) begin
                    wait_cnt <= 0;
                    st       <= ST_DIAG0;
                end else if (wait_cnt >= T_STABLE) begin
                    wait_cnt <= 0;
                    st       <= ST_DIAG0;
                end
            end
            //-----------------------------------------------------------
            //  诊断读: 12 次读
            //    0..3  : 0x300A / 0x300B / 0x4300 / 0x3017  (任何时候都读得对)
            //    4..7  : 0x3808~0x380B (输出窗口, 排在前面会读回 0x00)
            //    8..11 : 0x380C~0x380F (HTS / VTS, **只有最后 4 次读得对**)
            //
            //  [实测结论]
            //  1) 0x38xx 组(输出窗口/时序寄存器)在诊断读阶段里只有**最后 4 次
            //     事务**能读出真值, 排在前面的一律是 0x00; 0x30xx / 0x43xx 组
            //     任何时候都正常。所以把 HTS/VTS 放到最后 4 个槽位。
            //  2) 读方式 Sr 和 STOP+START 都能读对(对照实验: 0x3808 两种方式
            //     都读回 0x02, 0x300A 都读回 0x56)。
            //  3) 同一个地址连着读两次, 第二次会读回 0x00。
            //-----------------------------------------------------------
            ST_DIAG0: begin
                diag_mode    <= 1'b1;
                diag_is_read <= diag_read_w;
                diag_wdata   <= diag_data_w;
                diag_reg     <= diag_addr_w;
                diag_ss      <= 1'b0;              // 0 = 重复起始 Sr
                diag_start_r <= 1'b1;
                wait_cnt     <= 0;
                st           <= ST_DIAG1;
            end
            ST_DIAG1: begin
                wait_cnt <= wait_cnt + 1'b1;
                if (sccb_done) begin
                    if (!sccb_ack_err) begin
                        if (diag_read_w) begin
                        diag_ok <= diag_ok + 1'b1;
                        //  DSP bank 的 8 个尺寸/格式寄存器(slot 4..11)读到非零
                        //  才算"读回来了"
                        if ((diag_slot_w >= 4'd4) && (sccb_rdata != 8'h00))
                            diag_n38 <= diag_n38 + 1'b1;
                        case (diag_slot_w)
                            4'd0:  diag_rd[0]  <= sccb_rdata;
                            4'd1:  diag_rd[1]  <= sccb_rdata;
                            4'd2:  diag_rd[2]  <= sccb_rdata;
                            4'd3:  diag_rd[3]  <= sccb_rdata;
                            4'd4:  diag_rd[4]  <= sccb_rdata;
                            4'd5:  diag_rd[5]  <= sccb_rdata;
                            4'd6:  diag_rd[6]  <= sccb_rdata;
                            4'd7:  diag_rd[7]  <= sccb_rdata;
                            4'd8:  diag_rd[8]  <= sccb_rdata;
                            4'd9:  diag_rd[9]  <= sccb_rdata;
                            4'd10: diag_rd[10] <= sccb_rdata;
                            4'd11: diag_rd[11] <= sccb_rdata;
                            default: ;
                        endcase
                        end
                    end else begin
                        diag_nack <= diag_nack + 1'b1;
                    end
                    diag_idx <= diag_idx + 1'b1;
                    wait_cnt <= 0;
                    if (diag_idx >= 5'd13) begin
                        diag_mode <= 1'b0;
                        st        <= ST_MEAS;
                    end else begin
                        st        <= ST_DIAG0;
                    end
                end else if (wait_cnt >= T_ACK) begin
                    diag_idx  <= diag_idx + 1'b1;
                    wait_cnt  <= 0;
                    if (diag_idx >= 5'd13) begin
                        diag_mode <= 1'b0;
                        st        <= ST_MEAS;
                    end else begin
                        st        <= ST_DIAG0;
                    end
                end
            end
            //-----------------------------------------------------------
            ST_MEAS: begin
                cmd_op   <= 2'd1;           // clear
                cmd_tog  <= ~cmd_tog;
                ack_last <= ack_s2;
                meas_cnt <= 0;
                wait_cnt <= 0;
                st       <= ST_MEASW;
            end
            ST_MEASW: begin
                wait_cnt <= wait_cnt + 1'b1;
                if (ack_s2 != ack_last) begin
                    wait_cnt <= 0;
                    st       <= ST_COUNT;
                end else if (wait_cnt >= T_ACK) begin
                    wait_cnt <= 0;      // PCLK 域没有应答(相机没出流) -> 继续
                    st       <= ST_COUNT;
                end
            end
            //-----------------------------------------------------------
            ST_COUNT: begin
                meas_cnt <= meas_cnt + 1'b1;
                if (meas_cnt == 25'd24_000_000) st <= ST_FREEZE;
            end
            //-----------------------------------------------------------
            ST_FREEZE: begin
                cmd_op   <= 2'd2;           // freeze
                cmd_tog  <= ~cmd_tog;
                ack_last <= ack_s2;
                wait_cnt <= 0;
                st       <= ST_FRZWAIT;
            end
            ST_FRZWAIT: begin
                wait_cnt <= wait_cnt + 1'b1;
                if (ack_s2 != ack_last) begin
                    wait_cnt <= 0;
                    st       <= ST_FILL;
                end else if (wait_cnt >= T_ACK) begin
                    wait_cnt <= 0;
                    st       <= ST_FILL;
                end
            end
            //-----------------------------------------------------------
            ST_FILL: begin
                //  报表变量现在都是组合连线(直接指向源信号), 这里只需要
                //  给多周期分析器准备初值
                div_rem  <= snap_pclk_cnt;
                mhz_cnt  <= 8'd0;
                an_cnt   <= 4'd0;
                best_idx <= 2'd0;
                st       <= ST_DIV;
            end
            //----------------------------------------------------------- PCLK MHz
            ST_DIV: begin
                if (div_rem >= 32'd1_000_000) begin
                    div_rem <= div_rem - 32'd1_000_000;
                    mhz_cnt <= mhz_cnt + 1'b1;
                end else begin
                    r_mhz <= {24'd0, mhz_cnt};
                    an_cnt <= 4'd0;
                    st    <= ST_AN;
                end
            end
            //----------------------------------------------------------- 指标 min/second
            ST_AN: begin
                case (an_cnt)
                    4'd0: begin cmp_best <= snap_m0; best_idx <= 2'd0; an_cnt <= 4'd1; end
                    4'd1: begin if (snap_m1 < cmp_best) begin cmp_best <= snap_m1; best_idx <= 2'd1; end
                                 an_cnt <= 4'd2; end
                    4'd2: begin if (snap_m2 < cmp_best) begin cmp_best <= snap_m2; best_idx <= 2'd2; end
                                 an_cnt <= 4'd3; end
                    4'd3: begin if (snap_m3 < cmp_best) begin cmp_best <= snap_m3; best_idx <= 2'd3; end
                                 sec_best <= 32'hFFFFFFFF; an_cnt <= 4'd4; end
                    4'd4: begin if ((4'd0 != best_idx) && (snap_m0 < sec_best)) sec_best <= snap_m0;
                                 an_cnt <= 4'd5; end
                    4'd5: begin if ((4'd1 != best_idx) && (snap_m1 < sec_best)) sec_best <= snap_m1;
                                 an_cnt <= 4'd6; end
                    4'd6: begin if ((4'd2 != best_idx) && (snap_m2 < sec_best)) sec_best <= snap_m2;
                                 an_cnt <= 4'd7; end
                    4'd7: begin if ((4'd3 != best_idx) && (snap_m3 < sec_best)) sec_best <= snap_m3;
                                 an_cnt <= 4'd8; end
                    //  额外算 normal / bitrev 两组各自的最小值 (给字节序判据用)
                    4'd8: begin an_cnt <= 4'd9; end
                    4'd9: begin norm_min <= (snap_m0 <= snap_m1) ? snap_m0 : snap_m1;
                                 an_cnt <= 4'd10; end
                    4'd10: begin rev_min <= (snap_m2 <= snap_m3) ? snap_m2 : snap_m3;
                                  an_cnt <= 4'd11; end
                    default: st <= ST_FLAG;
                endcase
            end
            //----------------------------------------------------------- 结论
            ST_FLAG: begin
                flag_cfg_ok_r   <= cfg_ok_w;
                flag_dvp_ok_r   <= dvp_ok_w;
                flag_order_ok_r <= order_ok_w;
                r_verdict <= {23'd0, best_idx[0], (best_idx < 2'd2), order_ok_w,
                              dvp_ok_w, cfg_ok_w};
                r_cfg_ok   <= {31'd0, cfg_ok_w};
                r_dvp_ok   <= {31'd0, dvp_ok_w};
                r_order_ok <= {31'd0, order_ok_w};
                r_best     <= cmp_best;
                st   <= ST_PRINT;
            end
            //-----------------------------------------------------------
            ST_PRINT: begin
                pr_start <= 1'b1;
                if (pr_done) begin
                    wait_cnt <= 0;
                    st       <= ST_DONE;
                end else begin
                    wait_cnt <= wait_cnt + 1'b1;
                    if (wait_cnt >= T_PRINT) begin
                        wait_cnt <= 0;
                        st       <= ST_DONE;
                    end
                end
            end
            //-----------------------------------------------------------
            ST_DONE: begin
                // 保持
            end
            default: st <= ST_WAIT;
            endcase
        end
    end

    assign cfg_start = cfg_start_r;

    // ------------------------------------------------------------------
    //  LED: 绿=全部通过, 红=有失败, 蓝=工作中
    // ------------------------------------------------------------------
    wire all_ok = flag_cfg_ok_r && flag_dvp_ok_r && flag_order_ok_r;
    assign LED_G = (st == ST_DONE) && all_ok;
    assign LED_R = (st == ST_DONE) && !all_ok;
    assign LED_B = (st != ST_DONE);

endmodule

`default_nettype wire
