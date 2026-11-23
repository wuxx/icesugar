// ============================================================================
//  dvp_linebuf.v -- DVP 采集 + 片上行缓冲 (band scan 用)
//
//  为什么需要它: 640x480 YUYV 一帧 = 614400 字节, 而 iCE40UP5K 全部 BRAM
//  只有 30 x 4Kbit = 15KB, 整帧根本存不下。所以改成"分段扫描":
//  每次只采 KROWS 行(约 10KB)存进片上 BRAM, 串口再慢慢发出去,
//  主机端按行号把 60 段拼成一整幅图。
//
//  写口在 PCLK 域(28MHz), 读口在 clk24 域。SB_RAM40_4K 的读写时钟可以不同,
//  yosys 的 ice40 BRAM 规则支持这种双时钟双口, 会自动映射。
//
//  ---------------------------------------------------------------------------
//  行号计数 (这里最容易出错, 记一下):
//    line_idx 必须在"行结束"(HREF 下降沿)时递增, 而不是行开始时。
//    因为 DVP 的 HREF 上升沿和该行第一个字节是同一个 PCLK 周期, 如果在上升沿
//    递增, 那么这一行的第 1 个字节和后面 1279 个字节会落在两个不同的行号上,
//    行号判断 (line_idx == target) 就会漏掉/多抓 1 字节。
//    改成"下降沿递增"之后, line_idx 在整个行内保持不变, 正好等于这一行的序号。
//
//  采集条件用 row_match = (line_idx == seg_row0 + row_in_seg):
//    row_in_seg 是本段已经采完的行数, 所以只要行号对得上就一定是本段的行。
//
//  段请求的时机 (踩过坑, 改成"在帧边界武装"):
//    请求 (req_tog 翻转) 可以发生在任意时刻, 甚至在帧中间。
//    最初的做法是"等下一个行边界就武装", 结果段起始行号 seg_row0 > 0 时
//    武装完要一直等到本帧的 seg_row0 行 —— 可是等的过程中帧又结束了,
//    VSYNC 把 cap_en 清掉, 段永远采不到 (2 秒超时重试, 无限循环)。
//    现在改成: 请求 pend 住, 等下一个 VSYNC(帧头)才武装, 此时 line_idx=0,
//    然后自然数到 seg_row0 行再开始采。行号和帧永远对得上。
//
//  帧同步:
//    复位后必须先收到一次 VSYNC 才认为 line_idx 可信(frame_ok)。
//
//  写口为什么"总是写"(不产生写使能):
//    iCE40 的 SB_RAM40_4K 上 WCLKE/RCLKE 是接在"全局时钟使能"上的。
//    如果 yosys 把内存的写使能映射到 WCLKE, 那么这个全局缓冲的使能就变成
//    "只有 wr_en 时才有时钟" —— 而同一个全局还驱动着整个 pclk 时钟域,
//    于是整个域被门控, 表现为"FPGA 整机不动"(实测: 加了行缓冲的固件
//    一个字节都发不出来, 去掉行缓冲就正常)。
//    所以这里让写使能恒为 1: 不采的时候重复写同一个地址/同一个数据
//    (写上去的值和原来一样, 没有副作用), 采的时候每个 pclk 写一个新位置。
// ============================================================================
`default_nettype none

module dvp_linebuf #(
    parameter integer KROWS   = 8,        // 每段采多少行
    parameter integer LINEB   = 1280,     // 每行字节数 (640 像素 x YUV422)
    parameter integer FRAME_L = 480,      // 一帧多少行
    parameter integer AW      = 14        // 缓冲地址位宽 (KROWS*LINEB = 10240)
)(
    input  wire        pclk,
    input  wire        clk24,
    input  wire        rst_n,

    input  wire [7:0]  d,
    input  wire        href,
    input  wire        vsync,

    // ---- 段请求 (clk24 域 -> pclk 域): req_tog 翻转一次 = 采一段 ----
    input  wire        req_tog,
    input  wire [8:0]  req_row0,     // 本段要采的起始行号(帧内)

    // ---- 状态回传 (pclk 域 -> clk24 域) ----
    output reg         ack_tog,      // 翻转一次 = 本段采完
    output reg  [15:0] lines_seen,   // 累计采到的行数
    output reg  [31:0] bytes_seen,   // 累计采到的字节数
    output reg  [10:0] last_row_bytes, // 最后一行采到的字节数(诊断用)

    // ---- 读口 (clk24 域) ----
    input  wire [AW-1:0] rb_addr,
    output reg  [7:0]    rb_data
);

    localparam integer DEPTH = KROWS*LINEB;    // 10240 字节

    //  下面几个常量都定宽, 免得比较/加法被 32 位整数撑大 (iCE40 上 32 位
    //  比较器会多吃掉上百个 LC)。
    localparam [AW-1:0]  LINEB_V  = LINEB;
    localparam [10:0]    LINEB_W  = LINEB;
    localparam [9:0]     FRAME_V  = FRAME_L - 1;
    localparam [3:0]     KROWS_M1 = KROWS - 1;

    // ------------------------------------------------------------------
    //  片上缓冲 (写口 PCLK 域 / 读口 clk24 域)
    // ------------------------------------------------------------------
    reg [7:0] mem [0:DEPTH-1];

    always @(posedge clk24) begin
        rb_data <= mem[rb_addr];
    end

    // ------------------------------------------------------------------
    //  PCLK 域: 输入寄存 (D 与 HREF 同延迟, 保证字节和行边界对齐)
    // ------------------------------------------------------------------
    reg [7:0] d_f;
    reg       href_f, href_d;
    reg       vs_f, vs_d;

    always @(posedge pclk) begin
        d_f    <= d;
        href_f <= href;
        href_d <= href_f;
        vs_f   <= vsync;
        vs_d   <= vs_f;
    end

    wire vs_rise   = vs_f   & ~vs_d;
    wire href_rise = href_f & ~href_d;
    wire href_fall = ~href_f & href_d;

    // ------------------------------------------------------------------
    //  段请求跨时钟域同步 (toggle + 数据总线)
    //  req_row0 在 req_tog 翻转前很久就已经稳定, 两级同步后取样是安全的。
    // ------------------------------------------------------------------
    reg        req_s1, req_s2, req_s2d;
    reg [8:0]  row0_s1, row0_s2;

    always @(posedge pclk) begin
        req_s1   <= req_tog;
        req_s2   <= req_s1;
        req_s2d  <= req_s2;
        row0_s1  <= req_row0;
        row0_s2  <= row0_s1;
    end

    //  注意: 必须是 XOR 边沿检测, 不能写成 req_s2 & ~req_s2d ——
    //  那是电平检测, 只能认出 0->1 的跳变, 第 2 次请求(1->0)就永远收不到。
    wire req_pulse = req_s2 ^ req_s2d;

    // ------------------------------------------------------------------
    //  采集状态
    // ------------------------------------------------------------------
    reg [9:0]    line_idx;    // 帧内行号 (整行内保持不变)
    reg          frame_ok;    // 复位后见过一次 VSYNC, 行号才可信
    reg          cap_en;      // 段采集使能 (在帧边界武装)
    reg [9:0]    seg_row0;    // 本段起始行号
    reg [3:0]    row_in_seg;  // 本段已采完的行数
    reg [AW-1:0] row_base;    // 当前行在缓冲里的基址 (每行 +LINEB)
    reg [10:0]   row_byte;    // 行内字节计数
    reg          pend;        // 有待武装的段请求
    reg [8:0]    pend_row0;

    wire [9:0] row_target = seg_row0 + {6'd0, row_in_seg};
    wire       row_match  = (line_idx == row_target);
    wire       cap_hit    = cap_en && frame_ok && row_match;

    // ------------------------------------------------------------------
    //  写口: **总是写** (不产生写使能)
    //  地址和数据一起寄存, 保持对齐: 第 N 个字节在第 N+1 拍落到 mem[N]。
    // ------------------------------------------------------------------
    reg        wr_en;
    reg [AW-1:0] wr_addr_r;
    reg [7:0]  wr_data_r;

    //  写口: 总是写。地址和数据一起寄存, 保持对齐: 第 N 个字节在第 N+1 拍
    //  落到 mem[N]。
    //  注意: wr_addr_r/wr_data_r 只能在主 always 块里赋值 —— 两个 always 块
    //  驱动同一组寄存器会被 yosys 判成 "multiple conflicting drivers",
    //  然后整个内存映射失败(实测: 内存直接没进 BRAM)。
    always @(posedge pclk) begin
        mem[wr_addr_r] <= wr_data_r;
    end

    always @* begin
        wr_en = cap_hit && href_f && (row_byte < LINEB_W);
    end

    always @(posedge pclk) begin
        if (!rst_n) begin
            line_idx      <= 10'd0;
            frame_ok      <= 1'b0;
            cap_en        <= 1'b0;
            seg_row0      <= 10'd0;
            row_in_seg    <= 4'd0;
            row_base      <= {AW{1'b0}};
            row_byte      <= 11'd0;
            pend          <= 1'b0;
            pend_row0     <= 9'd0;
            ack_tog       <= 1'b0;
            lines_seen    <= 16'd0;
            bytes_seen    <= 32'd0;
            last_row_bytes<= 11'd0;
            wr_addr_r     <= {AW{1'b0}};
            wr_data_r     <= 8'd0;
        end else begin
            if (vs_rise) begin
                // ---- 帧边界: 行号归零, 并在这里武装待处理的段请求 ----
                frame_ok <= 1'b1;
                line_idx <= 10'd0;
                if (pend) begin
                    cap_en     <= 1'b1;
                    seg_row0   <= {1'b0, pend_row0};
                    row_in_seg <= 4'd0;
                    row_base   <= {AW{1'b0}};
                    row_byte   <= 11'd0;
                    pend       <= 1'b0;
                end
            end else if (href_fall) begin
                // ---- 行结束 ----
                if (cap_hit) begin
                    // 这一行属于本段, 采完了
                    last_row_bytes <= row_byte;
                    row_byte        <= 11'd0;
                    row_base        <= row_base + LINEB_V;
                    row_in_seg      <= row_in_seg + 4'd1;
                    lines_seen      <= lines_seen + 16'd1;
                    if (row_in_seg == KROWS_M1) begin
                        cap_en  <= 1'b0;
                        ack_tog <= ~ack_tog;
                    end
                end

                // ---- 行号推进 (行末递增, 整行内保持不变) ----
                if (line_idx == FRAME_V) line_idx <= 10'd0;
                else                     line_idx <= line_idx + 10'd1;
            end

            // ---- 字节计数 + 写口地址/数据寄存 ----
            if (wr_en) begin
                wr_addr_r  <= row_base + row_byte;
                wr_data_r  <= d_f;
                bytes_seen <= bytes_seen + 32'd1;
                row_byte   <= row_byte + 11'd1;
            end

            // ---- 请求随时可到, 先 pend 住, 等下一个帧边界武装 ----
            if (req_pulse) begin
                pend      <= 1'b1;
                pend_row0 <= row0_s2;
            end
        end
    end

endmodule

`default_nettype wire
