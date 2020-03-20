# PLL and clock example

This example shows how to use the internal oscillators as clocks and use the unique PLL in the iCE40 Ultraplus.

The example blinks the LED at two different frequencies, one is the internal oscillator at 48MHz, the other clock is at 24MHz.
The 24MHz frequency is obtained from the PLL, taking as input the 48MHz clock.

The ice40 ultraplus has two internal clocks, 48MHz and 10KHz, the clock can be used, by taking the output signal of the `SB_HFOSC` module for the 48MHz freq and the `SB_LFOSC` for the 10KHz.

The PLL module can be used either as `SB_PLL40_CORE` or `SB_PLL40_PAD`, the PAD will take an external IO clock as input (such as the 12MHz used in the breakout board). The CORE will take a signal clock (such as the internal one).

It seems that if the CORE_PLL is used with an internal clock, it is not possible to have the 12MHz external clock.

To get the configuration for the PLL, the `icepll` tool was used and it gives the parameters for the PLL to achieve the desired frequency:

```
./icepll -i 48 -o 24

F_PLLIN:    48.000 MHz (given)
F_PLLOUT:   24.000 MHz (requested)
F_PLLOUT:   24.000 MHz (achieved)

FEEDBACK: SIMPLE
F_PFD:   48.000 MHz
F_VCO:  768.000 MHz

DIVR:  0 (4'b0000)
DIVF: 15 (7'b0001111)
DIVQ:  5 (3'b101)

FILTER_RANGE: 4 (3'b100)
```

The `nextpnr-ice40` tool is used for routing as it provides timing analysis. It is possible to set the clock constraints with a python file, however a simple frequency for all clocks can be used by adding `-freq 48` to the parameters for 48MHz clock.  
The output will be:

```
Info: Max frequency for clock          'clk_48mhz': 56.27 MHz (PASS at 48.00 MHz)
Info: Max frequency for clock 'clk_24mhz_$glb_clk': 60.85 MHz (PASS at 48.00 MHz)

Info: Max delay posedge clk_24mhz_$glb_clk -> <async>: 9.98 ns
Info: Max delay posedge clk_48mhz          -> <async>: 8.66 ns
```
