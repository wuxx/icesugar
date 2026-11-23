// ============================================================================
//  tb_printer.v -- uart_printer 仿真测试台
//  用真实的 text.hex 跑一遍, 把串口输出存成 sim_out.txt。
//  仿真波特率提到 115200 (只是跑得快一点, 模板展开逻辑完全一样)。
// ============================================================================
`timescale 1ns/1ns

module tb;

    localparam integer NVARS  = 57;
    localparam integer SIMBAUD = 115200;

    reg clk = 1'b0;
    always #20 clk = ~clk;            // 25 MHz

    reg         rst_n = 1'b0;
    reg         start = 1'b0;
    reg [NVARS*32-1:0] vars_flat;
    reg [127:0] samples;

    wire        tx;
    wire        busy, done;

    integer i;
    integer fd;
    integer fd2;
    integer cycles = 0;
    reg [3:0]  last_st = 4'hF;
    reg [10:0] last_tpos = 11'h7FF;
    reg        last_done = 1'bx;

    uart_printer #(.CLK_HZ(24_000_000), .BAUD(SIMBAUD), .NVARS(NVARS)) u_pr (
        .clk(clk), .rst_n(rst_n), .start(start),
        .busy(busy), .done(done),
        .vars_flat(vars_flat), .samples(samples), .tx(tx)
    );

    // ---- 串口输出抓取 ----
    // 只有 u_tx 处于 S_IDLE 且打印机在 S_EMIT(ena) 时才会真的锁存一个字节,
    // 少了 e_ena 这个条件会把"等待下一个字节"的空闲周期也算进去, 导致每个字节重复两遍。
    always @(posedge clk) begin
        if (u_pr.u_tx.st === 3'd0 && u_pr.e_ena === 1'b1)
            $fwrite(fd, "%c", u_pr.e_byte);
    end

    // ---- 打印机状态追踪 (只在变化时记一行) ----
    always @(posedge clk) begin
        cycles <= cycles + 1;
        if (u_pr.st !== last_st || u_pr.tpos !== last_tpos || done !== last_done) begin
            last_st   <= u_pr.st;
            last_tpos <= u_pr.tpos;
            last_done <= done;
            $fwrite(fd2, "cyc=%0d pst=%0d tpos=%0d tb=%02x mode=%0d idx=%0d ecnt=%0d done=%b\n",
                    cycles, u_pr.st, u_pr.tpos, u_pr.tb, u_pr.emit_mode,
                    u_pr.emit_idx, u_pr.emit_cnt, done);
        end
    end

    initial begin
        fd  = $fopen("sim_out.txt", "w");
        fd2 = $fopen("sim_trace.txt", "w");
        for (i = 0; i < NVARS; i = i + 1)
            vars_flat[i*32 +: 32] = (i + 1) * 16'h1111;
        samples = 128'h0123456789ABCDEF;

        #1000;                          // 1 us
        rst_n = 1'b1;
        #1000;
        start = 1'b1;
        #40;
        start = 1'b0;

        #200000000;                     // 200 ms 超时
        $fwrite(fd, "\n");
        $fwrite(fd2, "TIMEOUT pst=%0d tpos=%0d tb=%02x mode=%0d idx=%0d ecnt=%0d done=%b\n",
                u_pr.st, u_pr.tpos, u_pr.tb, u_pr.emit_mode,
                u_pr.emit_idx, u_pr.emit_cnt, done);
        $fclose(fd);
        $fclose(fd2);
        $finish;
    end

endmodule
