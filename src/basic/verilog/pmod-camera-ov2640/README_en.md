# OV2640 DVP Bring-Up (iCESugar + iCE40UP5K + PMOD-CAMERA)

> Chinese version: [`README.md`](README.md) — the two files map 1:1 so that friends
> abroad can read the same content.

This project drives the **OV2640** module on the PMOD-CAMERA from an iCESugar
(iCE40UP5K-SG48I). After power-up the FPGA automatically runs
"SCCB configuration -> read back the key registers -> measure the DVP stream for
one second -> decide the byte order" and finally prints a self-test report over
UART at 9600 8N1.

There are only two goals: **prove that SCCB communication works** and
**prove that the DVP interface really streams pixels**.

Status:

- **Self-test verified on hardware** (`verdict = 15` = 0b01111, all five checks
  green — see the report in section 5).
- **Photo pipeline works end to end**: 60 segments / 538 packets / **0 CRC
  errors**, 640x480 YUYV. Geometry and byte order are cross-checked with the
  **colour-bar test pattern** (section 5.2).
- **A real picture finally comes out**: daytime re-test on 2026-11-23, 640x480
  real scene (a person, archive-box shelves and window blinds), Y mean
  **101.4**, std 71.8, U/V means 125/127 (no colour cast) — properly exposed.
- **Auto exposure works too**: the OV2640 on-chip AE engine requires the
  **whole AE block (COM8/COM9/AEW/AEB/VV/16-zone weights/histogram) to be
  written at the very end of the register table** — written at the top it is
  wiped by the reset sequence. Four controlled experiments in section 5.5.

> This is the OV2640 version of [`pmod-camera-ov5640`](../pmod-camera-ov5640/).
> The structure, the protocol and most of the pitfalls carry over;
> **the OV2640-specific ones are collected in section 7**.

---

## 1. Hardware connections

The pin map is **identical** to the OV5640 project (only the camera module on the
PMOD-CAMERA board was swapped):

| FPGA pin | Signal | Direction | Notes |
|---|---|---|---|
| 35 | clk12 | in | on-board 12MHz (iCELink MCO through ICE_CLK) |
| 43 | XMCLK | out | 24MHz (PLL 12->24, IOB DDR, 50% duty) |
| 44 | PCLK | in | DVP pixel clock (wired to a global clock input) |
| 38 | VSYNC | in | DVP vertical sync |
| 42 | HREF | in | DVP horizontal sync |
| 37 | SCL | bidir | SCCB clock (open drain + internal pull-up) |
| 36 | SDA | bidir | SCCB data (open drain + internal pull-up) |
| 23 / 25 / 26 / 27 / 28 / 31 / 32 / 34 | D0..D7 | in | DVP data Y2..Y9 (PMOD3) |
| 6 | TX | out | UART output (iCELink CDC, 9600 8N1) |
| 40 / 41 / 39 | LED_R/G/B | out | green = all pass, red = failure, blue = busy |

The two SCCB lines use an open-drain physical layer: `SB_IO PIN_TYPE=6'b1010_01`
+ `D_OUT_0=0` + `OUTPUT_ENABLE=*_low` + `PULLUP=1`, so the FPGA pulls low and the
slave / pull-up releases.

The pins were cross-checked against `src/common/io.pcf` and
`schematic/pmod-camera-v1.0.pdf`.

**XMCLK is the 24MHz the FPGA generates** (12MHz in, PLL doubles it to 24MHz, an
IOB DDR output produces a 50% duty square wave). The OV2640 wants 24MHz — do not
change it to 12MHz.

---

## 2. Key differences between OV2640 and OV5640

**These differ; copying the OV5640 code verbatim will not work.**

| Item | OV5640 | **OV2640** |
|---|---|---|
| SCCB slave address (write) | 0x78 (7-bit 0x3C) | **0x60 (7-bit 0x30)** |
| SCCB slave address (read) | 0x79 | **0x61** |
| Register address width | 16 bits (0x3xxx) | **8 bits (0x00..0xFF)** |
| Register banks | none | **yes**: write `0xFF`=0x00 for the DSP bank, 0xFF=0x01 for the sensor bank |
| Chip ID | 0x300A / 0x300B = 0x56 / 0x40 | **after switching to bank1, 0x0A / 0x0B = 0x26 / 0x42** |
| Output size registers | 0x3808..0x380B are the output width/height | **0xC0/0xC1 are the *input* size, 0x5A/0x5B are the *output* size** |

The last one is the easiest trap to fall into, so it gets its own section.

### 2.1 Size registers: input vs output

The OV2640 DSP has two size stages:

- **Input (how big the frame the sensor reads out really is)**:
  `HSIZE8(0xC0) = width>>3`, `VSIZE8(0xC1) = height>>3`,
  `HSIZE(0x51) = width>>2`, `VSIZE(0x52) = height>>2` (4-pixel units)
