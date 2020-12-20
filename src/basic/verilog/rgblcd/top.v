module TOP
(
	input  reset,
    input  CLK,

	output LCD_CLK,
	output LCD_HYNC,
	output LCD_SYNC,
	output LCD_DEN,
	output [4:0] LCD_R,
	output [5:0] LCD_G,
	output [4:0] LCD_B,

);

	wire PCLK;

    /* 18Mhz $icepll -o 18Mhz */
    SB_PLL40_PAD #(
            .FEEDBACK_PATH("SIMPLE"),
            .DIVR(4'b0000),         // DIVR =  0
            .DIVF(7'b0101111),      // DIVF =  48
            .DIVQ(3'b101),          // DIVQ =  5
            .FILTER_RANGE(3'b001)   // FILTER_RANGE = 1
            ) uut (
                .RESETB(1'b1),
                .BYPASS(1'b0),
                .PACKAGEPIN(CLK),
                .PLLOUTCORE(PCLK)
            );

	LCDC _LCDC
	(
		.rst	   (reset),

		.pclk	   (PCLK),
		.LCD_DE	   (LCD_DEN),
		.LCD_HSYNC (LCD_HYNC),
    	.LCD_VSYNC (LCD_SYNC),

		.LCD_B	   (LCD_B),
		.LCD_G	   (LCD_G),
		.LCD_R	   (LCD_R)
	);

	assign LCD_CLK = PCLK;

endmodule
