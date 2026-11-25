// ============================================================================
//  top.v -- iCESugar + PMOD-LCD-0.96 (ST7735S 160x80) 顶层
//
//  功能: 上电后自动初始化 LCD 并刷 8 条竖直色条, 不需要任何 CPU 干预。
//
//  引脚 (iCESugar v1.5, 依据 src/common/io.pcf; PMOD3):
//      clk12     35   板载 12MHz (iCELink MCO 输出)
//      lcd_cs_n  34   PMOD3-1   LCD 片选 (低有效)
//      lcd_mosi  31   PMOD3-2   LCD 数据 (MOSI)
//      lcd_dc    27   PMOD3-3   0=命令 1=数据
//      lcd_sck   25   PMOD3-4   LCD 时钟
//      lcd_rst_n 23   PMOD3-9   LCD 复位 (低有效)
// ============================================================================
`default_nettype none

module top (
    input  wire clk12,      // pin 35
    output wire lcd_cs_n,   // pin 34
    output wire lcd_mosi,   // pin 31
    output wire lcd_dc,     // pin 27
    output wire lcd_sck,    // pin 25
    output wire lcd_rst_n   // pin 23
);

    localparam integer CLK_HZ  = 24_000_000;
    localparam integer SCK_DIV = 4;              // SCLK = 24MHz/(2*4) = 3MHz

    // ------------------------------------------------------------------
    //  PLL: 12MHz -> 24MHz
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
    //  上电复位: 计数 1000 拍 (~42us) 后释放
    //  计数器必须饱和, 否则 16 位回绕会让 rst_n 反复拉低
    // ------------------------------------------------------------------
    reg [15:0] rst_cnt = 16'd0;
    always @(posedge clk24) begin
        if (rst_cnt != 16'hFFFF) rst_cnt <= rst_cnt + 1'b1;
    end
    wire rst_n = (rst_cnt >= 16'd1000);

    // ------------------------------------------------------------------
    //  ST7735 驱动
    // ------------------------------------------------------------------
    st7735 #(
        .CLK_HZ(CLK_HZ),
        .SCK_DIV(SCK_DIV),
        .INIT_HEX("st7735_init.hex")
    ) u_lcd (
        .clk(clk24),
        .rst_n(rst_n),
        .lcd_rst_n(lcd_rst_n),
        .lcd_cs_n(lcd_cs_n),
        .lcd_dc(lcd_dc),
        .lcd_sck(lcd_sck),
        .lcd_mosi(lcd_mosi),
        .busy(),
        .done()
    );

endmodule

`default_nettype wire