- **Output (how many pixels actually leave on DVP after scaling)**:
  `ZMOW(0x5A)` / `ZMOH(0x5B)` / `ZMHH(0x5C)` (4-pixel units, 12 bits),
  plus the H/V pre-divider in `CTRLI(0x50)`

Four independent drivers — the Linux kernel, Zephyr, OpenMV and esp32-camera —
**agree exactly** on this. This project follows the kernel route
(UXGA read-out -> DSP downscale to VGA):

```
input:  HSIZE8 = 1600>>3 = 200 = 0xC8    VSIZE8 = 1200>>3 = 150 = 0x96
        HSIZE  = 1600>>2 = 400 -> 0x90    VSIZE  = 1200>>2 = 300 -> 0x2C
output: ZMOW   =  640>>2 = 160 = 0xA0     ZMOH   =  480>>2 = 120 = 0x78
        ZMHH   = 0x00                      CTRLI  = 0x80 (h_div=0, v_div=0)
```

**What happens if you get it wrong**: writing `HSIZE8/VSIZE8` as the 640/480
values (0x50/0x3C) makes the chip read a window that does not exist, and the
picture is garbage — or the chip does not stream at all.

### 2.2 Bracket size/clock changes with R_BYPASS

```
write 0x05 = 0x01   (R_BYPASS: bypass the DSP, sensor straight through)
  ...change HSIZE8/VSIZE8/HSIZE/VSIZE/ZMOW/ZMOH/R_DVP_SP...
write 0x05 = 0x00   (R_BYPASS: use the internal DSP again)
```

OpenMV and esp32-camera both do this; the Linux kernel skips it (it uses
`RESET_DVP` instead). This project **does both** (`RESET_DVP` plus the
`R_BYPASS` bracket) and it worked on the first try.

### 2.3 Byte order

`IMAGE_MODE(0xDA) = 0x00` -> the bus is **YUYV** (high byte first, the first
byte on the wire is Y). `bit0 = 1` gives UYVY. `CTRL0(0xC2)` bit4 swaps U/V
(YUYV <-> YVYU).

---

## 3. Building

```bash
cd src/basic/verilog/pmod-camera-ov2640

make                # self-test firmware (prints the report at 9600 baud)
make photo          # photo firmware (115200 baud, 60 segments x 8 rows)
make sim            # offline simulation of the report expansion (iverilog)
make sim_photo      # offline simulation of the photo mode
```

You need yosys / nextpnr-ice40 / icetime / icepack.
`ov2640_cfg.hex` and `text.hex` are generated by `gen_cfg_hex.py` /
`gen_text_hex.py`.

Resources and timing (`nextpnr-ice40 --up5k --package sg48` + `icetime`, measured):

| Item | self-test `make` | photo `make photo` |
|---|---|---|
| ICESTORM_LC (logic) | **4999 / 5280 (94%)** | 1389 / 5280 (26%) |
| ICESTORM_RAM (SB_RAM40_4K) | 8 / 30 (26%) | **24 / 30 (80%)** |
| SB_IO | 19 / 96 (19%) | 19 / 96 (19%) |
| SB_GB | 8 / 8 (100%) | 8 / 8 (100%) |
| icetime | **38.19 ns / 26.18 MHz PASSED** (constraint 24 MHz) | **28.44 ns / 35.16 MHz PASSED** |
| Firmware | `top.bin` 104090 bytes, md5 `a8558270b4a0e09ee870ae9378861097` | `top_photo.bin` 104090 bytes, md5 `e7459780eab86639764655804b62894d` |
| Configuration ROM | `ov2640_cfg.hex` 230 entries, md5 `cee3afd62e9e9be21cce721679bba93e` | same |

> **The self-test firmware already uses 94% of the logic** (4999/5280), so be
> frugal when adding features; the photo firmware's bottleneck is RAM
> (80%, of which the line buffer takes 20 blocks).

**There is no frame-rate parameter**: on the OV2640 the frame rate is decided by
`CLKRC(0x11)` / `R_DVP_SP(0xD3)` / `FLL(0x46)`, not by a single pre-divider
register as on the OV5640, so there is no `make FPS=30` switch.

---

## 4. Flashing and looking at the result

Use the iCELink HID command-line tool (**never drag-and-drop the image**, the
virtual USB stick is unreliable):

```
# tools/src/icesprog at the repository root
tools/src/icesprog src/basic/verilog/pmod-camera-ov2640/top.bin
```

**Order matters**: the design runs its measurement once and then stops in
ST_DONE; it does not re-run by itself. So flash first (flashing resets the
target through DAPLink, so the FPGA restarts the measurement), then open the
serial port — the report starts about 8 seconds after the reset.

