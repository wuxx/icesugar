# Flash reading from the iCE40 UltraPlus

The goal of this example is to read, from the ice40 ultraplus some data in the flash using the SPI as master.

The flash_master folder contains the script and image to write in the flash at 1MB or 0x100000 offset

The program `flash_master/prog.hex` which only contains the bytes `00, 01, 02, 03, 04` in binary format should be programmed to the fpga using the `flash_master/flash_program.sh`, which will write the .hex in the flash of the fpga with a 1MB offset.  
After that, the fpga can be programmed with `make prog`, the fpga will then wait 2 sec before accessing the flash, reading the byte at 0x100002 which should be 02, and display it on the LED (green).

Don't forget to put the breakout board in flash mode using the jumpers on J6!

flash chip: N25Q032A13ESC40F, datasheet can be found here: https://www.micron.com/-/media/client/global/documents/products/data-sheet/nor-flash/serial-nor/n25q/n25q_32mb_3v_65nm.pdf

minimal erase cycle: 100k

Needs ~833Kb for the fpga bitstream (this is why `prog.hex` is written at 1MB)

The flash chip has 32Mb or 4MB
