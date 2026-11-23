// ============================================================================
//  ov2640_cfg.v -- OV2640 寄存器配置序列 (ROM 驱动)
//
//  ROM 格式 (ov2640_cfg.hex, 每行 8 位十六进制 = 32bit):
//     [31:30] op   : 0 = 结束, 1 = 写, 2 = 读, 3 = 延时(毫秒)
//     [29:14] 寄存器地址
//     [13:6]  数据
//
//  写失败(无 ACK) 自动重试 3 次; 读回的 8 个关键寄存器存到 rd0..rd7。
// ============================================================================
`default_nettype none

module ov2640_cfg #(
    parameter CLK_HZ     = 24_000_000,
    parameter POWERUP_MS = 200          // 摄像头上电后等待时间
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    output reg         busy,
    output reg         done,
    output wire        fail,

    // SCCB 主机接口
    output reg         sccb_start,
    output reg         sccb_is_read,
    output reg  [15:0] sccb_reg,
    output reg  [7:0]  sccb_wdata,
    input  wire        sccb_done,
    input  wire        sccb_ack_err,
    input  wire [7:0]  sccb_rdata,

    // 结果
    output reg  [7:0]  rd0, rd1, rd2, rd3, rd4, rd5, rd6, rd7,
    output reg  [7:0]  rd8, rd9, rd10, rd11,
    output reg  [7:0]  nack_cnt,
    output reg  [15:0] wr_cnt,
    output wire [15:0] rd_ok_cnt   // 成功读到数据的次数 (= rd_slot)
);

    localparam [1:0] OP_END = 2'd0, OP_W = 2'd1, OP_R = 2'd2, OP_DELAY = 2'd3;
    localparam integer DLY_TICKS = CLK_HZ / 1000;   // 1 毫秒对应多少拍
    localparam integer PWDLY = (CLK_HZ / 1000) * POWERUP_MS;
    localparam integer MAX_RETRY = 3;

    localparam [2:0] S_IDLE   = 0,
                     S_POWER  = 1,
                     S_PWDLY  = 2,
                     S_FETCH0 = 3,
                     S_FETCH1 = 4,
                     S_EXEC   = 5,
                     S_NEXT   = 6,
                     S_DELAY  = 7;

    //  说明: 本模块只负责把配置写出去, 不做回读。
    //  [实测] 写完 271 个寄存器就立刻回读 0x38xx 组(输出窗口/时序寄存器)会
    //  读回 0x00, 而且会让相机该组之后的读全部返回 0x00(0x30xx/0x43xx 组不
    //  受影响)。所以 ROM 里只放写操作, 所有回读都交给顶层诊断读
    //  (top.v 的 ST_WAITV / ST_DIAG0), 那里的 12 个关键寄存器都能读回真值。

    reg [31:0] rom [0:511];
    initial $readmemh("ov2640_cfg.hex", rom);

    reg  [8:0]  rom_idx;
    reg  [31:0] rom_q;
    always @(posedge clk) rom_q <= rom[idx];

    reg  [2:0]  st;
    reg  [15:0] dly_tick;    // 延时里的毫秒计时
    reg  [7:0]  dly_ms;      // 已经等了多少毫秒
    //  注意: 上电延时常数 PWDLY = CLK_HZ/1000*POWERUP_MS, 在 24MHz/200ms 下是
    //  4,800,000, 16 位计数器会溢出 -> 永远等不到上电延时结束, 配置一次都发不出去。
    reg  [23:0] pw_cnt;
    reg  [8:0]  idx;
    reg  [2:0]  retry;
    reg  [3:0]  rd_slot;

    reg  [1:0]  cur_op;
    reg  [15:0] cur_reg;
    reg  [7:0]  cur_dat;

    wire [1:0]  rom_op   = rom_q[31:30];
    wire [15:0] rom_radr = rom_q[29:14];
    wire [7:0]  rom_rdat = rom_q[13:6];

    always @(posedge clk) begin
        if (!rst_n) begin
            st <= S_IDLE; busy <= 1'b0; done <= 1'b0;
            pw_cnt <= 0; idx <= 0; retry <= 0; rd_slot <= 0;
            dly_tick <= 0; dly_ms <= 0;
            cur_op <= OP_W; cur_reg <= 0; cur_dat <= 0;
            sccb_start <= 1'b0; sccb_is_read <= 1'b0;
            sccb_reg <= 0; sccb_wdata <= 0;
            rd0 <= 0; rd1 <= 0; rd2 <= 0; rd3 <= 0;
            rd4 <= 0; rd5 <= 0; rd6 <= 0; rd7 <= 0;
            rd8 <= 0; rd9 <= 0; rd10 <= 0; rd11 <= 0;
            nack_cnt <= 0; wr_cnt <= 0;
        end else begin
            done       <= 1'b0;
            sccb_start <= 1'b0;
            case (st)
            //-----------------------------------------------------------
            S_IDLE: begin
                busy <= 1'b0;
                if (start) begin
                    busy   <= 1'b1;
                    pw_cnt <= 0;
                    st     <= S_POWER;
                end
            end
            //----------------------------------------------------------- 上电等待
            S_POWER: begin
                st <= S_PWDLY;
            end
            S_PWDLY: begin
                if (pw_cnt >= PWDLY - 1) begin
                    idx <= 9'd0;
                    st  <= S_FETCH0;
                end else begin
                    pw_cnt <= pw_cnt + 1'b1;
                end
            end
            //----------------------------------------------------------- 取 ROM
            S_FETCH0: begin
                st <= S_FETCH1;          // 此拍后 rom_q 有效
            end
            S_FETCH1: begin
                if (rom_op == OP_END) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    st   <= S_IDLE;
                end else if (rom_op == OP_DELAY) begin
                    dly_tick <= 16'd0;
                    dly_ms   <= 8'd0;
                    st       <= S_DELAY;
                end else begin
                    cur_op  <= rom_op;
                    cur_reg <= rom_radr;
                    cur_dat <= rom_rdat;
                    retry   <= 3'd0;
                    sccb_start   <= 1'b1;
                    sccb_is_read <= (rom_op == OP_R);
                    sccb_reg     <= rom_radr;
                    sccb_wdata   <= rom_rdat;
                    st    <= S_EXEC;
                end
            end
            //----------------------------------------------------------- 等 SCCB
            S_EXEC: begin
                if (sccb_done) begin
                    if (sccb_ack_err) begin
                        nack_cnt <= nack_cnt + 1'b1;
                        if (retry < MAX_RETRY) begin
                            retry        <= retry + 1'b1;
                            sccb_start   <= 1'b1;
                            sccb_is_read <= (cur_op == OP_R);
                            sccb_reg     <= cur_reg;
                            sccb_wdata   <= cur_dat;
                        end else begin
                            st <= S_NEXT;
                        end
                    end else begin
                        if (cur_op == OP_R) begin
                            case (rd_slot)
                            4'd0: rd0 <= sccb_rdata;
                            4'd1: rd1 <= sccb_rdata;
                            4'd2: rd2 <= sccb_rdata;
                            4'd3: rd3 <= sccb_rdata;
                            4'd4: rd4 <= sccb_rdata;
                            4'd5: rd5 <= sccb_rdata;
                            4'd6: rd6 <= sccb_rdata;
                            4'd7: rd7 <= sccb_rdata;
                            4'd8: rd8 <= sccb_rdata;
                            4'd9: rd9 <= sccb_rdata;
                            4'd10: rd10 <= sccb_rdata;
                            default: rd11 <= sccb_rdata;
                            endcase
                            rd_slot <= rd_slot + 1'b1;
                        end else begin
                            wr_cnt <= wr_cnt + 1'b1;
                        end
                        st <= S_NEXT;
                    end
                end
            end
            //----------------------------------------------------------- 延时
            //  软复位之后芯片需要一点时间复位, 寄存器表里用 op=3 + 毫秒数表示
            S_DELAY: begin
                if (dly_tick >= DLY_TICKS - 1) begin
                    dly_tick <= 16'd0;
                    if (dly_ms + 1'b1 >= rom_rdat) begin
                        idx <= idx + 1'b1;
                        st  <= S_FETCH0;
                    end else begin
                        dly_ms <= dly_ms + 1'b1;
                    end
                end else begin
                    dly_tick <= dly_tick + 1'b1;
                end
            end
            //----------------------------------------------------------- 下一项
            S_NEXT: begin
                idx <= idx + 1'b1;
                st  <= S_FETCH0;
            end
            default: st <= S_IDLE;
            endcase
        end
    end

    assign fail = (nack_cnt != 0);
    assign rd_ok_cnt = {12'd0, rd_slot};

endmodule

`default_nettype wire
