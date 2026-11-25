# iCESugar + PMOD-LCD-0.96 (ST7735S 160x80) 色条显示

纯 Verilog 实现的 ST7735S 驱动，上电自动初始化并刷 8 条竖直色条，**不需要 CPU 参与**。

## 接线 / 引脚

全部接在 iCESugar 的 **PMOD3 (J3)** 上（封装脚号见 `src/common/io.pcf`）：

| 信号 | 封装脚 | PMOD3 位置 | 说明 |
|------|--------|-----------|------|
| LCD_SPI_CS   | 34 | 1 | 片选，低有效 |
| LCD_SPI_MOSI | 31 | 2 | 数据 (DIN) |
| LCD_DC       | 27 | 3 | 0=命令，1=数据 |
| LCD_SPI_SCK  | 25 | 4 | 时钟 |
| LCD_RST      | 23 | 9 | 复位，低有效 |

## 文件

| 文件 | 说明 |
|------|------|
| `top.v` | iCESugar 顶层：12MHz → PLL 24MHz，接线约束 |
| `st7735.v` | ST7735 驱动：SPI 发送引擎 + 初始化 ROM + 像素引擎 |
| `gen_init_hex.py` | 生成初始化 ROM（照抄 iceZ0mb1e 参考固件的 `tft_init()`） |
| `st7735_init.hex` | 生成的 ROM（由 make 自动生成） |
| `top.pcf` | 引脚约束 |
| `tb_st7735.v` / `chk_lcd_stream.py` | 离线仿真：抓 SPI 字节流并逐字节核对 |

## 编译 / 烧录

```bash
cd /home/ubuntu/oss/icesugar/src/basic/verilog/pmod-lcd-0.96
make                 # yosys -> nextpnr-ice40 -> icepack, 产物 top.bin
make sim             # 离线仿真自检 (不需要硬件): 核对初始化序列 + 色条数据
make prog_flash      # 拖拽烧录 (iCELink 虚拟 U 盘)
make prog_icesprog   # 命令行烧录 (板子要接在这台机器上)
```

板上电后约 0.4 秒显示出 **白 黄 青 绿 品红 红 蓝 黑** 8 条竖直色条。

## 实现要点

- **SPI 模式**：SCLK 空闲为高，每个 bit 先拉低 SCLK 并更新 MOSI、再拉高 SCLK，
  ST7735 在上升沿采样（和 `iceZ0mb1e` 参考固件的 `spi_config(3, 24)` 一致）。
  SCLK = 24MHz / (2×4) = **3MHz**。
- **初始化**：ROM 里存 `命令/数据/延时` 三类指令，序列与参考固件逐条对应
  （SLPOUT + 120ms → B1..C5 → E0/E1 gamma → FC → 3A → 36 → 21 → 29 → 窗口 → RAMWR）。
- **坐标偏移**：横屏 160×80，GRAM 里列 = x+1（1..160）、行 = y+26（26..105），
  和参考固件的 `tft_set_addr_window()` 一致。
- **色条**：按 x 每 20 像素换一条（8 条），逐行从左到右写，高字节在前。

## 参考

- iceZ0mb1e 参考固件（同一块屏，验证可用）：
  <https://github.com/wuxx/iceZ0mb1e/blob/master/firmware/main/main_st7735.c>
- ST7735S 数据手册：`doc/st7735s/ST7735S-datasheet.pdf`