On Windows, read with pyserial in a tight loop. **Do not use PowerShell's
`System.IO.Ports.SerialPort.Read`** (every call blocks for the full
ReadTimeout, which drops data in chunks at 9600 baud):

```python
import serial, time
ser = serial.Serial('COM419', 9600, timeout=0.05)
buf = bytearray()
t0 = time.time()
while time.time() - t0 < 30:
    d = ser.read(4096)
    if d:
        buf.extend(d)
print(buf.decode('ascii', 'replace'))
```

---

## 5. Measured results (2026-11-23, daytime, iCESugar + PMOD-CAMERA + OV2640)

### 5.1 Self-test report (9600 bps, verbatim from the board)

```
OV2640 DVP TEST  --  iCE40UP5K / iCESugar
=====================================================
[SCCB LINK PROBE]
  sda idle = 01 (1=pull-up ok)  scl idle = 01  addr mask=0x01 (b0=60 b1=30 b2=D8 b3=6C b4=20 b5=50)
  chosen addr=0x60  acks=724  failed=5
  pin check: sda=OK scl=OK   cam pulled SDA=395533 cycles   scl mismatch=0

[SCCB READBACK]
  chip id 0x0A=0x26 0x0B=0x42  (expect 26/42)
  dvp size (measured) 00000280 x 000001E0   IMAGE_MODE=0x00  CTRL0=0x0E
  HSIZE8/VSIZE8=0x0000C896  (expect C896)   HSIZE/VSIZE=0x0000902C (expect 902C)
  DSP bank readback: nonzero=6/8   raw 0xC0=0xC8 0xC1=0x96 0x5A(ZMOW)=0xA0 0x51(HSIZE)=0x90
  sensor bank: GAIN(0x00)=0x03  AEC(0x10)=0x38
  diag nack=0
  reads ok=12/12  writes ok=227  nack tx=0
  sccb link = OK

[DVP]
  pclk = 33 MHz  (OV2640: sysclk / R_DVP_SP)
  frames=14 lines/frame=480 bytes/line=1279 fps=14
  active bytes=9002240 vsync=28 xclk=24MHz
  vsync edges=28 href edges=14066 metric bytes=65536
  data pins changed=0xFF now=0x4C  byte min=0x00 max=0x99
  line period=1366 pclk cycles   frame period=2308964 pclk cycles
  dvp link = OK

[BYTE ORDER] sum |byte-128| over chroma bytes (smaller = better)
  chroma-odd  normal = 160038
  chroma-even normal = 2731827
  chroma-odd  bitrev = 2153488
  chroma-even bitrev = 2088958
  best = 160038
  order = OK

first 16 bytes: 7F 1D 7C 1F 7D 1B 7E 17 7C 16 81 12 7D 17 7A 19
verdict = 15 (bit0 sccb_ok, bit1 dvp_ok, bit2 order_ok, bit3 normal-bits, bit4 chroma-odd)
END
```

> The `GAIN=0x03 / AEC=0x38` in the report are **not** the final exposure values:
> they are an instantaneous reading taken 255 ms after the configuration, while
> the auto-exposure engine is still ramping up. The picture that actually comes
> out is correctly exposed (section 5.3). To see the final values, make the
> trailing delay longer, or switch to manual mode and write fixed values.

### 5.2 Photo mode link verification

| Item | Measured |
|---|---|
| Segments / packets / CRC errors | 60 segments / 538 packets / **0 CRC errors** |
| Frame format | 640x480 YUYV (`IMAGE_MODE=0x00` = high byte first, `CTRL0=0x0E`) |
| DVP timing | PCLK = 33 MHz, 1366 PCLK per line, 2308964 PCLK per frame, 14 fps |
| Geometry | `HSIZE8/VSIZE8=0xC896` (1600x1200 readout), `HSIZE/VSIZE=0x902C`, `ZMOW=0xA0` (640>>2) |

### 5.3 Daytime re-test: a real picture finally came out

Re-tested on the morning of 2026-11-23 (**lights on, lens protection film removed**).
With auto exposure the camera photographed the office: a person in the foreground,
shelves of archive boxes behind, window blinds on the left.

| Channel | min | max | mean | std |
|---|---|---|---|---|
| Y | 0 | 255 | **101.4** | 71.8 |
| U | 71 | 184 | 125.1 | 11.5 |
| V | 79 | 192 | 126.9 | 11.5 |

How to read this:

- **Y mean 101.4** sits in the normal-photo range (ideal mid grey is around 110~120):
  neither blown out nor underexposed;
- U/V means are 125/127 — essentially the chroma midpoint, so the **white balance
  does not cast a colour tint** (skin tones look natural);
- facial features, box labels and the blind slats are all clearly readable;
- the per-row brightness falls off naturally from 146 at the top to 30 at the
  bottom, exactly like a real room;
