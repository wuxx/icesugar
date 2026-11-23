// ============================================================================
//  tb_top_photo.v -- 整个 top_photo 的离线仿真 (iverilog)
//
//  目的: 把"RTL 有问题"和"硬件/比特流有问题"彻底分开。
//  办法: 用桩件替掉 SB_PLL40_PAD / SB_IO, 直接仿真顶层, 把 TX 上的串口
//  字节解出来, 看复位后是不是真的发出了"上电信标"状态包。
//
//  桩件 (同一文件里):
//    SB_PLL40_PAD  -> 输出 24MHz (和真板子一致)
//    SB_IO         -> 直通
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

// ---------------------------------------------------------------- 桩件
module SB_PLL40_PAD #(
    parameter FEEDBACK_PATH = "SIMPLE",
    parameter [3:0] DIVR = 4'd0,
    parameter [6:0] DIVF = 7'd0,
    parameter [2:0] DIVQ = 3'd0,
    parameter [2:0] FILTER_RANGE = 3'd0
)(
    input  wire RESETB,
    input  wire BYPASS,
    input  wire PACKAGEPIN,
    output wire PLLOUTCORE
);
    reg pll_clk = 1'b0;
    always #20.8333 pll_clk = ~pll_clk;      // 24 MHz
    assign PLLOUTCORE = pll_clk;
endmodule

module SB_IO #(
    parameter [5:0] PIN_TYPE = 6'b000000,
    parameter PULLUP = 1'b0
)(
    inout  wire PACKAGE_PIN,
    input  wire OUTPUT_CLK,
    input  wire D_OUT_0,
    input  wire D_OUT_1,
    output wire D_IN_0,
    input  wire OUTPUT_ENABLE
);
    assign D_IN_0 = PACKAGE_PIN;
endmodule

// ---------------------------------------------------------------- 测试台
module tb_top_photo;

  //  必须和 top_photo.v 的 PHOTO_BAUD 默认值一致 (115200)
  localparam integer BAUD = 115200;
  localparam integer BITC = 24_000_000 / BAUD;

  reg clk12 = 1'b0;
  always #41.6666 clk12 = ~clk12;           // 12MHz (真实值, 桩件会转成 24MHz)

  // 摄像头数据 (仿真里给不给都行, 信标包不看图像)
  reg [7:0] D = 8'h00;
  reg HREF = 1'b0, VSYNC = 1'b0;

  wire TX;
  wire LED_R, LED_G, LED_B;

  top_photo dut (
      .clk12(clk12), .TX(TX),
      .LED_R(LED_R), .LED_G(LED_G), .LED_B(LED_B),
      .XMCLK(), .SCL(), .SDA(),
      .PCLK(), .VSYNC(VSYNC), .HREF(HREF), .D(D)
  );

  // ---- UART 接收 ----
  reg [7:0] rxbuf [0:511];
  integer rxn = 0;
  reg [7:0] rxb;
  integer bi;

  always begin
    @(negedge TX);
    //  1.5 个位时间 = 第 0 个数据位的中间 (等半个位会采到起始位, 整体错一位)
    repeat (BITC + (BITC/2)) @(posedge dut.clk24);
    for (bi=0; bi<8; bi=bi+1) begin
      rxb[bi] = TX;
      repeat (BITC) @(posedge dut.clk24);
    end
    //  每个字节的接收耗时必须 <= 10 个位时间, 否则会错过起始位的下降沿
    rxbuf[rxn] = rxb;
    rxn = rxn + 1;
  end

  integer i;
  integer fh;

  // 看门狗
  initial begin
    #30_000_000;
    $display("WATCHDOG: rxn=%0d  st=%0d  led(B=%b G=%b R=%b)",
             rxn, dut.st, LED_B, LED_G, LED_R);
    $display("  hello_sent=%b diag_code=%0d cfg_done=%b cfg_fail=%b",
             dut.hello_sent, dut.diag_code, dut.cfg_done, dut.cfg_fail);
    $finish;
  end

  initial begin
    fh = $fopen("sim_top.hex", "w");
    repeat (200) @(posedge dut.clk24);
    // 等信标包 (复位后立刻发)
    //  状态包总长 = 包头6(magic+row+len) + 数据16 + CRC2 = 24 字节
    wait (rxn >= 24);
    repeat (50) @(posedge dut.clk24);
    $display("---- tb_top_photo ----");
    $display("  rx bytes = %0d", rxn);
    $display("  st=%0d hello_sent=%b diag_code=%0d", dut.st, dut.hello_sent, dut.diag_code);
    $fwrite(fh, "%0d\n", rxn);
    for (i=0; i<rxn; i=i+1) $fwrite(fh, "%02x", rxbuf[i]);
    $fwrite(fh, "\n");
    $fclose(fh);
    $finish;
  end

endmodule

`default_nettype wire
