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

`include "sub_clock_module.v"
`include "flash_module.v"

module main (
    input   clk,
    input   miso,
    output  cs,
    output  sck,
    output  mosi
);
    /*system wiring*/
    reg flash_start;
    wire flash_done;
    wire sub_clock, SI_out_clock;

    wire [1023:0] SO_data;
    reg [1055:0] SI_data;
    reg [11:0] SI_len;
    reg [11:0] SO_len;
    reg [11:0] OP_end;

    /*device states*/
    reg [3:0] DEVICE_STATE;
    parameter RESUME_PREP           = 4'b0000;
    parameter RESUME                = 4'b0001;
    parameter READ_ID_PREP          = 4'b0010;
    parameter READ_ID               = 4'b0100;
    parameter DEFAULT               = 4'b1000;

    initial begin
        SI_data         <= 0;
        SI_len          <= 0;
        SO_len          <= 0;
        OP_end          <= 0;
        flash_start     <= 0;
        DEVICE_STATE    <= RESUME_PREP;
    end

    always @ (posedge clk) begin
        case (DEVICE_STATE)
            RESUME_PREP : begin
                SI_data[7:0]    <= {8'hAB};             // opcode for RESUME
                SI_len          <= 12'b000000000111;    // 7
                SO_len          <= 12'b000000000000;    // 0
                OP_end          <= 12'b000000001000;    // 8
                DEVICE_STATE    <= RESUME;
            end
            RESUME : begin
                if (flash_done == 0) flash_start <= 1;
                if (flash_done == 1 && flash_start == 1) begin
                    flash_start     <= 0;
                    SI_data         <= 0;
                    DEVICE_STATE    <= READ_ID_PREP;
                end
            end
            READ_ID_PREP : begin
                SI_data[31:0]   <= {8'h90, 24'h000000};                 // opcode for Read Device ID
                SI_len          <= 12'b000000011111;                    // 31
                SO_len          <= 12'b000000001111;                    // 15
                OP_end          <= 12'b000000110000;                    // 48
                DEVICE_STATE    <= READ_ID;
            end
            READ_ID : begin
                if (flash_done == 0) flash_start <= 1;
                if (flash_done == 1 && flash_start == 1) begin
                    flash_start     <= 0;
                    SI_data         <= 0;
                    DEVICE_STATE    <= READ_ID_PREP;
                end
            end
            DEFAULT: begin
            end
        endcase
    end

    /*flash_modules*/
    flash_module flash_module (
        .top_clk(sub_clock),
        .sub_clk(SI_out_clock),
        .flash_start(flash_start),
        .SI_data(SI_data),
        .SI_len(SI_len),
        .SO_len(SO_len),
        .OP_end(OP_end),
        .miso(miso),
        .cs(cs),
        .sck(sck),
        .mosi(mosi),
        .SO_data(SO_data),
        .flash_done(flash_done)
    );

    /*clock module management*/
    sub_clock_module sub_clock_module (
        .top_clk(clk),
        .sub_clock(sub_clock),
        .SI_out_clock(SI_out_clock)
    );

endmodule