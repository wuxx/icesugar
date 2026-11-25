# iCESugar + PMOD-LCD-0.96 (ST7735S 160x80) Colour Bar Test

A pure-Verilog ST7735S driver. It initialises the panel and paints 8 vertical colour bars
right after power-up, **with no CPU involved**.

## Wiring / Pin Map

Everything goes to the iCESugar **PMOD3 (J3)** connector (package pin numbers taken from
`src/common/io.pcf`):

| Signal | Package pin | PMOD3 position | Notes |
|--------|--------------|----------------|-------|
| LCD_SPI_CS   | 34 | 1 | Chip select, active low |
| LCD_SPI_MOSI | 31 | 2 | Data in (DIN) |
| LCD_DC       | 27 | 3 | 0 = command, 1 = data |
| LCD_SPI_SCK  | 25 | 4 | Serial clock |
| LCD_RST      | 23 | 9 | Reset, active low |

## Files

| File | Description |
|------|-------------|
| `top.v` | iCESugar top level: 12MHz → PLL 24MHz, pin constraints |
| `st7735.v` | ST7735 driver: SPI transmit engine + init ROM + pixel engine |
| `gen_init_hex.py` | Generates the init ROM (mirrors `tft_init()` of the iceZ0mb1e reference firmware) |
| `st7735_init.hex` | Generated ROM (produced automatically by make) |
| `top.pcf` | Pin constraints |
| `tb_st7735.v` / `chk_lcd_stream.py` | Offline simulation: capture the SPI byte stream and check it byte by byte |

## Build / Program

```bash
cd /home/ubuntu/oss/icesugar/src/basic/verilog/pmod-lcd-0.96
make                 # yosys -> nextpnr-ice40 -> icepack, produces top.bin
make sim             # offline self-check (no hardware needed): init sequence + bar data
make prog_flash      # drag & drop programming (iCELink virtual USB drive)
make prog_icesprog   # command line programming (the board must be attached to this machine)
```

About 0.4 s after power-up the panel shows **white / yellow / cyan / green / magenta / red /
blue / black** as 8 vertical bars.

## Implementation Notes

- **SPI mode**: SCLK idles high. For every bit the driver pulls SCLK low and updates MOSI
  at the same time, then pulls SCLK high again — the ST7735 samples on the rising edge.
  This matches the `iceZ0mb1e` reference firmware (`spi_config(3, 24)`).
  SCLK = 24MHz / (2×4) = **3MHz**.
- **Initialisation**: the ROM holds three kinds of entries — command / data / delay — and the
  sequence maps one-to-one onto the reference firmware
  (SLPOUT + 120ms → B1..C5 → E0/E1 gamma → FC → 3A → 36 → 21 → 29 → window → RAMWR).
- **Coordinate offsets**: landscape 160×80, in GRAM the column is x+1 (1..160) and the row is
  y+26 (26..105), identical to `tft_set_addr_window()` in the reference firmware.
- **Colour bars**: one bar every 20 pixels across x (8 bars in total), written row by row
  from left to right, high byte first.

## Gotchas

- `lcd_cs_n`, `lcd_dc`, `lcd_sck` and `lcd_mosi` are driven by the SPI engine **only**.
  If a second always-block also assigns them, yosys reports
  `multiple conflicting drivers` and silently resolves the signal to a constant — with CS
  stuck high the display stays black and nothing in the build log points at the real cause.
  The Makefile therefore greps the yosys log and fails the build on such a conflict.
- The ROM file is padded to 128 entries with `END` markers; otherwise `$readmemh` complains
  about "Not enough words in the file for the requested range".

## References

- iceZ0mb1e reference firmware (same display, known to work):
  <https://github.com/wuxx/iceZ0mb1e/blob/master/firmware/main/main_st7735.c>
- ST7735S datasheet: `doc/st7735s/ST7735S-datasheet.pdf`
