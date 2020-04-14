/*
 *  icebreaker examples - Async uart rx module
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

`ifndef _uart_rx_v_
`define _uart_rx_v_

`include "uart_baud_tick_gen.v"

module uart_rx(
	input clk,
	input rx,
	output reg rx_ready,
	output reg [7:0] rx_data, // data received, valid onli (for one clock cycle) when rx_read is asserted

	// We also detect if a gap occurs in the received stream of characters
	// That can be useful if multiple characters are sent in a burst
	// This allows us to consider a block of characters as a "packet"
	output rx_idle, // asserted when no data has been received for a while
	output reg rx_eop = 0 // asserted for one clock cycle when an end of packet has been detected
);

parameter clk_freq = 12000000;
parameter baud = 115200;

parameter oversampling = 8; // needs to be power of 2
// we oversample the rx line at fixed rate to capture each rx data bit
// 8 times oversampling by default, use 16 for higher reception quality.

localparam
	IDLE      = 4'b0000,
	BIT_START = 4'b0001,
	BIT0      = 4'b1000,
	BIT1      = 4'b1001,
	BIT2      = 4'b1010,
	BIT3      = 4'b1011,
	BIT4      = 4'b1100,
	BIT5      = 4'b1101,
	BIT6      = 4'b1110,
	BIT7      = 4'b1111,
	BIT_STOP  = 4'b0010;

reg [3:0] rx_state = 0;

wire os_tick;
baud_tick_gen #(clk_freq, baud, oversampling) tickgen(.clk(clk), .enable(1'b1), .tick(os_tick));

// sync rx to our clock domain
reg [1:0] rx_sync = 2'b11;
always @(posedge clk) if(os_tick) rx_sync <= {rx_sync[0], rx};

// filter/debounce rx
reg [1:0] filter_cnt = 2'b11;
reg rx_bit = 1'b1;
always @(posedge clk)
	if(os_tick) begin
		// increment/decrement filter_cnt
		// the filter_cnt counts up when rx_sync is high until it reaches 2'b11
		// the filter_cnt counts down when rx_sync is low until it reaches 2'b00
		// this filter will ignore glitches of length up to 2 x oversampling period
		// the filter does not provide hold hysteresis
		if((rx_sync[1] == 1'b1) && (filter_cnt != 2'b11)) filter_cnt <= filter_cnt + 1'd1;
		if((rx_sync[1] == 1'b0) && (filter_cnt != 2'b00)) filter_cnt <= filter_cnt - 1'd1;

		// set rx_bit output high when filter_cnt reaches max and low when min
		if(filter_cnt == 2'b11) rx_bit <= 1'b1;
		else 
		if(filter_cnt == 2'b00) rx_bit <= 1'b0;
		// XXX: we probably should set rx_bit to some defined value when filter_cnt is not 11 nor 00.
	end

// create an appropriate oversampling counter
// using the counter we generate a sample_now signal offset by 90deg from the rx data clock phase
function integer log2(input integer v); begin log2 = 0; while(v >> log2) log2 = log2 + 1; end endfunction
localparam l2o = log2(oversampling);
reg [l2o-2:0] os_cnt = 0;
always @(posedge clk) if(os_tick) os_cnt <= (rx_state == IDLE) ? 1'd0 : os_cnt + 1'd1;
wire sample_now = os_tick && (os_cnt == ((oversampling / 2) - 1));

// rx data finite state machine
always @(posedge clk)
	case(rx_state)
		IDLE:      if(~rx_bit) rx_state <= BIT_START;
		BIT_START: if(sample_now) rx_state <= BIT0;
		BIT0:      if(sample_now) rx_state <= BIT1;
		BIT1:      if(sample_now) rx_state <= BIT2;
		BIT2:      if(sample_now) rx_state <= BIT3;
		BIT3:      if(sample_now) rx_state <= BIT4;
		BIT4:      if(sample_now) rx_state <= BIT5;
		BIT5:      if(sample_now) rx_state <= BIT6;
		BIT6:      if(sample_now) rx_state <= BIT7;
		BIT7:      if(sample_now) rx_state <= BIT_STOP;
		BIT_STOP:  if(sample_now) rx_state <= IDLE;
		default:   rx_state <= IDLE;
	endcase

// accumulate rx data into the rx_data shift register
// rx_state[3] -> this bit is only high when the state machine is in state BIT0:7
always @(posedge clk) begin
	if(sample_now && rx_state[3]) begin
		rx_data <= {rx_bit, rx_data[7:1]};
	end
end

// reg rx_error = 0;
always @(posedge clk)
begin
	rx_ready <= (sample_now && (rx_state == BIT_STOP) && rx_bit); // Stay high for the duration of stop bit
	//rx_error <= (sample_now && (rx_state == BIT_STOP) && ~rx_bit);
end

// measure gap size between bytes to determine if bus is idle and if the "packet" ended
reg [l2o+1:0] gap_cnt = 0;
always @(posedge clk)
	if (rx_state != IDLE) 
		gap_cnt <= 0;
	else
		if(os_tick & ~gap_cnt[l2o+1]) gap_cnt <= gap_cnt + 1'd1;
assign rx_idle = gap_cnt[l2o+1];
always @(posedge clk) rx_eop <= os_tick & ~gap_cnt[l2o+1] & &gap_cnt[l2o:0];

endmodule

`endif // _uart_rx_v_
