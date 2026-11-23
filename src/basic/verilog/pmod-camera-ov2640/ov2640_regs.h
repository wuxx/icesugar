// ============================================================================
//  ov2640_regs.h -- OV2640 寄存器表 (DVP / YUV422 / 640x480)
//
//  来源: Linux 内核 drivers/media/i2c/ov2640.c (ov2640_init_regs /
//        ov2640_size_change_preamble_regs / ov2640_vga_regs /
//        ov2640_format_change_preamble_regs / ov2640_yuyv_regs)
//        交叉验证: esp32-camera sensors/private_include/ov2640_settings.h
//                  (bank1 的 0x3A/0x3B/0x3E/0x43/0x16/0x06/0x07/0x0E 等
//                   模拟/时钟寄存器地址与内核表一致)
//
//  关键差异 (相对 OV5640):
//    1) SCCB 从机地址: 写 0x60 / 读 0x61 (7bit 0x30), 不是 0x78/0x79
//    2) 寄存器地址是 **8 位** (OV5640 是 16 位 0x3xxx)
//    3) 寄存器分 bank: 写 0xFF = 0x00 -> bank0(DSP), 0xFF = 0x01 -> bank1(sensor)
//    4) 芯片 ID: 切到 bank1 后读 0x0A = PID (0x26), 0x0B = VER (0x42)
//
//  尺寸寄存器 (bank0):
//    **重要**: HSIZE8/VSIZE8/HSIZE/VSIZE 是 **DSP 输入图像尺寸**(相机读出来的
//    那一帧有多大), 而 ZMOW/ZMOH/ZMHH 是 **输出尺寸**(缩放之后 DVP 上真正吐出
//    多少像素)。四个独立驱动(Linux 内核 / Zephyr / OpenMV / esp32-camera)
//    对这点的定义完全一致, 不要把两者搞反。
//    HSIZE8(0xC0) = width>>3   VSIZE8(0xC1) = height>>3   SIZEL(0x8C) = 低 3 bit
//    HSIZE(0x51)  = width>>2   VSIZE(0x52)  = height>>2  (图像窗口, 4 像素单位)
//    ZMOW(0x5A)/ZMOH(0x5B)/ZMHH(0x5C) = 输出尺寸 (4 像素单位, 12 bit)
//    CTRLI(0x50) bit[2:0]=H_DIV, bit[5:3]=V_DIV (缩放前的预分频)
//  640x480 的取值 (UXGA 读出 -> DSP 缩放到 VGA, Linux 内核/Zephyr 同款):
//    输入: HSIZE8 = 1600>>3 = 200 = 0xC8   VSIZE8 = 1200>>3 = 150 = 0x96
//          HSIZE  = 1600>>2 = 400 -> 0x90  VSIZE  = 1200>>2 = 300 -> 0x2C
//    输出: ZMOW  = 640>>2 = 160 = 0xA0      ZMOH  = 480>>2 = 120 = 0x78
//          ZMHH  = 0x00                   CTRLI = 0x80
//  改尺寸/改时钟必须用 R_BYPASS(0x05) 括起来: 0x01 旁路 -> 改 -> 0x00 恢复。
//  (OpenMV 和 esp32-camera 都这么做, Linux 内核省略了这一步)
//
//  帧率/时钟:
//    CLKRC(0x11)  bit7=1 用内部 PLL, bit6:0 为分频 (实际分频 = 值+1)
//    FLL(0x46)/FLH(0x47) 帧长
//    R_DVP_SP(0xD3) DVP 输出速度: bit7=1 自动, 否则 PCLK = sysclk/[6:0]
//
//  镜像/翻转: REG04(0x04) bit7 = HFLIP_IMG, bit6 = VFLIP_IMG,
//             bit4 = VREF_EN, bit3 = HREF_EN (HSYNC 变 HREF)
//  输出格式: IMAGE_MODE(0xDA) bit0 = LBYTE_FIRST (0 = 高字节先 = YUYV)
//
//  伪指令: 地址 0xFF00 表示"延时 N 毫秒"(N = 值), 其它地址都是真实寄存器。
// ============================================================================

struct sensor_reg { unsigned char address; unsigned char value; };

// ---------------------------------------------------------------------------
//  软复位: 切到 sensor bank, COM7 写 0x80 触发系统复位, 等 5ms
//  (复位后所有寄存器回到出厂默认值, 下面必须把整张表重新写一遍)
// ---------------------------------------------------------------------------
const struct sensor_reg ov2640_reset_regs[] PROGMEM = {
    { 0xFF, 0x01 },     // BANK_SEL = sensor bank
    { 0x12, 0x80 },     // COM7 = SRST
    { 0xFF00, 0x05 },   // 延时 5 ms (等芯片复位完成)
};

