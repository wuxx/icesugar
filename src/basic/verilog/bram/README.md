# BRAM example

The goal of this example was to understand how yosys infer BRAM from verlog arrays.
The ice40 ultraplus has 30 BRAM of 4kbit, and each BRAM can save a lot of LUT logic, so understanding how they are used is important.

Two versions of a simple memory module are implemented, on is implemented using a verilog array to be transformed into a BRAM durin synthesis,
the other one using an explicit BRAM module (SB_RAM40_4K) used to compare its behaviour with the inferred one.

Once the fpga is programmed, it will store the value `3'b010` (green) at address 0x14 and `3'b110` (light blue) at address 0x15.  
It will then read address 0x14 and display it on the LED, wait 24M cycles (2sec at 12MHz) read 0x15 and display it.

A few things I have learned doing this example:
- It isn't possible to do a read and write at the same time to a bram (should have a rd_en and wr_en signals)
- Both read and write to the verilog array should be clocked so that it can be "inferrable", ```data_out <= mem[rd_addr]```, instead of ```assign data_out = mem[rd_addr]```
- In the implicit bram, ```data_out <= mem[rd_addr]```, should be the only assignment to ```data_out```, any other assignment will cause yosys to use logic instead of bram
- BRAMs, at least when inferred and when programming the fgpa with the sram, need a small amount of cycles (~60) to be init, this seems to be a hardware issue.
