# DSP example on ice40 ultraplus

This example show how to use the DSP blocks (`SB_MAC16`) within the ice40 ultraplus fpga to implement MAC (multiply and accumulate) operations. The sequence of operations are the following:

```
a <- 127
a <- a + (a*5)
a <- a + (a*a)
a == 581406
```
If the result of this calculation is correct, it will light up the LED as white.

Two implementations of this calculation are made, one without DSP `calc.v` and the other using a DSP block `calc_dsp.v`, they apply the above calculation one operation per cycle and light up the led if the result is correct.

DSP block can be added to a module as `SB_MAC16`, they need some parameters in order to define if they will be used as multipliers or adders, in this example, the DSP is used as a MAC with 16x16bits inputs and 32bit output, by putting `2` to the two parameters `TOPADDSUB_LOWERINPUT` and `BOTADDSUB_LOWERINPUT`.

Here are the fpga elements usage for both implementations, the multiplications have a serious impact on logic cell usage when not using a DSP:

| element | calc.v | calc_dsp.v |
|---|---|---|
| LCs | 1280 | 64 |
| MAC16s  | 0 | 1 |

The two modules, with and without the dsp are in the `top.v` file, only one can be used at once.

To note that in a very recent or future implementation of yosys, it will be able to infer DSP from the verilog (https://twitter.com/oe1cxw/status/1098647996445659136?lang=en).