- the horizontal tearing is the **inherent cost of the segmented scan** (8 rows per
  frame, 60 segments taken from 60 different frames). Static objects are fine,
  a moving face smears. That is the protocol's price, not a bug.

### 5.4 How to set the exposure

The default is **auto exposure** (the on-chip engine, see 5.5) — nothing to tune.
For a very bright/dark scene, or when you want a completely deterministic
exposure, switch to **manual**: put `COM8=0xE0` in `ov2640_end_regs` (AGC/AEC off)
and write `GAIN(0x00)` and `AEC(0x10)` yourself.

Gain formula from the datasheet:
`Gain = (B7+1)x(B6+1)x(B5+1)x(B4+1)x(1 + B3:0/16)`, range 1x..32x.

| Configuration | GAIN | Factor | AEC | Measured Y mean | Comment |
|---|---|---|---|---|---|
| **auto (default)** | engine | — | engine | **101.4** | ✅ adapts to the light, recommended |
| manual | `0xFF` | 32x | `0xFF` | 175.2 | **overexposed**, highlights are dead white |
| manual | `0x7E` | 15x | `0xFF` | 99.7 | ✅ fine indoors during the day as well |
| manual | `0x38` | 6x | `0xFF` | darker | bright light / outdoors |
| manual | `0x18` | 2x | `0xFF` | very dark | very bright environment |

> AEC is **16 bits spread over three registers**: `REG45(0x45)[5:0]` = AEC[15:10],
> `AEC(0x10)[7:0]` = AEC[9:2], `REG04(0x04)[1:0]` = AEC[1:0].
> Writing only `0x10` controls the low 8 bits (= AEC[9:2]); 0xFF means AEC=1020.
> To change the exposure, edit the few lines of `ov2640_end_regs` in
> `ov2640_regs.h`, then run
> `python3 gen_cfg_hex.py ov2640_regs.h ov2640_cfg.hex && make && make photo`.

### 5.5 The auto-exposure engine: four controlled experiments (root cause found)

The OV2640 has an internal AE/AWB engine, switched on by `AEC_EN`/`AGC_EN` in
`COM8`. It was tested thoroughly here; all four runs used the same scene and
the same lighting:

| # | What is written at the end of the register table | Read-back GAIN / AEC | Picture |
|---|---|---|---|
| 1 | kernel ordering (`COM8=0xE5` near the top) | `0x01` / `0x4E` (power-on defaults) | black at night, the engine never took over |
| 2 | only `COM8=0xE5` appended at the end (other AE registers still at the top) | `0x01` / `0x4E` → engine pins to `0xFF`/`0xFF` | overexposed, Y=175.2 |
| 3 | whole AE block moved to the end (`AEW=0x40 AEB=0x38`) | `0x03` / `0x38` (ramping up) | correct magnitude |
| 4 | whole AE block moved to the end (`AEW=0xFF AEB=0x00`) ✅ **default** | `0x03` / `0x38` (ramping up) | **correct, Y=101.4** |

**Root cause: the OV2640 restores its AE configuration to the defaults during the
reset sequence, so the whole AE block — `COM8` / `COM9` / `AEW` / `AEB` / `VV` /
16-zone metering weights / histogram limits — must be written at the very end of
the register table (i.e. after the reset).**

- Experiment 1 → 2: moving only `COM8` to the end lets the engine take over, but
  it then uses the post-reset default parameters and ramps gain and exposure to
  the maximum → overexposed;
- Experiment 2 → 4: moving the **whole** AE block to the end is what gives the
  engine the right parameters → correct exposure;
- Experiment 3 vs 4: the values of `AEW`/`AEB` make **no difference at all**
  (identical read-back), so what matters is the **position of the AE block**,
  not those two register values;
- A second clue from experiment 1: while the engine is not in control the read-back
  shows the factory defaults `0x01`/`0x4E`, whereas in manual mode writing
  `GAIN=0x7E` reads back exactly `0x7E` — so the read-back path itself is fine.

### 5.6 Summary

- ✅ SCCB works, register writes and read-back work (`reads ok=12/12`, `nack tx=0`);
- ✅ DVP really streams, 640x480 YUYV, byte order / geometry / timing all checked;
- ✅ **a properly exposed real picture comes out** (Y mean 101.4, no colour cast);
- ✅ **the on-chip auto exposure is usable** — provided the AE block is written at
  the end of the register table (section 5.5).

---

## 6. Files

