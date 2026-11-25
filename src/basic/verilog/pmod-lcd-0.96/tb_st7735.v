// ============================================================================
//  tb_st7735.v -- ST7735 驱动离线仿真: 抓 SPI 上的字节流
//
//  跑法 (在工程目录下):
//      iverilog -g2005 -o tb_st7735.vvp tb_st7735.v st7735.v
//      vvp tb_st7735.vvp
//      python3 chk_lcd_stream.py spi_stream.txt
//
//  输出 spi_stream.txt: 每行 "<DC> <字节>", DC=0 命令 / 1 数据
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_st7735;

    reg  clk = 1'b0;
    reg  rst_n = 1'b0;
    always #10 clk = ~clk;              // 仿真时钟 (只用拍数, 不影响时序比例)

    wire lcd_rst_n, lcd_cs_n, lcd_dc, lcd_sck, lcd_mosi;
    wire busy, done;

    st7735 #(
        .CLK_HZ(24_000_000),
        .SCK_DIV(4),
        .INIT_HEX("st7735_init.hex")
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .lcd_rst_n(lcd_rst_n),
        .lcd_cs_n(lcd_cs_n),
        .lcd_dc(lcd_dc),
        .lcd_sck(lcd_sck),
        .lcd_mosi(lcd_mosi),
        .busy(busy),
        .done(done)
    );

    initial begin
        #1000 rst_n = 1'b1;             // 释放外部复位
    end

    // ---------------- SPI 字节监视器 ----------------
    integer fd;
    integer cnt;
    integer nbytes;
    reg [7:0] sh;

    initial begin
        fd     = $fopen("spi_stream.txt", "w");
        cnt    = 0;
        nbytes = 0;
        sh     = 8'h00;
    end

    always @(posedge lcd_sck) begin
        if (!lcd_cs_n) begin
            sh = {sh[6:0], lcd_mosi};
            cnt = cnt + 1;
            if (cnt == 8) begin
                cnt = 0;
                nbytes = nbytes + 1;
                $fwrite(fd, "%b %02x\n", lcd_dc, sh);
            end
        end
    end

    // ---------------- 收尾 ----------------
    always @(posedge done) begin
        $fwrite(fd, "#TOTAL %0d\n", nbytes);
        $fclose(fd);
        $display("tb: done, %0d bytes on SPI", nbytes);
        $finish;
    end

    initial begin
        #2000000000;
        $display("tb: TIMEOUT");
        $finish;
    end

endmodule

`default_nettype wire
