`include "defines.sv"
`include "icicle.sv"
`include "pll.sv"
`include "sync.sv"

module top (
`ifndef INTERNAL_OSC
    input clk,
`endif

`ifdef SPI_FLASH
    /* serial flash */
    output logic flash_clk,
    output logic flash_csn,
    inout flash_io0,
    inout flash_io1,
`endif

    /* LEDs */
    output logic [7:0] leds,

    /* UART */
    input uart_rx,
    output logic uart_tx
);
`ifdef INTERNAL_OSC
    logic clk;

    SB_HFOSC inthosc (
        .CLKHFPU(1'b1),
        .CLKHFEN(1'b1),
        .CLKHF(clk)
    );
`endif

`ifdef SPI_FLASH
    logic flash_io0_en;
    logic flash_io0_in;
    logic flash_io0_out;

    logic flash_io1_en;
    logic flash_io1_in;
    logic flash_io1_out;

`ifdef ICE40
    SB_IO #(
        .PIN_TYPE(6'b1010_01)
    ) flash_io [1:0] (
        .PACKAGE_PIN({flash_io1, flash_io0}),
        .OUTPUT_ENABLE({flash_io1_en, flash_io0_en}),
        .D_IN_0({flash_io1_in, flash_io0_in}),
        .D_OUT_0({flash_io1_out, flash_io0_out})
    );
`elsif ECP5
    TRELLIS_IO #(
        .DIR("BIDIR")
    ) flash_io [1:0] (
        .B({flash_io1, flash_io0}),
        .T({flash_io1_en, flash_io0_en}),
        .I({flash_io1_in, flash_io0_in}),
        .O({flash_io1_out, flash_io0_out})
    );
`endif
`endif

    logic pll_clk;
    logic pll_locked_async;

    pll pll (
`ifdef ECP5
        .clki(clk),
        .clko(pll_clk),
`else
        .clock_in(clk),
        .clock_out(pll_clk),
`endif
        .locked(pll_locked_async)
    );

    logic pll_locked;
    logic reset;

    logic [3:0] reset_count;

    initial
        reset_count <= 0;

    always_ff @(posedge pll_clk) begin
        if (&reset_count) begin
            if (pll_locked) begin
                reset <= 0;
            end else begin
                reset <= 1;
                reset_count <= 0;
            end
        end else begin
            reset <= 1;
            reset_count <= reset_count + pll_locked;
        end
    end

    sync sync (
        .clk(pll_clk),
        .in(pll_locked_async),
        .out(pll_locked)
    );

    icicle icicle (
        .clk(pll_clk),
        .reset(reset),

`ifdef SPI_FLASH
        /* serial flash */
        .flash_clk(flash_clk),
        .flash_csn(flash_csn),

        .flash_io0_en(flash_io0_en),
        .flash_io0_in(flash_io0_in),
        .flash_io0_out(flash_io0_out),

        .flash_io1_en(flash_io1_en),
        .flash_io1_in(flash_io1_in),
        .flash_io1_out(flash_io1_out),
`endif

        /* LEDs */
        .leds(leds),

        /* UART */
        .uart_rx(uart_rx),
        .uart_tx(uart_tx)
    );
endmodule