| File | Purpose |
|---|---|
| `top.v` | Top level: reset / PLL / pin IO / main state machine / report |
| `sccb_master.v` | SCCB master (open-drain physical layer + ACK detection + pin self-test), **with the `ADDR8` parameter** |
| `ov2640_cfg.v` | Register configuration sequence (ROM-driven, supports "write / read / delay" operations) |
| `dvp_capture.v` | DVP capture / statistics / byte-order decision (PCLK clock domain) |
| `uart_tx.v` | 9600 8N1 serial transmitter |
| `uart_printer.v` | Text template interpreter (text.hex) |
| `tb_printer.v` | iverilog test bench for uart_printer (offline verification of the report) |
| `gen_cfg_hex.py` | Builds the configuration ROM from `ov2640_regs.h` |
| `gen_text_hex.py` | Builds the report text template |
| `ov2640_regs.h` | OV2640 register table (Linux kernel + esp32-camera cross-checked) |
| `top.pcf` | Pin constraints for the self-test mode |
| `top_photo.v` / `top_photo.pcf` | Photo-mode top level / pin constraints |
| `dvp_linebuf.v` | DVP capture + on-chip line buffer (photo mode) |
| `photo_tx.v` | Line buffer -> CRC-protected line packets -> serial |
| `host_capture.py` | Host side: flash / collect packets / CRC check / assemble YUYV / convert to PNG |
| `tb_linebuf.v` / `tb_photo.v` / `tb_top_photo.v` / `chk_photo.py` | Offline verification of the photo mode |

---

## 7. OV2640 pitfalls (for whoever comes next)

> The 26 pitfalls of the OV5640 project (timing / reset / resources / CRC / BRAM
> and so on) apply here just as well, so only the **OV2640-specific** ones are
> listed.

1. **OV2640 register addresses are a single byte, while the OV5640
   `sccb_master` sends 16-bit ones.** The OV5640 version sends
   `reg[15:8] + reg[7:0]`, two address bytes. On an OV2640 that means **the
   register address gets written as data** — the symptom is "no register ever
   takes, but SCCB still acknowledges".
   Fix: add an `ADDR8` parameter to `sccb_master`; in 8-bit mode only one address
   byte is sent and the byte-index checks for read/write transactions change
   accordingly (`write: bi==2 -> STOP after the data byte`,
   `read: bi==1 -> switch to the read phase after the register byte`).
   The `sccb_master.v` in this OV2640 directory defaults to `ADDR8 = 1`.

2. **The chip ID lives in bank1, so you must switch banks before reading.**
   On the OV2640 `0xFF` is the bank select register: write `0xFF=0x00` for the
   DSP bank, `0xFF=0x01` for the sensor bank. `PID(0x0A)` / `VER(0x0B)` are in
   the sensor bank, while `IMAGE_MODE(0xDA)` / `ZMOW(0x5A)` are in the DSP bank.
   So the diagnostic read cannot be "read 12 addresses in a row" like on the
   OV5640; this project uses **14 steps: 1 write to switch bank + 4 reads +
   1 write to switch back + 8 reads**. Forgetting the bank switch shows up as
   "everything reads back 0x00, or the value of the previous bank".

3. **Never de-duplicate the configuration ROM by address.**
   The OV5640 `gen_cfg_hex.py` merges repeated writes to the same address into
   the last one — safe there, because OV5640 register addresses are unique.
   Not on the OV2640: `0xFF` is two different registers in the two banks, and
   consecutive `BPDATA(0x7D)` writes rely on the chip's **internal address
   auto-increment**
   (`0x7C=0x03, 0x7D=0x48, 0x7D=0x48, 0x7C=0x08, 0x7D=0x20, ...`); merging them
   corrupts the sequence. The OV2640 generator emits the table strictly in
   order, unchanged.

4. **You must delay after the soft reset.**
   The OV2640 does not produce any picture after power-up: the whole register
   table has to be written. And after the soft reset via `COM7(0x12)=0x80` all
   registers go back to their factory values, so the entire table has to be
   written again — the chip needs time to finish resetting in between.
   That is why the ROM has a fourth opcode, **op=3 "delay N milliseconds"**,
   with a matching `S_DELAY` state in `ov2640_cfg.v`.
   Skip it and, at best, the reset does not take effect; at worst every
   following write lands nowhere.

5. **Every value in `ov2640_regs.h` has to be written as 0x hex.**
   I hit this one myself: a delay pseudo-instruction written as
   `{ 0xFF00, 5 }` (decimal) was silently skipped, because the generator's
   regex only accepts values starting with `0x`. **No error is raised, the ROM
   is still generated — the wait is simply missing.** The generator now counts
   how many entries the table has and how many it parsed, and aborts when they
   disagree.

6. **Do not treat `HSIZE8/VSIZE8` as the output size** (see section 2.1).
   The right thing is an input of 1600x1200 and ZMOW/ZMOH = 640x480.

7. **The published semantics of `CLKRC(0x11)` and `R_DVP_SP(0xD3)` do not
   agree with each other.** The four drivers give contradictory values
   (`CLKRC`: 0x00 / 0x01 / 0x07 / 0x80; `R_DVP_SP`: "manual 0x02" vs
   "auto 0x80"), and the models for the resulting PCLK differ by 1.5x to 3x.
   This project uses the kernel's set (`CLKRC=0x00` + `R_DVP_SP=0x02`);
   **measured PCLK = 33MHz**, 640x480 @ 14fps, which is enough.
   To change the frame rate, change these two registers and re-run the
   self-test to read `pclk` from the report. Whether bit7 of `CLKRC` means
   "PLL enable" or "2x clock" still does not match the public sources.

