// ============================================================================
//  dvp_capture.v -- OV5640 DVP 采集 / 统计 / 字节序判定 (PCLK 时钟域)
//
//  DVP 在 YUV422(YUYV) 模式下每个 PCLK 就是一个字节:
//     640x480 一行 = 1280 字节 (Y,U,Y,V 交替)
//
//  字节序判定:
//     U/V 字节的直流分量约在 128, 因此 m = Σ|byte-128| 对"色度字节"应该很小,
//     对亮度字节或者位序颠倒的字节会很大。
//     对 4 个假设各算一次:
//        m0 = 色度在奇数字节位, 正常位序
//        m1 = 色度在偶数字节位, 正常位序
//        m2 = 色度在奇数字节位, 位序颠倒
//        m3 = 色度在偶数字节位, 位序颠倒
//     取最小者即为正确答案。
//
//  流水线 (为了跑满 28MHz 的 PCLK, 留足余量):
//     Stage A: 输入寄存 (d_f / href_f / vs_f) + 计数器
//     Stage B: 计算 |byte-128| 与位序颠倒, 寄存差值与字节奇偶
//     Stage C: 24bit 累加器 (进位链)
//
//  重要: 统计窗口不依赖 VSYNC。VSYNC 没来(相机没进视频模式)时,
//  只要 HREF 有数据, 也要能拿到字节序指标和原始采样字节。
//
//  跨时钟域: 系统域用 toggle 握手下 clear / freeze 两条命令。
// ============================================================================
`default_nettype none

module dvp_capture (
    input  wire        pclk,        // 摄像头像素时钟 (全局时钟)
    input  wire        rst_n,       // 异步复位, 低有效
    input  wire        vsync,
    input  wire        href,
    input  wire [7:0]  d,

    // ---- 命令接口 (系统域 -> PCLK 域, toggle 握手) ----
    input  wire        cmd_tog,
    input  wire [1:0]  cmd_op,      // 1 = clear, 2 = freeze
    output reg         ack_tog,

    // ---- 快照 (系统域读取) ----
    output reg [31:0]  snap_pclk_cnt,
    output reg [31:0]  snap_active_cnt,
    output reg [31:0]  snap_frames,
    output reg [15:0]  snap_lines,
    output reg [15:0]  snap_line_bytes,
    output reg [31:0]  snap_m0,
    output reg [31:0]  snap_m1,
    output reg [31:0]  snap_m2,
    output reg [31:0]  snap_m3,
    output reg [127:0] snap_sample,
    output reg [31:0]  snap_vsync_cnt,
    output reg [31:0]  snap_vsync_edge,
    output reg [31:0]  snap_href_edge,
    output reg [31:0]  snap_metric_bytes,
    // ---- 引脚诊断: 数据线到底有没有动 ----
    output reg [7:0]   snap_pin_changed,  // 统计窗口内发生过电平变化的位
    output reg [7:0]   snap_pin_now,      // 冻结瞬间 8 根数据线的电平
    output reg [7:0]   snap_byte_min,     // 统计窗口内采样字节的最小值
    output reg [7:0]   snap_byte_max,     // 统计窗口内采样字节的最大值
    // ---- 时序测量: 一行 / 一帧占多少个 PCLK 周期 ----
    output reg [31:0]  snap_line_period,
    output reg [31:0]  snap_frame_period,
    //  实时值(不受冻结影响): 顶层用它判断相机是不是已经在稳定出流
    output wire [31:0]  vsync_edge_live
);

    // ------------------------------------------------------------------
    //  Stage A : 输入寄存 + 帧/行/字节计数
    // ------------------------------------------------------------------
    reg [7:0] d_f;
    reg       href_f, href_d;
    reg       vs_f,  vs_d;

    always @(posedge pclk) begin
        d_f    <= d;
        href_f <= href;
        href_d <= href_f;
        vs_f   <= vsync;
        vs_d   <= vs_f;
    end

    wire vsync_rise = vs_f & ~vs_d;
    wire href_rise  = href_f & ~href_d;
    wire vsync_edge = vs_f ^ vs_d;
    wire href_edge  = href_f ^ href_d;

    reg [31:0] pclk_cnt;      // PCLK 周期数 (用来算 PCLK 频率)
    reg [31:0] active_cnt;    // href 有效期间的字节数
    reg [31:0] frames;        // 帧计数
    reg [15:0] lines;         // 当前帧的行计数
    reg [15:0] line_bytes;    // 当前行的字节数
    reg [16:0] metric_cnt;    // 参与统计的字节数 (上限 65536, 保证 24bit 不溢出)
    reg        metric_en;     // 统计窗口使能
    reg        frame_seen;
    reg        par;           // href 有效期的字节奇偶 (只允许一处驱动)
    reg        sample_en;     // 正在抓取采样字节
    reg [4:0]  sidx;          // 采样字节序号 (0..15)
    reg [127:0] sample;

    reg [31:0] vsync_edge_cnt;
    reg [31:0] href_edge_cnt;
    assign vsync_edge_live = vsync_edge_cnt;

    //  引脚诊断
    reg [7:0]  d_prev;        // 上一拍的数据总线
    reg [7:0]  pin_changed;   // 统计窗口内发生过电平跳变的数据线
    reg [7:0]  byte_min, byte_max;

    //  行/帧时序 (以 PCLK 周期计)
    //  行周期取"最小间隔": href 上升沿之间最短的那个才是真正的行时间
    //  (HTS), 最大的那个是垂直消隐(帧与帧之间的长空档)。
    reg [31:0] line_per_cnt, line_per_min;
    reg [31:0] frame_per_cnt, frame_per_max;
    reg        frozen;        // 冻结后不再更新统计量, 否则快照会被后续的
                               // VSYNC/HREF 跳变覆盖掉

    // ------------------------------------------------------------------
    //  Stage B : 差值计算 + 字节奇偶
    // ------------------------------------------------------------------
    wire [7:0] d_rev = {d_f[0], d_f[1], d_f[2], d_f[3],
                        d_f[4], d_f[5], d_f[6], d_f[7]};
    wire [8:0] diff_n_c = (d_f    >= 8'd128) ? ({1'b0, d_f}    - 9'd128)
                                           : (9'd128 - {1'b0, d_f});
    wire [8:0] diff_r_c = (d_rev >= 8'd128) ? ({1'b0, d_rev} - 9'd128)
                                           : (9'd128 - {1'b0, d_rev});

    reg [8:0] diff_n_r, diff_r_r;
    reg       par_r;

    always @(posedge pclk) begin
        diff_n_r <= diff_n_c;
        diff_r_r <= diff_r_c;
        par_r    <= par;
    end

    // ------------------------------------------------------------------
    //  Stage C : 24bit 指标累加器
    // ------------------------------------------------------------------
    reg [23:0] m0, m1, m2, m3;

    // ------------------------------------------------------------------
    //  命令握手
    // ------------------------------------------------------------------
    reg  cmd_s1, cmd_s2, cmd_s3;
    reg  do_clear, do_freeze;

    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            cmd_s1 <= 1'b0; cmd_s2 <= 1'b0; cmd_s3 <= 1'b0;
            ack_tog <= 1'b0; do_clear <= 1'b0; do_freeze <= 1'b0;
        end else begin
            cmd_s1 <= cmd_tog;
            cmd_s2 <= cmd_s1;
            cmd_s3 <= cmd_s2;
            do_clear  <= 1'b0;
            do_freeze <= 1'b0;
            if (cmd_s2 != cmd_s3) begin
                ack_tog <= ~ack_tog;
                case (cmd_op)
                    2'd1: do_clear  <= 1'b1;
                    2'd2: do_freeze <= 1'b1;
                    default: ;
                endcase
            end
        end
    end

    // ------------------------------------------------------------------
    //  计数 (Stage A) 与指标累加 (Stage C)
    // ------------------------------------------------------------------
    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            pclk_cnt <= 0; active_cnt <= 0; frames <= 0;
            lines <= 0; line_bytes <= 0;
            metric_cnt <= 0; metric_en <= 1'b0; frame_seen <= 1'b0;
            m0 <= 0; m1 <= 0; m2 <= 0; m3 <= 0;
            par <= 1'b0; sidx <= 0; sample <= 0; sample_en <= 1'b0;
            vsync_edge_cnt <= 0; href_edge_cnt <= 0;
            snap_lines <= 0; snap_line_bytes <= 0; snap_vsync_cnt <= 0;
            d_prev <= 8'h00; pin_changed <= 8'h00;
            byte_min <= 8'hFF; byte_max <= 8'h00;
            line_per_cnt <= 0; line_per_min <= 32'hFFFFFFFF;
            frame_per_cnt <= 0; frame_per_max <= 0;
            frozen <= 1'b0;
        end else if (do_clear) begin
            pclk_cnt <= 0; active_cnt <= 0; frames <= 0;
            lines <= 0; line_bytes <= 0;
            metric_cnt <= 0; metric_en <= 1'b1; frame_seen <= 1'b0;
            m0 <= 0; m1 <= 0; m2 <= 0; m3 <= 0;
            par <= 1'b0; sidx <= 0; sample <= 0; sample_en <= 1'b1;
            vsync_edge_cnt <= 0; href_edge_cnt <= 0;
            snap_lines <= 0; snap_line_bytes <= 0; snap_vsync_cnt <= 0;
            d_prev <= 8'h00; pin_changed <= 8'h00;
            byte_min <= 8'hFF; byte_max <= 8'h00;
            line_per_cnt <= 0; line_per_min <= 32'hFFFFFFFF;
            frame_per_cnt <= 0; frame_per_max <= 0;
            frozen <= 1'b0;
        end else if (frozen) begin
            //  已冻结: 什么都不再改, 保证快照有效
        end else begin
            // ---- Stage A: 计数 ----
            pclk_cnt <= pclk_cnt + 1'b1;

            if (vsync_edge) vsync_edge_cnt <= vsync_edge_cnt + 1'b1;
            if (href_edge)  href_edge_cnt  <= href_edge_cnt  + 1'b1;

            if (vsync_rise) begin
                snap_lines     <= lines;
                snap_vsync_cnt <= frames + 1'b1;
                frames         <= frames + 1'b1;
                lines          <= 16'd0;
                //  帧周期 (PCLK 周期数) 的最大值
                if (frame_per_cnt > frame_per_max) frame_per_max <= frame_per_cnt;
                frame_per_cnt  <= 32'd0;
            end else begin
                frame_per_cnt <= frame_per_cnt + 1'b1;
            end

            if (href_rise) begin
                snap_line_bytes <= line_bytes;
                line_bytes      <= 16'd0;
                lines           <= lines + 1'b1;
                //  行周期 (PCLK 周期数): 取最小间隔 = 真正的行时间 (HTS)
                if (line_per_cnt < line_per_min) line_per_min <= line_per_cnt;
                line_per_cnt    <= 32'd0;
            end else begin
                line_per_cnt <= line_per_cnt + 1'b1;
                //  [修复] 原来这里和上面的 line_bytes<=0 在同一个 always 块里,
                //  后面的自增把复位覆盖掉了 -> line_bytes 变成只增不减的 16 位
                //  回绕计数器, "每行字节数" 打印出来是随机值。
                if (href_f) line_bytes <= line_bytes + 1'b1;
            end

            // ---- 字节奇偶: 只在 href 有效期内翻转 ----
            if (href_f) par <= ~par;

            // ---- 采样: clear 之后抓前 16 个 href 字节 (移位寄存器, 字节1 在最低位) ----
            if (sample_en && href_f) begin
                sample <= {sample[119:0], d_f};
                if (sidx == 5'd15) sample_en <= 1'b0;
                else               sidx      <= sidx + 1'b1;
            end

            // ---- 引脚诊断: 哪几根数据线真的在跳变 ----
            d_prev      <= d_f;
            pin_changed <= pin_changed | (d_f ^ d_prev);

            if (href_f) active_cnt <= active_cnt + 1'b1;

            // ---- Stage C: 指标累加 (只统计 href 有效期的字节) ----
            if (metric_en && href_f) begin
                if (par_r) begin
                    m0 <= m0 + diff_n_r;
                    m2 <= m2 + diff_r_r;
                end else begin
                    m1 <= m1 + diff_n_r;
                    m3 <= m3 + diff_r_r;
                end
                metric_cnt <= metric_cnt + 1'b1;
                if (metric_cnt == 17'd65535) metric_en <= 1'b0;
                //  采样字节的取值范围 (判断数据线是不是死的)
                if (d_f < byte_min) byte_min <= d_f;
                if (d_f > byte_max) byte_max <= d_f;
            end
        end
    end

    // ------------------------------------------------------------------
    //  冻结快照
    // ------------------------------------------------------------------
    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            snap_pclk_cnt   <= 0; snap_active_cnt <= 0; snap_frames <= 0;
            snap_m0 <= 0; snap_m1 <= 0; snap_m2 <= 0; snap_m3 <= 0;
            snap_sample <= 0;
            snap_metric_bytes <= 0;
            snap_vsync_edge <= 0; snap_href_edge <= 0;
            snap_pin_changed <= 8'h00; snap_pin_now <= 8'h00;
            snap_byte_min <= 8'h00; snap_byte_max <= 8'h00;
            snap_line_period <= 32'd0; snap_frame_period <= 32'd0;
        end else if (do_freeze) begin
            snap_pclk_cnt   <= pclk_cnt;
            snap_active_cnt <= active_cnt;
            snap_frames     <= frames;
            snap_m0 <= {8'd0, m0}; snap_m1 <= {8'd0, m1};
            snap_m2 <= {8'd0, m2}; snap_m3 <= {8'd0, m3};
            snap_sample <= sample;
            snap_metric_bytes <= metric_cnt;
            snap_vsync_edge <= vsync_edge_cnt;
            snap_href_edge  <= href_edge_cnt;
            snap_pin_changed <= pin_changed;
            snap_pin_now     <= d_f;
            snap_byte_min    <= byte_min;
            snap_byte_max    <= byte_max;
            snap_line_period <= line_per_min;
            snap_frame_period<= frame_per_max;
            frozen            <= 1'b1;
        end
    end

endmodule

`default_nettype wire