// ---------------------------------------------------------------------------
//  初始化 (Linux ov2640_init_regs)
//    前半段是 sensor bank(模拟/时钟/曝光), 后半段是 DSP bank(色彩/gamma)
// ---------------------------------------------------------------------------
const struct sensor_reg ov2640_init_regs[] PROGMEM = {
    { 0xFF, 0x00 },     // BANK_SEL = DSP bank
    { 0x2C, 0xFF },
    { 0x2E, 0xDF },
    { 0xFF, 0x01 },     // BANK_SEL = sensor bank
    { 0x3C, 0x32 },
    { 0x11, 0x00 },     // CLKRC
    { 0x09, 0x02 },     // COM2   输出驱动 3x
    { 0x04, 0x28 },     // REG04  默认 0x20 | HREF_EN
    { 0x13, 0xE5 },     // COM8   默认 0xC0 | banding | AGC | AEC
    { 0x14, 0x48 },     // COM9   AGC 上限 8x
    { 0x2C, 0x0C },
    { 0x33, 0x78 },
    { 0x3A, 0x33 },
    { 0x3B, 0xFB },
    { 0x3E, 0x00 },
    { 0x43, 0x11 },
    { 0x16, 0x10 },
    { 0x39, 0x02 },
    { 0x35, 0x88 },
    { 0x22, 0x0A },
    { 0x37, 0x40 },
    { 0x23, 0x00 },
    { 0x34, 0xA0 },     // ARCOM2
    { 0x06, 0x02 },
    { 0x06, 0x88 },
    { 0x07, 0xC0 },
    { 0x0D, 0xB7 },     // COM4
    { 0x0E, 0x01 },     // COM5
    { 0x4C, 0x00 },
    { 0x4A, 0x81 },
    { 0x21, 0x99 },
    { 0x24, 0x40 },     // AEW
    { 0x25, 0x38 },     // AEB
    { 0x26, 0x82 },     // VV
    { 0x5C, 0x00 },
    { 0x63, 0x00 },
    { 0x46, 0x22 },     // FLL  帧长低字节
    { 0x0C, 0x3A },     // COM3 自动 50/60Hz 抗条纹
    { 0x5D, 0x55 },
    { 0x5E, 0x7D },
    { 0x5F, 0x7D },
    { 0x60, 0x55 },
    { 0x61, 0x70 },     // HISTO_LOW
    { 0x62, 0x80 },     // HISTO_HIGH
    { 0x7C, 0x05 },
    { 0x20, 0x80 },
    { 0x28, 0x30 },
    { 0x6C, 0x00 },
    { 0x6D, 0x80 },
    { 0x6E, 0x00 },
    { 0x70, 0x02 },
    { 0x71, 0x94 },
    { 0x73, 0xC1 },
    { 0x3D, 0x34 },
    { 0x12, 0x04 },     // COM7 = UXGA 模式 + 打开 ZOOM
    //  **UXGA 读出窗口**: esp32-camera 的 ov2640_settings_to_uxga 和 Zephyr 的
    //  uxga_regs 都显式写这 6 个寄存器, Linux 内核没写(靠软复位后的默认值)。
    //  不写的话窗口落在空白区 -> 画面全黑 + 垂直消隐多出上千行。
    { 0x03, 0x0F },     // COM1  = UXGA 窗口低位
    { 0x32, 0x36 },     // REG32 = UXGA
    { 0x17, 0x11 },     // HSTART
    { 0x18, 0x75 },     // HSTOP
    { 0x19, 0x01 },     // VSTART
    { 0x1A, 0x97 },     // VSTOP
    { 0x42, 0x83 },     // UXGA 模式下的 0x42 (bank1, 和 DSP bank 的 0x42 不是一回事)
    { 0x5A, 0x57 },     // REG5A  50/60Hz 最大 AEC 步进
    { 0x4E, 0x00 },     // COM25
    { 0x4F, 0xBB },     // BD50
    { 0x50, 0x9C },     // BD60
    { 0xFF, 0x00 },     // BANK_SEL = DSP bank
    { 0xE5, 0x7F },
    { 0xF9, 0xC0 },     // MC_BIST 复位 MCU + 选 boot ROM
    { 0x41, 0x24 },
    { 0xE0, 0x14 },     // RESET = JPEG | DVP
    { 0x76, 0xFF },
    { 0x33, 0xA0 },
    { 0x42, 0x20 },
    { 0x43, 0x18 },
    { 0x4C, 0x00 },
    { 0x87, 0xD0 },     // CTRL3 = BPC | WPC | 0x10
    { 0x88, 0x3F },
    { 0xD7, 0x03 },
    { 0xD9, 0x10 },
    { 0xD3, 0x82 },     // R_DVP_SP = 自动模式 | 0x02
    { 0xC8, 0x08 },
    { 0xC9, 0x80 },
    { 0x7C, 0x00 },     // BPADDR
    { 0x7D, 0x00 },     // BPDATA
    { 0x7C, 0x03 },     // BPADDR
    { 0x7D, 0x48 },     // BPDATA
    { 0x7D, 0x48 },     // BPDATA
    { 0x7C, 0x08 },     // BPADDR
    { 0x7D, 0x20 },     // BPDATA
    { 0x7D, 0x10 },     // BPDATA
    { 0x7D, 0x0E },     // BPDATA
    { 0x90, 0x00 },
    { 0x91, 0x0E },
    { 0x91, 0x1A },
    { 0x91, 0x31 },
    { 0x91, 0x5A },
    { 0x91, 0x69 },
    { 0x91, 0x75 },
    { 0x91, 0x7E },
    { 0x91, 0x88 },
    { 0x91, 0x8F },
    { 0x91, 0x96 },
    { 0x91, 0xA3 },
    { 0x91, 0xAF },
    { 0x91, 0xC4 },
    { 0x91, 0xD7 },
    { 0x91, 0xE8 },
    { 0x91, 0x20 },
    { 0x92, 0x00 },
    { 0x93, 0x06 },
    { 0x93, 0xE3 },
    { 0x93, 0x03 },
    { 0x93, 0x03 },
    { 0x93, 0x00 },
    { 0x93, 0x02 },
    { 0x93, 0x00 },
    { 0x93, 0x00 },
    { 0x93, 0x00 },
    { 0x93, 0x00 },
    { 0x93, 0x00 },
    { 0x93, 0x00 },
    { 0x93, 0x00 },
    { 0x96, 0x00 },
    { 0x97, 0x08 },
    { 0x97, 0x19 },
    { 0x97, 0x02 },
    { 0x97, 0x0C },
    { 0x97, 0x24 },
    { 0x97, 0x30 },
    { 0x97, 0x28 },
    { 0x97, 0x26 },
    { 0x97, 0x02 },
    { 0x97, 0x98 },
    { 0x97, 0x80 },
    { 0x97, 0x00 },
    { 0x97, 0x00 },
    { 0xA4, 0x00 },
    { 0xA8, 0x00 },
    { 0xC5, 0x11 },
    { 0xC6, 0x51 },
    { 0xBF, 0x80 },
    { 0xC7, 0x10 },     // 简单 AWB
    { 0xB6, 0x66 },
    { 0xB8, 0xA5 },
    { 0xB7, 0x64 },
    { 0xB9, 0x7C },
    { 0xB3, 0xAF },
    { 0xB4, 0x97 },
    { 0xB5, 0xFF },
    { 0xB0, 0xC5 },
    { 0xB1, 0x94 },
    { 0xB2, 0x0F },
    { 0xC4, 0x5C },
    { 0xA6, 0x00 },
    { 0xA7, 0x20 },
    { 0xA7, 0xD8 },
    { 0xA7, 0x1B },
    { 0xA7, 0x31 },
    { 0xA7, 0x00 },
    { 0xA7, 0x18 },
    { 0xA7, 0x20 },
    { 0xA7, 0xD8 },
    { 0xA7, 0x19 },
    { 0xA7, 0x31 },
    { 0xA7, 0x00 },
    { 0xA7, 0x18 },
    { 0xA7, 0x20 },
    { 0xA7, 0xD8 },
    { 0xA7, 0x19 },
    { 0xA7, 0x31 },
    { 0xA7, 0x00 },
    { 0xA7, 0x18 },
    { 0x7F, 0x00 },
    { 0xE5, 0x1F },
    { 0xE1, 0x67 },
    { 0xDD, 0x7F },
    { 0xC2, 0x0E },     // CTRL0 = YUV422 | YUV_EN | RGB_EN (VFIRST 清零 = YUYV)
};

