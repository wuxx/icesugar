/*
 *  icebreaker examples - Async uart mirror using pll
 *
 *  Copyright (C) 2018 Piotr Esden-Tempski <piotr@esden.net>
 *
 *  Permission to use, copy, modify, and/or distribute this software for any
 *  purpose with or without fee is hereby granted, provided that the above
 *  copyright notice and this permission notice appear in all copies.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 *  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 *  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 *  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 *  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 *  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 *  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 */

`include "uart_rx.v"
`include "uart_tx.v"

module top (
	input  clk,
	input RX,
  	output TX,
	output LED_R,
	output LED_G
);

wire clk_42mhz;
//assign clk_42mhz = clk;
SB_PLL40_PAD #(
  .DIVR(4'b0000),
  // 42MHz
  .DIVF(7'b0110111),
  .DIVQ(3'b100),
  .FILTER_RANGE(3'b001),
  .FEEDBACK_PATH("SIMPLE"),
  .DELAY_ADJUSTMENT_MODE_FEEDBACK("FIXED"),
  .FDA_FEEDBACK(4'b0000),
  .DELAY_ADJUSTMENT_MODE_RELATIVE("FIXED"),
  .FDA_RELATIVE(4'b0000),
  .SHIFTREG_DIV_MODE(2'b00),
  .PLLOUT_SELECT("GENCLK"),
  .ENABLE_ICEGATE(1'b0)
) usb_pll_inst (
  .PACKAGEPIN(clk),
  .PLLOUTCORE(clk_42mhz),
  .EXTFEEDBACK(),
  .DYNAMICDELAY(),
  .RESETB(1'b1),
  .BYPASS(1'b0),
  .LATCHINPUTVALUE(),
  .LOCK(),
  .SDI(),
  .SDO(),
  .SCLK()
);

/* local parameters */
//localparam clk_freq = 12_000_000; // 12MHz
localparam clk_freq = 42_000_000; // 42MHz
//localparam baud = 57600;
localparam baud = 115200;


/* instantiate the rx1 module */
wire reg rx1_ready;
wire reg [7:0] rx1_data;
uart_rx #(clk_freq, baud) urx1 (
	.clk(clk_42mhz),
	.rx(RX),
	.rx_ready(rx1_ready),
	.rx_data(rx1_data),
);

/* instantiate the tx1 module */
wire reg tx1_start;
wire reg [7:0] tx1_data;
wire reg tx1_busy;
uart_tx #(clk_freq, baud) utx1 (
	.clk(clk_42mhz),
	.tx_start(tx1_start),
	.tx_data(tx1_data),
	.tx(TX),
	.tx_busy(tx1_busy)
);

// Send the received data immediately back

wire reg [7:0] data_buf;
wire reg data_flag = 0;
wire reg data_check_busy = 0;
always @(posedge clk_42mhz) begin

  // we got a new data strobe
  // let's save it and set a flag
	if(rx1_ready && ~data_flag) begin
    data_buf <= rx1_data;
    data_flag <= 1;
    data_check_busy <= 1;
  end

  // new data flag is set let's try to send it
  if(data_flag) begin

    // First check if the previous transmission is over
    if(data_check_busy) begin
      if(~tx1_busy) begin
        data_check_busy <= 0;
      end // if(~tx1_busy)

    end else begin // try to send waiting for busy to go high to make sure
      if(~tx1_busy) begin
        tx1_data <= data_buf;
        tx1_start <= 1'b1;
        LED_R <= ~data_buf[0];
        LED_G <= ~data_buf[1];
      end else begin // Yey we did it!
        tx1_start <= 1'b0;
        data_flag <= 0;
      end
    end
  end
end

// Loopback the TX and RX lines with no processing
// Useful as a sanity check ;-)
//assign TX = RX;

endmodule
