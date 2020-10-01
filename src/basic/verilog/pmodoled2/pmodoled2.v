// Copyright (c) 2015 Wladimir J. van der Laan
// Distributed under the MIT software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

/* Very simple interface to PMOD SPI. Serial port accepts bytes in the
* form:
*    0001zzzz    Followed by z+1 bytes. Transfer data to SPI.
*    001abcde    Set parallel control flags: a CS, b DC, c RES, e VBATC, f VDDC
* */
`timescale 1 ns / 1 ps

`default_nettype none

module top(input clk,

           output TXD,        // UART TX
           input RXD,         // UART RX

           input resetq,

           output LED0,  // Led
           output LED1,  // Led
           output LED2,  // Led
           output LED4,  // Center led

           output PMOD_CS,
           output PMOD_SDIN,
           output PMOD_SCLK,
           output PMOD_DC,
           output PMOD_RES,
           output PMOD_VBATC,
           output PMOD_VDDC,
);
    localparam MHZ = 12;

    // ######   UART   ##########################################
    //
    reg uart0_valid, uart0_busy;
    wire [7:0] uart0_data_in;
    wire [7:0] uart0_data_out = 0;
    wire uart0_wr = 0;
    wire uart0_rd = 1;
    wire [31:0] uart_baud = 1000000;
    buart #(.CLKFREQ(MHZ * 1000000)) _uart0 (
     .clk(clk),
     .resetq(resetq),
     .baud(uart_baud),
     .rx(RXD),
     .tx(TXD),
     .rd(uart0_rd),
     .wr(uart0_wr),
     .valid(uart0_valid),
     .busy(uart0_busy),
     .tx_data(uart0_data_out),
     .rx_data(uart0_data_in));

    reg led0;
    reg led4;
    reg [4:0] outcount;
    reg halfclk;
    reg [3:0] spi_count; /* number of data bits */
    reg [7:0] spi_data_out;
    reg uart_processed; /* UART input byte processed */

    always @(posedge clk) begin
      // Acme clock divider 12MHz -> 6MHz (to get under max 10MHz)
      halfclk <= ~halfclk;
      // Handle SPI output
      if (halfclk) begin
          // rising edge
          PMOD_SCLK <= 1;
      end else begin
          // falling edge
          if (|spi_count) begin
              // if active - load new data bit on falling edge
              {PMOD_SDIN,spi_data_out} <= {spi_data_out[7:0],1'b1};
              PMOD_SCLK <= 0;
              spi_count <= spi_count - 1;
          end
          LED1 <= spi_count; // Just for fun
      end
      // Handle UART input, if not processed yet
      if (uart0_valid && !uart_processed) begin
          uart_processed <= 1;
          if (|outcount) begin
              // SPI transmission in progress
              outcount <= outcount - 1;
              spi_data_out <= uart0_data_in;
              spi_count <= 8;
              led0 <= ~led0; // Blinkenlights just for fun
          end else begin
              // Handle opcodes
              casez (uart0_data_in)
                  8'b0001zzzz: begin
                      // Send next N+1 bytes to SPI
                      outcount <= (uart0_data_in & 5'b01111) + 1;
                  end
                  8'b001zzzzz: begin
                      // Set flags
                      {PMOD_CS,PMOD_DC,PMOD_RES,PMOD_VBATC,PMOD_VDDC} <= uart0_data_in[4:0];
                  end
                  default: ;
              endcase
              led4 <= ~led4; // Blinkenlights
          end
      end
      // New data word coming in, reset processed flag
      if (~uart0_valid)
          uart_processed <= 0;
    end
    assign LED0 = led0;
    assign LED4 = led4;

endmodule // top
