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

`ifndef SUB_CLOCK_MODULE_V   // Check if SUB_CLOCK_MODULE_V is not defined
`define SUB_CLOCK_MODULE_V   // Define SUB_CLOCK_MODULE_V

module sub_clock_module(
    input   top_clk,
    output  sub_clock,
    output  SI_out_clock
);
    /*output clock hyperparameters*/
    parameter LOW               = 0;
    parameter HIGH              = 1;
    parameter HIGH_COUNT        = 2;
    parameter LOW_COUNT         = 4;
    parameter LOW_COUNT_RISING  = 2;

    /*counters*/
    integer high_counter;
    integer low_counter;

    /*module wiring*/
    reg clock_state_active, SI_out_reg;
    assign sub_clock        = clock_state_active;
    assign SI_out_clock     = SI_out_reg;

    /*module initialisation*/
    initial begin
        clock_state_active  <= LOW;
        SI_out_reg          <= 1;
        high_counter        <= 0;
        low_counter         <= 0;
    end

    /*output clock signal management*/
    always @(posedge top_clk) begin
        case (clock_state_active)
            LOW : begin
                if (low_counter < LOW_COUNT) low_counter <= low_counter + 1;
                if (low_counter == LOW_COUNT) begin
                    clock_state_active  <= HIGH;
                    low_counter         <= 0;
                end
                if (low_counter == LOW_COUNT_RISING) begin
                    SI_out_reg <= 1;
                end
                if (low_counter != LOW_COUNT_RISING) begin
                    SI_out_reg <= 0;
                end
            end 
            HIGH : begin
                if (high_counter == HIGH_COUNT) begin
                    clock_state_active  <= LOW;
                    high_counter        <= 0;
                end
                else high_counter <= high_counter + 1;
            end 
        endcase
    end

endmodule

`endif