8. **Bits [1:0] of `REG04(0x04)` are the low 2 bits of the AEC exposure
   value** — do not clobber them when changing the mirror setting.
   The mirror bits are bit7 (HFLIP) / bit6 (VFLIP); flipping vertically also
   needs bit4 (VREF_EN), otherwise you get red/green stripes (there is a 2006
   Linux kernel patch about exactly that).

9. **The image orientation depends on how the vendor assembled the lens, not
   on the silicon.** The OV2640 is an **FSI** (front-illuminated) sensor, so
   the read-out direction is not mirrored by itself, but a module vendor may
   mount the lens upside down.
   The defaults of the Linux / esp32 / Zephyr drivers are all `REG04 = 0x28`
   (no flip), while the default tables of OpenMV2 and mikroPhone use `0xF8`
   (everything flipped on).
   **How to check**: take a photo **of a human face** — nose pointing to the
   left of the picture and the ear on the right side of the face means the
   orientation is correct (you are seeing their left ear); nose to the right and
   ear to the left means the image is mirrored.

10. **The first frame after a size change may be garbage.** On the OV2640 the
    AWB/AEC need 10..20 frames to settle, so the first frames after power-up
    tend to be green-ish. The self-test waits for 6 vertical-sync edges before
    reading the registers back, and in photo mode every segment comes from a
    different frame, so white balance has long converged by the time the 60
    segments are complete.

11. **When the picture is black, look at the two exposure registers
    `GAIN(0x00)` / `AEC(0x10)` first.** They are the primary evidence for
    whether the auto-exposure engine is alive at all:

    * `GAIN` stuck at `0x00/0x01` (minimum) with a small `AEC`
      -> the chip thinks the scene is **bright** while the picture is black, so
      the metering input and the real image disagree.
    * `GAIN` above `0x3C` and a large `AEC`
      -> the chip thinks the scene is **dark** and is pushing the exposure hard,
      yet the picture is still black: the problem is the analog path or the
      module itself (lens covered, module mounted the wrong way, dead).

    The first black capture in this project showed `GAIN=0x01 / AEC=0x4E` (both
    at the minimum) while **the lab lights were off** — a scene that dark should
    have pushed auto-exposure to the other extreme, which by itself proves the
    auto-exposure was not working. **Before investigating any OV2640 "black
    picture" problem, always read the GAIN/AEC values out of this report.**

12. **Using bit1 (0x02) of `COM7(0x12)` to switch on the colour-bar pattern is
    the cheapest way to localise a "black picture" problem.**
    `COM7 = 0x04 | 0x02 = 0x06` enables the chip's internal test-pattern
    generator, which bypasses the sensor analog path.
    Bars look right => the FPGA capture chain is fine and the problem is on the
    sensor side; bars look wrong => go back and check the DVP timing, the byte
    order and the pinout.
    This project used exactly that trick to narrow the problem down to "only
    the analog/exposure side is left" (section 5.2).

13. **The esp32-camera and Linux kernel analog register sets differ in two
    places — try them if you change the module.** Both tables are for the
    OV2640, but these two sensor-bank registers differ:

    | Register | Linux kernel | esp32-camera (UXGA) |
    |---|---|---|
    | `0x39` | `0x02` | `0x82` |
    | `0x06` | `0x02` then `0x88` (final value 0x88) | `0x02` (final value 0x02) |

    All the other analog registers (`0x35` / `0x22` / `0x37` / `0x34` / `0x0D` /
    `0x0E` / `0x42`) agree between the two in the UXGA mode.
    If the picture is still wrong after changing the module, try esp32-camera's
    values for these two registers, re-running the self-test after every change
    and watching whether GAIN/AEC in the report move — that tells you which
    register actually does something.

14. **Forcing manual exposure and gain is the fastest way to find out whether
    the analog path works at all.** Add three writes at the end of
    `ov2640_end_regs` in `ov2640_regs.h`:

    ```c
    { 0xFF, 0x01 },     // BANK_SEL = sensor bank
    { 0x13, 0xE0 },     // COM8: clear AGC_EN(0x04) / AEC_EN(0x01) -> manual mode
    { 0x00, 0x3C },     // GAIN  manual gain
    { 0x10, 0x80 },     // AEC   manual exposure
    { 0xFF, 0x00 },     // BANK_SEL = DSP bank
    ```

    In manual mode the GAIN/AEC read-back equals what was written, which
    confirms that those two registers really are writable and readable (the
    self-test report prints them). If the picture is still black with maximum
    gain and maximum exposure, you can basically rule out "auto-exposure never
    converged" and go straight to the module, the lens and the assembly.

