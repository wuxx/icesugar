iCESugar
-----------
[中文](./README.md) [English](./README_en.md)

* [iCESugar介绍](#iCESugar介绍) 
* [芯片规格](#芯片规格)
* [硬件说明](#硬件说明)
	* [iCE40UP5K](iCE40UP5K)
	* [iCELink](iCELink)
* [资源下载](#虚拟机镜像)
* [开发环境搭建](#开发环境搭建)
* [视频教程](#视频教程)
* [FPGA教程](#fpga教程)
* [产品链接](#产品链接)
* [参考](#参考)


# iCESugar介绍 
iCESugar 是MuseLab基于Lattice iCE40UP5k设计的开源FPGA开发板，开发板小巧精致，资源丰富，板载RGB LED，Switch，TYPE-C-USB, Micro-USB，大部分IO以标准PMOD接口引出，可与标准PMOD外设进行对接，方便日常的开发使用。  
板载的调试器iCELink经过精心设计，支持拖拽烧录，用户只需将综合出的FPGA bitstream文件拖拽至虚拟U盘中，即可实现烧录。iCELink亦支持虚拟串口以和FPGA进行通信，同时引出JTAG接口，方便用户对FPGA上实现的SoC进行调试。  
Lattice的iCE40系列芯片在国外的开源创客社区中拥有大量拥趸，其所有的开发软件环境亦均为开源。一般来说，假若您使用Xilinx或者Altera系列的开发板，您需要安装复杂臃肿的IDE开发环境(而且一般为盗版，使用存在一定法律风险), 在未开始开发前，首先还先需要学会如何操作其复杂的IDE。 iCE40则使用完全开源的工具链进行开发，包括FPGA综合（yosys），布线（arachne-pnr & nextpnr）, 打包烧录（icestorm），编译（gcc），只需在Linux下输入数条命令，即可将整套工具链轻松安装，随后即可开始您的FPGA之旅，而且这一切都是开源的，您可仔细研究整个过程中任何一个细节的实现，非常适合个人研究学习，对于有丰富经验的开发者，亦可用来作为快速的逻辑验证平台。典型的基于iCE40系列的开源开发板有iCEBreaker、UPduino、BlackIce、iCEstick、TinyFPGA 等，社区中拥有丰富的demo可用于验证测试，或者作为自己开发学习的参考。  
iCESugar是iCESugar系列的第一款开发板，[iCESugar-nano](https://github.com/wuxx/icesugar-nano)(基于Lattice iCE40LP1k) 和 [iCESugar-pro](https://github.com/wuxx/icesugar-pro)(基于Lattice ECP5)已经发布，以匹配不同的功能性能的需求。  
![icesugar_1](https://github.com/wuxx/icesugar/blob/master/doc/iCESugar_1.jpg)
# 芯片规格 
iCE40UP5K-SG48  
1. 5280 Logic Cells (4-LUT + Carry + FF)  
2. 128 KBit Dual-Port Block RAM  
3. 1 MBit (128 KB) Single-Port RAM  
4. PLL, Two SPI and two I2C hard IPs  
5. Two internal oscillators (10 kHz and 48 MHz)  
6. 8 DSPs (16x16 multiply + 32 bit accumulate)  
7. 3x 24mA drive and 3x hard PWM IP  

# 硬件说明
### iCE40UP5K
1. SPI Flash使用W25Q64（8MB）
2. 板载拨码开关和RGB LED可用于测试
3. 所有IO以标准PMOD接口引出，可用于开发调试

### iCELink
iCESugar实现了一个板载的调试器iCELink，您可仅用一根USB线便可实现FPGA的烧录和调试，具体功能说明如下：  
1. 拖拽烧录，将综合布线打包生成的bin文件（一般称之为配置或者逻辑）拖拽到iCELink的虚拟U盘中即可实现烧录  
2. 虚拟串口，可用于和FPGA直接数据的发送接收  
3. 支持JTAG, 可对FPGA上实现的SoC进行调试  
4. 通过MCO输出12Mhz时钟，作为FPGA的外部时钟  


# 虚拟机镜像
链接：https://pan.baidu.com/s/1qVSdwM7DnFbaS0xdqsPNrA  
提取码：6gn3  
`user: ubuntu`  
`passwd: ubuntu`  
所有环境包括综合(yosys)，布线(nextpnr)，打包(icesorm)，编译器(gcc) 已经预制好，启动即可开始使用。

# 开发环境搭建
推荐使用虚拟机镜像进行开发测试，简单方便。  
FPGA工具链安装请参考[icestorm](http://www.clifford.at/icestorm/)  
gcc工具链安装请参考 [riscv-gnu-toolchain](https://pingu98.wordpress.com/2019/04/08/how-to-build-your-own-cpu-from-scratch-inside-an-fpga/)  
也可直接下载xPack或者SiFive提供的预编译工具链
+ https://xpack.github.io/riscv-none-embed-gcc/install/
+ https://www.sifive.com/software  

`icesprog`是为iCESugar开发的命令行烧写工具，仓库中已经提供，依赖libusb和hidapi，若自行搭建环境需要安装依赖的库  
`$sudo apt-get install libhidapi-dev`  
`$sudo apt-get install libusb-1.0-0-dev`  
# 视频教程
- [开源FPGA开发板-硬件介绍](https://www.bilibili.com/video/av85029350?from=search&seid=17750023774521991972)  
- [开源FPGA开发板-开发环境搭建](https://www.bilibili.com/video/av85146557?from=search&seid=17750023774521991972)   
- [开源FPGA开发板-RISC-V SoC烧录演示](https://www.bilibili.com/video/av90891200?from=search&seid=17750023774521991972)   
# FPGA教程
强烈推荐学习此教程，[open-fpga-verilog-tutorial](https://github.com/Obijuan/open-fpga-verilog-tutorial/wiki/Home_EN) `src/basic/open-fpga-verilog-tutorial`目录中有对应的例程

# 产品链接
[iCESugar FPGA Board](https://item.taobao.com/item.htm?spm=a1z10.1-c-s.w4004-21349689053.18.305e20f8cSEvqA&id=614093598737)

# 参考
### RTL toolchain
http://www.clifford.at/icestorm/
### Firmware toolchain
https://xpack.github.io/riscv-none-embed-gcc/install/
https://www.sifive.com/software
### Examples
https://github.com/damdoy/ice40_ultraplus_examples  
https://github.com/icebreaker-fpga/icebreaker-examples
### SpinalHDL 教程
https://spinalhdl.github.io/SpinalDoc-RTD/SpinalHDL/Getting%20Started/index.html
### 开源FPGA单板iCESugar介绍
https://www.muselab-tech.com/wan-quan-shi-yong-kai-yuan-gong-ju-lian-de-fpgadan-ban/
