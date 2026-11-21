// ============================================================================
//  tb_linebuf.v -- dvp_linebuf 离线验证 (iverilog)
//
//  用合成的 DVP 数据流检查"到底抓到了哪几行":
//    合成流里第 L 行的第 i 个字节固定是 (L<<4)|i, 所以只要读回缓冲就知道
//    抓的行对不对。覆盖 4 种情况:
//      1) 请求行 4
//      2) 请求行 0
//      3) 请求行 6 (帧尾)
//      4) 在一行正中间发请求 (必须仍然从行首开始抓)
//
//  带看门狗: 超过时限没等到 ack 就把 DUT 内部状态打出来, 免得仿真挂死。
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_linebuf;

  localparam integer LINEB   = 16;      // 每行字节数 (缩小版)
  localparam integer KROWS   = 2;       // 每段行数
  localparam integer FRAME_L = 8;       // 每帧行数
  localparam integer AW      = 6;       // 缓冲地址位宽 (2*16 = 32)

  reg clk24 = 1'b0;
  reg pclk  = 1'b0;
  always #25 clk24 = ~clk24;   // 20 MHz
  always #50 pclk  = ~pclk;    // 10 MHz

  reg rst_n = 1'b0;

  // ---- DVP 合成流 ----
  reg        href = 1'b0, vsync = 1'b0;
  reg [7:0]  d    = 8'h00;
  reg        gen_on = 1'b0;
  reg [15:0] gline = 16'd0;
  reg [10:0] gpcyc = 11'd0;
  reg [3:0]  gvcnt = 4'd0;

  always @(posedge pclk) begin
    if (!rst_n) begin
      href   <= 1'b0; vsync <= 1'b0; d <= 8'h00;
      gen_on <= 1'b0; gline <= 16'd0; gpcyc <= 11'd0; gvcnt <= 4'd0;
    end else if (!gen_on) begin
      href <= 1'b0; vsync <= 1'b0;
    end else if (gvcnt < 4) begin
      vsync <= 1'b1; href <= 1'b0; gvcnt <= gvcnt + 4'd1;
    end else if (gpcyc < LINEB) begin
      //  注意: 这里必须把 vsync 拉回 0 —— dvp_linebuf 是靠 VSYNC 的**上升沿**
      //  来武装段采集的, 如果 VSYNC 一直保持高, 第二帧之后就没有上升沿了,
      //  段请求会永远 pend 住 (实测: 看门狗超时, cap_en 一直是 0)。
      vsync <= 1'b0;
      href <= 1'b1;
      d    <= {gline[3:0], gpcyc[3:0]};    // 第 L 行第 i 字节 = (L<<4)|i
      gpcyc <= gpcyc + 11'd1;
    end else begin
      href  <= 1'b0;
      gpcyc <= 11'd0;
      gline <= gline + 16'd1;
      if (gline == FRAME_L-1) begin
        gline <= 16'd0;
        gvcnt <= 4'd0;
      end
    end
  end

  // ---- DUT ----
  reg         req_tog = 1'b0;
  reg  [8:0]  req_row0 = 9'd0;
  wire        ack_tog;
  wire [15:0] lines_seen;
  wire [31:0] bytes_seen;
  wire [10:0] last_row_bytes;
  reg  [AW-1:0] rb_addr = {AW{1'b0}};
  wire [7:0]    rb_data;

  dvp_linebuf #(
      .KROWS(KROWS), .LINEB(LINEB), .FRAME_L(FRAME_L), .AW(AW)
  ) dut (
      .pclk(pclk), .clk24(clk24), .rst_n(rst_n),
      .d(d), .href(href), .vsync(vsync),
      .req_tog(req_tog), .req_row0(req_row0),
      .ack_tog(ack_tog),
      .lines_seen(lines_seen), .bytes_seen(bytes_seen),
      .last_row_bytes(last_row_bytes),
      .rb_addr(rb_addr), .rb_data(rb_data)
  );

  // ack 同步到 clk24 域
  reg a_s1, a_s2, a_s2d;
  always @(posedge clk24) begin
    a_s1  <= ack_tog;
    a_s2  <= a_s1;
    a_s2d <= a_s2;
  end
  wire ack_pulse = a_s2 ^ a_s2d;

  integer errs = 0;

  task do_req(input [8:0] r0);
    begin
      req_row0 <= r0;
      repeat (4) @(posedge clk24);
      req_tog   <= ~req_tog;
      wait (ack_pulse);
      repeat (2) @(posedge clk24);
    end
  endtask

  task chk(input integer row0);
    integer j;
    reg [7:0] exp;
    begin
      for (j=0; j<LINEB*KROWS; j=j+1) begin
        rb_addr = j[AW-1:0];
        @(posedge clk24);
        #1;
        exp = ((row0 + j/LINEB) << 4) | (j % LINEB);
        if (rb_data !== exp) begin
          $display("  ERR  seg_row0=%0d  byte[%0d]  exp=%02x  got=%02x",
                   row0, j, exp, rb_data);
          errs = errs + 1;
        end
      end
      if (last_row_bytes !== LINEB) begin
        $display("  ERR  seg_row0=%0d  last_row_bytes=%0d (expect %0d)",
                 row0, last_row_bytes, LINEB);
        errs = errs + 1;
      end
    end
  endtask

  // ---- 状态追踪 ----
  reg [9:0] t_line = 10'h3FF;
  reg       t_cap = 1'bx;
  reg       t_pend = 1'bx;
  reg       t_ack = 1'bx;
  always @(posedge pclk) begin
    if (rst_n) begin
      if (dut.line_idx !== t_line) begin
        t_line = dut.line_idx;
        $display("  [t=%0t] line_idx -> %0d  href=%b cap_en=%b pend=%b",
                 $time, dut.line_idx, href, dut.cap_en, dut.pend);
      end
      if (dut.cap_en !== t_cap) begin
        t_cap = dut.cap_en;
        $display("  [t=%0t] cap_en -> %b  seg_row0=%0d row_in_seg=%0d frame_ok=%b",
                 $time, dut.cap_en, dut.seg_row0, dut.row_in_seg, dut.frame_ok);
      end
      if (dut.pend !== t_pend) begin
        t_pend = dut.pend;
        $display("  [t=%0t] pend -> %b  pend_row0=%0d", $time, dut.pend, dut.pend_row0);
      end
      if (ack_tog !== t_ack) begin
        t_ack = ack_tog;
        $display("  [t=%0t] ACK TOGGLE  lines_seen=%0d bytes_seen=%0d last_row_bytes=%0d",
                 $time, dut.lines_seen, dut.bytes_seen, dut.last_row_bytes);
      end
    end
  end

  // ---- 看门狗 ----
  initial begin
    #2_000_000;
    $display("WATCHDOG TIMEOUT");
    $display("  line_idx=%0d frame_ok=%b cap_en=%b seg_row0=%0d row_in_seg=%0d pend=%b",
             dut.line_idx, dut.frame_ok, dut.cap_en, dut.seg_row0, dut.row_in_seg, dut.pend);
    $display("  ack_tog=%b lines_seen=%0d bytes_seen=%0d", ack_tog, dut.lines_seen, dut.bytes_seen);
    $display("  href=%b vsync=%b gen_on=%b gline=%0d gpcyc=%0d gvcnt=%0d",
             href, vsync, gen_on, gline, gpcyc, gvcnt);
    $finish;
  end

  initial begin
    rst_n  = 1'b0;
    gen_on = 1'b0;
    repeat (20) @(posedge clk24);
    rst_n = 1'b1;
    repeat (10) @(posedge clk24);
    gen_on = 1'b1;
    // 跑两帧, 让 frame_ok 置位、行号稳定
    repeat (400) @(posedge clk24);

    $display("---- tb_linebuf ----");
    do_req(9'd4); chk(4);  $display("  test1 seg_row0=4  done");
    do_req(9'd0); chk(0);  $display("  test2 seg_row0=0  done");
    do_req(9'd6); chk(6);  $display("  test3 seg_row0=6  done");

    // 行中间发请求: 必须还是从行首开始抓
    wait (href === 1'b1);
    do_req(9'd2); chk(2);  $display("  test4 seg_row0=2 (mid-row req) done");

    $display("lines_seen=%0d bytes_seen=%0d", lines_seen, bytes_seen);
    if (errs == 0) $display("RESULT: PASS");
    else           $display("RESULT: FAIL (%0d errors)", errs);
    $finish;
  end

endmodule

`default_nettype wire