---

### Pitfall 15: the **whole AE block must be written at the end** of the OV2640 register table

`COM8` bit0 = `AEC_EN`, bit2 = `AGC_EN` switch the chip's AE/AWB engine on;
`COM9` (AGC ceiling), `AEW`/`AEB` (stable operating region), `VV`, the 16-zone
metering weights (`0x5D~0x60`) and the histogram limits (`0x61`/`0x62`) are the
algorithm's parameters.

**The chip restores this configuration to its defaults during the reset
sequence**, so writing the block at the top of the table (kernel ordering)
throws all of it away:

- `COM8=0xE5` at the top → read-back `GAIN=0x01`/`AEC=0x4E` (factory defaults),
  the engine never takes over and the night capture comes out black;
- `COM8=0xE5` appended at the end → the engine takes over, but with the
  post-reset default parameters, and ramps gain and exposure to the full 32x
  range → overexposed;
- **moving the whole AE block to the end** → the engine gets the right
  parameters → correct exposure (Y mean 101.4).

### Pitfall 16: the **values** of `AEW`/`AEB` do not matter, their **position** does

`AEW=0x40 AEB=0x38` (kernel values) and `AEW=0xFF AEB=0x00` (range fully open)
measured **identically** — same read-back, same picture. So do not agonise over
those two register values; first make sure the whole AE block is written after
the reset.

### Pitfall 17: before trusting a `GAIN`/`AEC` read-back, prove the write path in **manual mode** first

`GAIN=0x01` / `AEC=0x4E` has two completely different causes:
(a) the chip wrote them (the AE engine took over), or (b) our write never landed.
Confusing the two leads to wrong conclusions such as "the read-back path is
broken" or "the engine is dead". Reliable procedure: first write `COM8=0xE0`
(engine off) and `GAIN=0x7E` — the read-back must be `0x7E`; only then turn
the engine on and re-measure, and a changed value proves the engine wrote it.

### Pitfall 18: **Timing** of the diagnostic read: at least 255 ms at the end, and you read a value from *mid-ramp*

The engine needs a few frames to converge (~14 fps at 640x480, so 3~4 frames =
200~300 ms). With only a 50 ms delay at the end you read the *pre-convergence*
factory values and conclude that the engine is dead. Even with 255 ms the value
you read is still an instantaneous one from the middle of the ramp (measured
`GAIN=0x03/AEC=0x38` while the actual picture is correctly exposed) —
**judge the exposure from the picture / brightness, not from those two
registers**.

### Pitfall 19: when only the register table changed, `make photo` may reuse the **old bitstream**

`ov2640_cfg.hex` is a prerequisite of `top_photo.json`, but a freshly
regenerated hex can be *older* than the json produced by the previous build, so
make considers the target up to date and skips the rebuild. The result is
"code changed, firmware did not". Force a rebuild after editing the table:

```bash
touch top.v top_photo.v      # or rm -f top_photo.json
make && make photo
```

## 8. Appendix: the 14 diagnostic read steps

The order is fixed (a bank switch must come before the matching reads):

| Step | Action | Register | Content | Expected |
|---|---|---|---|---|
| 0 | write | 0xFF | switch to the sensor bank | 0x01 |
| 1 | read | 0x0A | chip ID PID | **0x26** |
| 2 | read | 0x0B | chip ID VER | **0x42** |
| 3 | read | 0x00 | GAIN (AGC gain) | see pitfall 11 in section 7 |
| 4 | read | 0x10 | AEC (exposure time) | see pitfall 11 in section 7 |
| 5 | write | 0xFF | switch back to the DSP bank | 0x00 |
| 6 | read | 0xC0 | HSIZE8 (input width>>3) | **0xC8** (1600) |
| 7 | read | 0xC1 | VSIZE8 (input height>>3) | **0x96** (1200) |
| 8 | read | 0x8C | SIZEL | 0x00 |
| 9 | read | 0x51 | HSIZE (input width>>2) | **0x90** (400) |
| 10 | read | 0x52 | VSIZE (input height>>2) | **0x2C** (300) |
| 11 | read | 0xDA | IMAGE_MODE | **0x00** (YUV422/YUYV) |
| 12 | read | 0xC2 | CTRL0 | **0x0E** (YUV422\|YUV_EN\|RGB_EN) |
| 13 | read | 0x5A | ZMOW (output width>>2) | **0xA0** (640) |

---

# Photo mode (`top_photo`) — camera -> serial -> PNG on the host

`top.v` is the "functional self-test": configure the camera, measure the DVP
bytes, print a diagnostic report.
`top_photo` is the "camera": it sends the image the sensor sees out over the
serial port and the host stitches it into a PNG.

