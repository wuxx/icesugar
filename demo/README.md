[中文](./README.md) [English](./README_en.md)
# demo
此目录下为已经预编译好的FPGA bitstream，可进行拖拽烧录测试  
源码位于`src/basic`和`src/advanced`中

## basic
`leds.bin`  
  RGB LED测试  
`bram.bin`  
内部BRAM测试  
`pll.bin`  
内部PLL测试  
`pwm.bin`  
LED渐变  
`spram.bin`  
内部BRAM测试  
`switch.bin`  
板载的拨码开关和RGB LED 组合测试  
`uart_echo.bin`  
uart 回环测试，返回输入的字符  
`uart_tx.bin`  
uart 发送测试
## advanced
`picorv32.bin`   
risc-v SoC实现，打开串口，波特率调至115200进行观测  
`up5k_6502.bin`  
6502 core实现，打开串口，波特率调至9600进行观测  
`vga_pong.bin`  
vga pong 游戏，配合PMOD-VGA可在屏幕显示pong游戏  
`vga_rotate.bin`  
vga 旋转测试  
`icicle.bin`  
risc-v SoC实现，打开串口，波特率调至9600进行观测  
`litex-image-gateware+bios+none.bin`  
litex SoC框架，实现的是lm32 core，打开串口，波特率调至115200进行观测  
`litex-image-gateware+bios+micropython.bin`  
litex SoC框架，实现的是lm32 core + micropython，打开串口，波特率调至115200进行观测  
`nes_smb.bin`  
nes超级玛丽游戏，配合PMOD-VGA显示  
