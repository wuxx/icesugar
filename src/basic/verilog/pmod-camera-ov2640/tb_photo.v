// ============================================================================
//  tb_photo.v -- photo_tx 离线验证 (iverilog)
//  把串口输出还原成字节, 和主机端的算法逐字节比对:
//    行包 = A5 5A | row(2) | len(2) | data | crc(2)
//    CRC16/CCITT-FALSE 覆盖 "行号(2)+长度(2)+数据", magic 不参与计算
//  重点验证: 第 2 行的数据必须来自缓冲的第 2 行 (row_off 递进), 而不是又从第 0 行开始。
//
//  UART 接收模型的一个坑 (踩过):
//    下降沿 = 起始位的前沿。从这里再等半个位时间, 采到的还是起始位,
//    整个字节会整体错一位 (0xA5 被解成 0x4A)。正确做法是等 1.5 个位时间,
//    也就是第 0 个数据位的正中间。
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_photo;

  localparam integer CLK_HZ = 24_000_000;
  localparam integer BAUD  = 9600;       // 仿真用慢速, 方便采样
  localparam integer LINEB = 8;
  localparam integer KROWS = 2;
  localparam integer AW    = 4;          // 2 行 x 8 字节 = 16 -> 4 位
  localparam integer BITC  = CLK_HZ / BAUD;

  reg clk = 1'b0;
  always #20.8333 clk = ~clk;           // 24 MHz

  reg rst_n = 1'b0;
  reg go    = 1'b0;
  reg stat_ena = 1'b0;
  reg [127:0] stat_data = 128'd0;
  reg [8:0]  row0 = 9'd0;
  wire done;
  wire [AW-1:0] rb_addr;
  wire rb_adv;
  reg  [7:0]  rb_data;
  wire tx;

  reg [7:0] mem [0:15];
  integer i;
  initial begin
    for (i=0; i<16; i=i+1) mem[i] = i[7:0] + 8'd1;   // 1..16
  end

  photo_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD), .LINEB(LINEB), .KROWS(KROWS), .AW(AW)) dut (
      .clk(clk), .rst_n(rst_n), .go(go), .stat_ena(stat_ena),
      .stat_data(stat_data), .row0(row0), .done(done),
      .rb_addr(rb_addr), .rb_adv(rb_adv), .rb_data(rb_data), .tx(tx)
  );

  //  行缓冲读口模型 (同步读, 1 拍延迟)
  always @(posedge clk) rb_data <= mem[rb_addr];

  //  ---- UART 接收 ----
  reg [7:0] rxbuf [0:255];
  integer rxn = 0;
  reg [7:0] rxb;
  integer bi;
  integer fh;

  always begin
    @(negedge tx);
    repeat (BITC + (BITC/2)) @(posedge clk);   // 1.5 位 -> 第 0 个数据位的中间
    for (bi=0; bi<8; bi=bi+1) begin
      rxb[bi] = tx;
      repeat (BITC) @(posedge clk);
    end
    //  这里不能再多等: 线上一个字节是 10 个位时间(起始1+数据8+停止1),
    //  接收模型每个字节也必须 <= 10 位时间, 否则相位会越飘越远,
    //  最后错过下一个起始位的下降沿 -> 隔一个字节丢一个。
    //  循环结束时已经在停止位中间(8.5 位), 直接等下一个下降沿(9.0 位)即可。
    rxbuf[rxn] = rxb;
    rxn = rxn + 1;
  end

  initial begin
    fh = $fopen("sim_photo.hex", "w");
    repeat (20) @(posedge clk);
    rst_n = 1'b1;
    repeat (10) @(posedge clk);

    // ---- 先发一个状态包 ----
    //  激励必须和 DUT 的采样错开: 用 #1 拉开, 否则初值块和 DUT 在同一个
    //  时钟沿上竞争, DUT 有可能采到已经清零的 go。
    stat_data = 128'h112233445566778899AABBCCDDEEFF00;
    stat_ena  = 1'b1;
    go         = 1'b1;
    @(posedge clk);
    #1;
    go         = 1'b0;
    stat_ena  = 1'b0;
    wait (done);
    repeat (BITC*12) @(posedge clk);      // 等最后一个字节真正发完

    // ---- 再发一个图像段包 (2 行) ----
    row0 = 9'd0;
    go   = 1'b1;
    @(posedge clk);
    #1;
    go   = 1'b0;
    wait (done);
    repeat (BITC*12) @(posedge clk);      // 同上

    $fwrite(fh, "%0d\n", rxn);
    for (i=0; i<rxn; i=i+1) $fwrite(fh, "%02x", rxbuf[i]);
    $fwrite(fh, "\n");
    $fclose(fh);
    $display("TB DONE bytes=%0d", rxn);
    $finish;
  end

endmodule

`default_nettype wire