// ---------------------------------------------------------------------------
//  窗口前导 (Linux ov2640_size_change_preamble_regs)
//    先把 DSP 配成 UXGA(1600x1200) 输入窗口, 后面再用 ZOOM 缩到目标尺寸
// ---------------------------------------------------------------------------
const struct sensor_reg ov2640_size_preamble_regs[] PROGMEM = {
    { 0xFF, 0x00 },     // BANK_SEL = DSP bank
    { 0x05, 0x01 },     // R_BYPASS = 旁路 DSP (改尺寸/时钟前先旁路, 写完再恢复)
    { 0xE0, 0x04 },     // RESET = DVP
    { 0x8C, 0x00 },     // SIZEL
    { 0xC0, 0xC8 },     // HSIZE8 = 1600>>3 = 200
    { 0xC1, 0x96 },     // VSIZE8 = 1200>>3 = 150
    { 0x86, 0x3D },     // CTRL2 = DCW | SDE | UV_AVG | CMX | UV_ADJ
    { 0x51, 0x90 },     // HSIZE = 1600>>2 = 400 (低 8 位)
    { 0x52, 0x2C },     // VSIZE = 1200>>2 = 300 (低 8 位)
    { 0x53, 0x00 },     // XOFFL
    { 0x54, 0x00 },     // YOFFL
    { 0x55, 0x88 },     // VHYX  窗口高位补齐
    { 0x57, 0x00 },     // TEST
};

