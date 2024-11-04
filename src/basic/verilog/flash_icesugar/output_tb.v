/*
 *  
 *  Copyright(C) 2024 Kai Harris <matchahack@gmail.com>
 * 
 *  Permission to use, copy, modify, and/or distribute this software for any purpose with or
 *  without fee is hereby granted, provided that the above copyright notice and 
 *  this permission notice appear in all copies.
 * 
 *  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO
 *  THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS. 
 *  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL 
 *  DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN
 *  AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN 
 *  CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 * 
 */
 
`timescale 1 ns / 1 ps  // Time scale directive, 1 ns time unit, 1 ps time precision

module output_tb();
    wire cs, sck, mosi;
    reg clk = 0;

    localparam CLK_PERIOD       = 83.33; // 12 MHz clock -> 1/12_000_000 second period -> 83.33 nanosecons
    localparam HALF_CLK_PERIOD  = 41.67;
    localparam DURATION         = 100000;
    
    main uut (
        .clk(clk),
        .cs(cs),
        .sck(sck),
        .mosi(mosi)
    );

    // VCD dump for waveform analysis
    initial begin
        $dumpfile("output_tb.vcd");    // Create VCD file for simulation waveform output
        $dumpvars(0, output_tb);       // Dump variables from top module (output_tb)
        #(DURATION);                   // Run simulation for specified duration
        $finish;                       // End the simulation
    end

    // Clock generation block
    always begin
        #(HALF_CLK_PERIOD)             // Half-period delay
        clk = ~clk;                    // Toggle clock signal every half period
    end

endmodule
