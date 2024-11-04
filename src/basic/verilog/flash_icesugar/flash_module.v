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

`ifndef FLASH_MODULE_V   // Check if FLASH_MODULE_V is not defined
`define FLASH_MODULE_V   // Define FLASH_MODULE_V

module flash_module(
    input   top_clk,
    input   sub_clk,
    input   flash_start,
    input   [1055:0] SI_data,
    input   [11:0] SI_len,
    input   [11:0] SO_len,
    input   [11:0] OP_end,
    input   miso,
    output  cs,
    output  sck,
    output  mosi,
    output  [1023:0] SO_data,
    output  flash_done
);
    /*module wiring*/
    reg CS_register, MOSI_register, SCK_register;
    reg [1023:0] SO_register;
    assign cs               = CS_register;
    assign sck              = SCK_register;
    assign mosi             = MOSI_register;
    assign SO_data          = SO_register;

    /*operation state*/
    parameter await_delay   = 0;
    parameter perform_op    = 1;
    reg clock_state, clock_start_flag, flash_done_register;
    assign flash_done = flash_done_register;

    /*operation delay*/
    parameter OPERATION_DELAY = 4'b1111;
    reg [3:0] delay_counter;

    /*counters and flags*/
    integer operation_counter, SI_pulse, SO_pulse;

    /*initialisation*/
    initial begin
        clock_state             <= await_delay;
        delay_counter           <= 0;
        operation_counter       <= 0;
        SI_pulse                <= 0;
        SO_pulse                <= 0;
        clock_start_flag        <= 0;
        CS_register             <= 1;
        flash_done_register     <= 0;
    end

    /*CS, SI and SO control*/
    always @ (posedge sub_clk) begin
        if (delay_counter == 0) flash_done_register <= 0;
        if (flash_start == 1 && flash_done_register == 0) begin
            case (clock_state)
                await_delay : begin
                    delay_counter <= delay_counter + 1;
                    if (delay_counter == OPERATION_DELAY - 1) begin
                        CS_register     <= 0;
                        clock_state     <= perform_op;
                        MOSI_register   <= SI_data[SI_len];
                    end
                end
                perform_op : begin
                    if (delay_counter == OPERATION_DELAY) begin
                        clock_start_flag <= 1;
                    end begin
                        operation_counter <= operation_counter + 1;
                        if (SO_len == 0) begin
                            if (operation_counter <= SI_len) begin
                                SI_pulse        <= SI_pulse + 1;
                                MOSI_register   <= SI_data[SI_len - SI_pulse];
                            end
                        end
                        if (SO_len != 0) begin
                            if (operation_counter <= SI_len) begin
                                SI_pulse        <= SI_pulse + 1;
                                MOSI_register   <= SI_data[SI_len - SI_pulse];
                            end
                            if (operation_counter > SI_len && operation_counter < OP_end) begin
                                SO_pulse                        <= SO_pulse + 1;
                                SO_register[SO_len - SO_pulse]  <= miso;
                            end
                        end
                        if (operation_counter == OP_end) begin
                            clock_state             <= await_delay;
                            delay_counter           <= 0;
                            operation_counter       <= 0;
                            SI_pulse                <= 0;
                            clock_start_flag        <= 0;
                            MOSI_register           <= SI_data[SI_len];
                            CS_register             <= 1;
                            flash_done_register     <= 1;
                        end
                    end
                end
            endcase
        end
    end

    /*SCK wiring control*/
    always @ (*) begin
        if (clock_start_flag == 1) SCK_register <= top_clk;
        else SCK_register <= 0;
    end

endmodule

`endif