// ---------------------------------------------------------------------------
//  VGA 640x480 (Linux ov2640_vga_regs = PER_SIZE_REG_SEQ(640,480,0,0,2))
//    CTRLI 的 h_div/v_div 都取 0 = 不做预分频, 由 ZOOM 块一次缩到位
// ---------------------------------------------------------------------------
const struct sensor_reg ov2640_vga_regs[] PROGMEM = {
    { 0x50, 0x80 },     // CTRLI = LP_DP (h_div=0, v_div=0)
    { 0x5A, 0xA0 },     // ZMOW = 640>>2 = 160  (输出宽度)
    { 0x5B, 0x78 },     // ZMOH = 480>>2 = 120  (输出高度)
    { 0x5C, 0x00 },     // ZMHH  高位补齐
    { 0xD3, 0x02 },     // R_DVP_SP = 2 (PCLK = sysclk/2)
    { 0xE0, 0x00 },     // RESET = 0
    { 0x05, 0x00 },     // R_BYPASS = 恢复走 DSP
};

// ---------------------------------------------------------------------------
//  输出格式前导 + YUYV (Linux ov2640_format_change_preamble_regs /
//  ov2640_yuyv_regs)
//    IMAGE_MODE bit0 = 0 = 高字节先 = YUYV (和 OV5640 工程一致)
// ---------------------------------------------------------------------------
const struct sensor_reg ov2640_format_preamble_regs[] PROGMEM = {
    { 0xFF, 0x00 },     // BANK_SEL = DSP bank
    { 0x05, 0x00 },     // R_BYPASS = 走内部 DSP
};

const struct sensor_reg ov2640_yuyv_regs[] PROGMEM = {
    { 0xDA, 0x00 },     // IMAGE_MODE = YUV422 (bit0=0 -> YUYV)
    { 0xD7, 0x03 },
    { 0x33, 0xA0 },
    { 0xE5, 0x1F },
    { 0xE1, 0x67 },
    { 0xE0, 0x00 },     // RESET = 0
    { 0x05, 0x00 },     // R_BYPASS = 走内部 DSP
};

// ---------------------------------------------------------------------------
//  收尾: 再确认一次 CTRL0 的 VFIRST 位是 0 (YUYV), 然后等 AWB 收敛
// ---------------------------------------------------------------------------
const struct sensor_reg ov2640_end_regs[] PROGMEM = {
    // ---- AE / AWB block written LAST (after the sensor reset sequence) ----
    { 0xFF, 0x01 },     // BANK_SEL = sensor bank
    { 0x13, 0xE5 },     // COM8  = 0xC0 | BNDF_EN | AGC_EN | AEC_EN
    { 0x14, 0x48 },     // COM9  = AGC ceiling 8x
    { 0x24, 0xFF },     // AEW   = stable operating region, upper limit
    { 0x25, 0x00 },     // AEB   = stable operating region, lower limit
    { 0x26, 0x82 },     // VV    = fast mode operating region
    { 0x5C, 0x00 },
    { 0x63, 0x00 },
    { 0x5D, 0x55 },     // 16-zone average weight
    { 0x5E, 0x7D },
    { 0x5F, 0x7D },
    { 0x60, 0x55 },
    { 0x61, 0x70 },     // HISTO_LOW
    { 0x62, 0x80 },     // HISTO_HIGH
    { 0x45, 0x00 },     // REG45 = AEC[15:10] = 0 (no stale high bits)
    { 0x04, 0x28 },     // REG04 = 0x20 | HREF_EN | AEC[1:0] = 0
    { 0xFF, 0x00 },     // BANK_SEL = DSP bank
    { 0xC2, 0x0E },     // CTRL0 = YUV422 | YUV_EN | RGB_EN
    { 0xFF00, 0xFF },   // delay 255 ms: let the AE/AWB engine converge
};