The two entry points are independent; the default flow (`make`) is still the
self-test, the photo build is separate (`make photo`).

## 9.1 How to use it

```bash
cd src/basic/verilog/pmod-camera-ov2640

# 1) build the photo firmware (115200 baud / 8 rows per segment by default)
make photo

# 2) flash + collect (run on the Windows host; needs pyserial + numpy + pillow)
python host_capture.py --flash --baud 115200 --seconds 200
```

The host prints progress and finally writes three files:

| File | Content |
|---|---|
| `photo.raw` | the assembled raw YUYV (640x480x2 = 614400 bytes) |
| `photo.png` | the RGB PNG |
| `photo.stream` | the raw serial byte stream (for debugging) |

`--flash` calls `icesprog.exe` first (**never drag-and-drop**, the virtual USB
stick is unreliable) and then finds the iCELink CDC port (VID_1D50 / PID_602B)
to collect the data.

Measured (2026-11-22): **about 58 seconds for 480 rows / 60 segments, 0 CRC
errors**.

## 9.2 Why the segmented scan

One 640x480 YUYV frame is 614400 bytes, while all the BRAM on the iCE40UP5K is
30 x 4Kbit = 15KB, so **a whole frame simply does not fit**. On top of that the
serial link at 115200 only carries 11520 bytes/second, while one camera line
(38us at 33MHz) is long gone by then.

So the design uses a "band scan" instead:

- each segment captures `KROWS = 8` rows (10240 bytes, 20 BRAM blocks) into the
  on-chip buffer;
- the serial link slowly sends those 8 rows out (8 x 1280 = 10240 bytes, 888ms);
- once that is done the next segment is captured, **starting at row `seg*8` of
  the next frame** (the camera keeps streaming all the time; we only store the
  rows we need and throw the other frames away);
- the host assembles the 60 segments into one picture using the row numbers.

One row has to be captured in 38us (1280 bytes), while sending one row over the
serial link takes 111ms, so **you cannot capture and send at the same time** —
the buffer is the only way out.

The segment start row is re-armed on the **frame boundary (VSYNC rising edge)**,
so the row numbers always line up with the frames; half a row or leftovers from
the previous frame can never be captured.

## 9.3 Serial protocol

One packet per line:

```
A5 5A            magic (the host re-syncs on it)
row_lo row_hi    row number (little endian, 16 bits)
len_lo len_hi    payload length of this line (little endian, 16 bits, = 1280)
data[len]        raw YUYV bytes
crc_lo crc_hi    CRC16/CCITT-FALSE (poly 0x1021, init 0xFFFF)
```

- The CRC covers `row(2) + length(2) + data`, **not** the magic;
- status packets use `row = 0xFFFF, len = 16` and carry telemetry (diagnostic
  code / flags / segment number / rows captured so far / bytes captured so far /
  byte count of the last row). One is sent after every segment so you can see
  what the FPGA is doing;
- right after the reset a "link beacon" status packet is sent (diagnostic code
  = 3), so as soon as the host sees it the bitstream is alive; if nothing
  follows, the problem is capture/configuration, not the link.

## 9.4 Files of the photo mode

| File | Purpose |
|---|---|
| `top_photo.v` | Photo-mode top level (PLL / IO / SCCB configuration / capture / packing / state machine) |
| `top_photo.pcf` | Pin constraints (identical to `top.pcf`) |
| `dvp_linebuf.v` | DVP capture + on-chip line buffer (write port in the PCLK domain, read port in the clk24 domain) |
| `photo_tx.v` | Line buffer -> CRC-protected line packets -> serial |
| `host_capture.py` | Host side: flash / collect packets / CRC check / assemble YUYV / convert to PNG |
| `tb_linebuf.v` | Offline verification: synthesise a DVP stream and check "which rows did we really capture" |
| `tb_photo.v` | Offline verification: restore the serial byte stream and compare it byte for byte with the host algorithm |
| `tb_top_photo.v` | Offline verification: stubs for SB_PLL40_PAD/SB_IO so the top level can be simulated directly |
| `chk_photo.py` | The comparison script used by `tb_photo` |

Offline verification: `make sim_photo` (no hardware needed).

## 9.5 Resources and timing (measured)

| Item | Value |
|---|---|
| ICESTORM_LC (logic) | 1389 / 5280 (26%) |
| ICESTORM_RAM (SB_RAM40_4K) | 24 / 30 (80%, of which 20 are the line buffer and 4 the camera configuration ROM) |
| SB_IO / SB_GB | 19 / 96 / 8 / 8 |
| icetime | **28.44 ns / 35.16 MHz PASSED** @ 24 MHz |
| Whole-frame time | about 58 seconds (115200 baud, 60 segments) |
| Firmware | `make photo` produces 104090 bytes, md5 `e7459780eab86639764655804b62894d` |
