iCESugar
-----------
[中文](./README.md) [English](./README_en.md)
* [iCESugar](#iCESugar) 
* [Hardware](#hardware)
	* [iCE40UP5K](ice40up5k)
	* [iCELink](icelink)
* [virtual-machine-image](#virtual-machine-image)
* [How-to-setup](#how-to-setup-env)
* [How-to-buy](#how-to-buy)
* [Reference](#reference)

# iCESugar
iCESugar is a FPGA board made by MuseLab, which is base on Lattice iCE40UP5k, on board peripherals include RGB LED，Switch，TYPE-C-USB, Micro-USB，most IO out with standard PMOD interface   
the on board debugger iCELink (base on ARM Mbed DAPLink) support drag-and-drop program, you can just drag the FPGA bitstream into the virtual disk to program, iCELink also support USB CDC serial port and JTAG   
iCESugar is the first board of iCESugar series FPGA Board, [iCESugar-nano](https://github.com/wuxx/icesugar-nano)(base on Lattice iCE40LP1k) and [iCESugar-pro](https://github.com/wuxx/icesugar-pro)(base on Lattice ECP5) are already released for difference needs.
![icesugar_1](https://github.com/wuxx/icesugar/blob/master/doc/iCESugar_1.jpg)

# Hardware
### iCE40UP5K
1. 5280 Logic Cells (4-LUT + Carry + FF)  
2. 128 KBit Dual-Port Block RAM  
3. 1 MBit (128 KB) Single-Port RAM  
4. PLL, Two SPI and two I2C hard IPs  
5. Two internal oscillators (10 kHz and 48 MHz)  
6. 8 DSPs (16x16 multiply + 32 bit accumulate)  
7. 3x 24mA drive and 3x hard PWM IP  
8. SPI Flash use W25Q64 (8MB)
9. on board switch and RGB LED
10. all IO out with standard PMOD Interface

### iCELink
iCESugar has a on board debugger named iCELink (base on STM32F1)，you can only use one USB wire to program the FPGA and debug, here is detail:   
1. drag-and-drop program, just drop the bitstream into the virtual USB DISK iCELink, then wait a few second, the iCELink firmware will do the total program work
2. USB CDC serial port, it can use to communicate with FPGA
3. support JTAG, you can use it to debug the SoC run on FPGA
4. the MCO can provide 12Mhz clock for FPGA as extern clock.

# virtual-machine-image
link：https://pan.baidu.com/s/1qVSdwM7DnFbaS0xdqsPNrA  
verify code：6gn3  
`user: ubuntu`  
`passwd: ubuntu`  
or
https://mega.nz/file/uvJTWKrK#1bBgBkJPZrszwHQSTHHL-RLjxGIru0Qv0qUgmULZZVs

the env include yosys, nextpnr, icestorm, gcc, sbt.

# How-to-setup-env
recommand use the virtual machine, it simple and convenient  
FPGA toolchain reference [icestorm](http://www.clifford.at/icestorm/)  
gcc toolchain reference [riscv-gnu-toolchain](https://pingu98.wordpress.com/2019/04/08/how-to-build-your-own-cpu-from-scratch-inside-an-fpga/)  
Alternatively, you can download the pre-built toolchain provided by xPack or SiFive
+ https://xpack.github.io/riscv-none-embed-gcc/install/
+ https://www.sifive.com/software
`icesprog` is command tool for iCESugar program，it depend libusb and hidapi  
`$sudo apt-get install libhidapi-dev`  
`$sudo apt-get install libusb-1.0-0-dev`  

# How-to-buy
you can buy iCESugar and PMOD boards from our offcial aliexpress shop [Muse Lab Factory Store](https://muselab-tech.aliexpress.com/store/5940159?spm=a2g0o.detail.1000061.1.7cc733429fQjmK)

# Reference
### RTL toolchain
http://www.clifford.at/icestorm/
### Firmware toolchain
https://xpack.github.io/riscv-none-embed-gcc/install/
https://www.sifive.com/software
### Examples
https://github.com/damdoy/ice40_ultraplus_examples  
https://github.com/icebreaker-fpga/icebreaker-examples
### SpinalHDL
https://spinalhdl.github.io/SpinalDoc-RTD/SpinalHDL/Getting%20Started/index.html
### iCESugar introduce
https://www.muselab-tech.com/wan-quan-shi-yong-kai-yuan-gong-ju-lian-de-fpgadan-ban/
