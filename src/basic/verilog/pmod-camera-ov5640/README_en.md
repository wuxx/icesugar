# OV5640 DVP Verification on iCESugar (iCE40UP5K + PMOD-CAMERA)

> **This is the English version.** The Chinese version is [`README.md`](README.md);
> both documents describe exactly the same hardware, firmware and measurements.

Drives a PMOD-CAMERA (OV5640) on an iCESugar board (iCE40UP5K-SG48I). On power-up
the FPGA automatically runs *"configure over SCCB -> read back key registers ->
measure the DVP stream for 1 second -> determine the byte order"* and finally
prints a self-test report over the UART at 9600 8N1.

There are only two goals: **prove that the SCCB link works** and **prove that DVP
data really flows**.

Current status: **verified on real hardware** (2026-11-20, see "Measured results"
below, `verdict = 15` = 0b01111 — all five conclusions green).

---

## Quick start

```bash
cd src/basic/verilog/ov5640

# Self-test firmware: prints a diagnostic report at 9600 baud
make
../../../tools/src/icesprog top.bin

# Photo firmware: streams a 640x480 YUYV image over the serial port
make photo
python host_capture.py --flash --baud 115200 --seconds 200   # needs pyserial/numpy/pillow
```

`make photo` writes `top_photo.bin`; the host script flashes it, reassembles the
image and saves `photo.raw` + `photo.png`.

---

## Hardware connections

| FPGA pin | Signal | Direction | Notes |
|---|---|---|---|
| 35 | clk12 | in | On-board 12 MHz (iCELink MCO via ICE_CLK) |
| 43 | XMCLK | out | 24 MHz (PLL 12->24, IOB DDR, 50% duty) |
| 44 | PCLK | in | DVP pixel clock (wired to a global clock) |
| 38 | VSYNC | in | DVP vertical sync |
| 42 | HREF | in | DVP horizontal sync |
| 37 | SCL | bidir | SCCB clock (open-drain + internal pull-up) |
| 36 | SDA | bidir | SCCB data (open-drain + internal pull-up) |
| 23 / 25 / 26 / 27 / 28 / 31 / 32 / 34 | D0..D7 | in | DVP data Y2..Y9 (PMOD3) |
| 6 | TX | out | UART output (iCELink CDC, 9600 8N1) |
| 40 / 41 / 39 | LED_R/G/B | out | green = all passed, red = failure, blue = working |

The two SCCB lines use an open-drain physical layer: `SB_IO PIN_TYPE=6'b1010_01` +
`D_OUT_0=0` + `OUTPUT_ENABLE=*_low` + `PULLUP=1`. The FPGA pulls the line low,
the slave (or the pull-up) releases it.

The pin assignment was cross-checked against `src/common/io.pcf` and
`schematic/pmod-camera-v1.0.pdf`.

## Building

```
make                # default FPS=15 (0x3035=0x21 -> PCLK 28MHz)
make FPS=30         # 0x3035=0x11 -> PCLK 56MHz
make sim            # offline simulation of the report formatter (iverilog, no hardware)
```

Requires yosys / nextpnr-ice40 / icetime / icepack. `ov5640_cfg.hex` and `text.hex`
are generated automatically by `gen_cfg_hex.py` / `gen_text_hex.py`; there is
nothing to maintain by hand.

Resource usage and timing (up5k / sg48, yosys 0.9 + nextpnr + icetime):

| Item | Usage |
|---|---|
| SB_LUT4 | 3420 |
| Flip-flops | 2251 |
| SB_CARRY | 1244 |
| SB_RAM40_4K | 8 (1 config ROM + 4 text templates + 3 other) |
| icetime | 36.44 ns / 27.44 MHz **PASSED** (constraint 24 MHz) |
| nextpnr | clk24 26.74 MHz / PCLK 31.52 MHz, both PASS |
| top.bin | 104090 bytes |

## Flashing and reading the result

The iCELink HID command-line tool:

```
../../../tools/src/icesprog top.bin
```

**The order matters**: this design runs one measurement and then stays in
ST_DONE, it does not re-run by itself. So flash first (flashing resets the target
through the DAPLink, which restarts the measurement on the FPGA), *then* open the
serial port — the report starts printing roughly 8 seconds after reset.

On the Windows side, read the port with pyserial in a tight loop. **Do not use
PowerShell's `System.IO.Ports.SerialPort.Read`** — every call blocks for the full
ReadTimeout, which drops data in large chunks at 9600 baud (measured: only 283
bytes received):

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

## Measured results (2026-11-20, iCESugar + PMOD-CAMERA)

```
OV5640 DVP TEST  --  iCE40UP5K / iCESugar
=====================================================
[SCCB LINK PROBE]
  sda idle = 01 (1=pull-up ok)  scl idle = 01  addr mask=0x01 (b0=78 b1=D8 b2=6C b3=30 b4=20 b5=50)
  chosen addr=0x78  acks=1133  failed=5
  pin check: sda=OK scl=OK   cam pulled SDA=594854 cycles   scl mismatch=0

[SCCB READBACK]
  chip id 0x300A=0x56 0x300B=0x40  (expect 56/40)
  dvp size (measured) 00000280 x 000001E0   fmt=0x30 (30=YUYV)  en=0x7F
  HTS=00000768  VTS=000003D8
  0x38xx readback: nonzero=8/8   raw 0x3808=0x02  0x3809=0x80  0x380A=0x01  0x380B=0xE0
  diag nack=0
  reads ok=12/12  writes ok=271  nack tx=0
  sccb link = OK

[DVP]
  pclk = 28 MHz  (expect ~28 @15fps / ~56 @30fps)
  frames=2 lines/frame=480 bytes/line=1279 fps=2
  active bytes=1228800 vsync=4 xclk=24MHz
  vsync edges=4 href edges=1920 metric bytes=65536
  data pins changed=0xFF now=0x19  byte min=0x16 max=0x91
  line period=3791 pclk cycles   frame period=11374103 pclk cycles
  dvp link = OK

[BYTE ORDER] sum |byte-128| over chroma bytes (smaller = better)
  chroma-odd  normal = 146461
  chroma-even normal = 2882674
  chroma-odd  bitrev = 2155284
  chroma-even bitrev = 2123188
  best = 146461
  order = OK

first 16 bytes: 72 1A 82 19 73 1B 81 1B 78 1B 80 1B 78 1C 83 1C
verdict = 15 (bit0 sccb_ok, bit1 dvp_ok, bit2 order_ok, bit3 normal-bits, bit4 chroma-odd)
END
```

Conclusions:

- **SCCB is fine**: chip ID 0x56/0x40 read back correctly; all 271 register writes
  were acknowledged; all 12 key registers read back the expected values, including
  **all 8 of the 0x38xx output-window / timing registers**
  (0x3808=0x02 / 0x3809=0x80 -> 640; 0x380A=0x01 / 0x380B=0xE0 -> 480;
  HTS=0x0768 / VTS=0x03D8). Only address 0x78 answers during the address probe
  (mask=0x01), i.e. the camera is the only slave on the bus. The SCL/SDA pull-ups
  are healthy, the pin self-test passes and there is not a single SCL read-back
  mismatch inside the acknowledge window.
- **DVP data really flows**: PCLK 28 MHz; 480 lines per frame; 1279 bytes per line
  (640 pixels x 2 bytes per pixel for YUV422 = 1280; the missing one is the cycle
  at the very start of the line); all 8 data lines toggle (`changed=0xFF`); the
  sampled byte range is 0x16..0x91.
- **Byte order**: the "chroma on odd byte positions + normal bit order" hypothesis
  scores the lowest (146461, more than 14x better than the other three), i.e. the
  stream alternates Y,U,Y,V — consistent with 0x4300=0x30 (YUYV).
- **Line/frame timing**: the line period of 3791 PCLK cycles is exactly
  2 x HTS (0x0768 = 1896). The frame period of 11374103 cycles is ~0.406 s, i.e.
  the measured frame rate is about 2.5 fps rather than the 15 fps implied by the
  registers. **This is the OV5640 auto-exposure stretching the frame interval
  (longer vertical blanking), not an FPGA problem** — the line time matching HTS
  exactly is the proof. (In bright light the camera drops the frame rate by
  itself; depending on the lighting the measured rate floats between 2 and 6 fps,
  which is why the `dvp link` criterion is `frames >= 2` and not `>= 5`.)

## Files

| File | Purpose |
|---|---|
| `top.v` | Top level: reset / PLL / pin IO / main state machine / report |
| `sccb_master.v` | SCCB master (open-drain physical layer + acknowledge detection + pin self-test) |
| `ov5640_cfg.v` | The 271-register configuration sequence (the ROM holds write ops only) |
| `dvp_capture.v` | DVP capture / statistics / byte-order determination (PCLK clock domain) |
| `uart_tx.v` | 9600 8N1 UART transmitter |
| `uart_printer.v` | Text template interpreter (text.hex) |
| `tb_printer.v` | iverilog testbench for uart_printer (offline report formatting) |
| `gen_cfg_hex.py` | Generates the config ROM from `ov5640_regs.h` |
| `gen_text_hex.py` | Generates the report text templates |
| `ov5640_regs.h` | OV5640 register table (ArduCAM variant) |

## Pitfalls (left here for the next person)

1. **The SCL low period of an SCCB transfer must last a full half bit period.**
   The first version only waited one system clock in the "prepare phase (SCL low)",
   so the SCL low pulse was 42 ns and the slave could not recognise the falling
   edge of SCL — **it never ACKed** (symptom: `acks=0`, every attempt failed).
   Waiting a full HALF cycle fixed it immediately. The bit timing must be
   `phase 0: SCL low + present data (wait HALF) / phase 1: SCL high (wait HALF, sample mid-bit)`.
2. **A register must not be driven by two always blocks.** The self-test flags
   `sda_pin_ok` / `scl_pin_ok` / `scl_mismatch_cnt` were originally reset in a
   separate always block and assigned in the main state machine, so the values
   stayed stuck at their reset value (the self-test always FAILed). Verilog does
   not complain, but the synthesised result is undefined.
3. **A 16-bit counter cannot implement a 4,800,000-cycle power-on delay** — it
   overflows and the condition is never true.
4. **The reset counter must saturate.** A free-running 16-bit counter wraps every
   65536 cycles (2.73 ms), so `rst_n` is pulled low over and over and the design
   never reaches the printing stage.
5. **Do not keep all report variables in registers.** 57 x 32-bit variables =
   1824 flip-flops, and the UP5K only has 5280 LC, so nextpnr fails with
   `Failed to expand region`. Pointing combinational wires directly at the source
   signals (config result registers / frozen snapshots / write-only counters)
   brings it to 0 flip-flops.
6. **A later assignment inside the same always block overrides an earlier one.**
   `line_bytes <= 0` used to sit in the HREF rising-edge branch while an
   unconditional `line_bytes <= line_bytes + 1` followed it, so the reset was
   overridden and "bytes per line" became the random value of a free-running
   16-bit wrap-around counter.
7. **Stop counting after taking the frozen snapshot.** Otherwise the "frames"
   field of the snapshot is overwritten by the VSYNCs that arrive after the
   freeze (that is where `vsync=18` with `frames=6` came from).
8. **Writes need a timeout.** With no camera connected (or no acknowledge) the
   state machine waits forever for the handshake and not a single byte comes out.
   With a timeout it continues with whatever it has, and the report then shows
   *which* stage was empty.
9. **Bit order of the decimal conversion.** `dec_dig[k]` holds the 10^k digit and
   must be printed from the most significant one down: `emit_idx` counts from 0
   and takes `dec_dig[dec_start - emit_idx]`. Also, report variable indices need
   6 bits — with 5 bits, everything above v32 prints as something else.
10. **The 0x38xx group (output window / timing registers) must be read last among
    the diagnostic reads.** 0x300A / 0x300B / 0x4300 / 0x3017 read correctly at any
    point; the 0x38xx group read back as 0x00 whenever it came first, and all 8
    were correct when moved into the last 8 slots (nonzero=8/8). Hypotheses that
    were tried and ruled out: read method (Sr vs STOP+START are identical),
    double reads, read-back during the cfg phase, a 300 ms settle, two reads with
    a gap in between, an `rd_addr()` function vs literal addresses, the ST_WAITV
    wait length. **It was finally solved by reordering the diagnostic reads.**
11. **The nibble selection in the hex32 printer.** It used to read
    `emit_val[31 - {emit_idx[1:0], 2'b00}]` with a 2-bit `emit_idx`, so only 4 of
    the 8 nibbles were distinct positions and the printer printed them twice —
    every value below 0x10000 (HTS / VTS / 640x480) showed up as `00000000`,
    which looks like "nothing was read". The fix is a 32-bit shift register
    `hex32_sr` that shifts left by 4 for every nibble.
12. **The "highest non-zero digit" priority encoder of the decimal converter
    destroys the timing budget.** `dec_start` is a 4-level LUT chain over
    9 `dec_dig[i] != 0` terms, followed by "select the bit by dec_start + add
    0x30 + feed the UART shift register". The whole critical path was 42.1 ns >
    41.67 ns and nextpnr reported FAIL. Fix: register `dec_start` into
    `dec_start_r` during the `S_DEC4` cycle and use only the registered value
    while transmitting (clk24 went from 23.7 MHz back to 26.7 MHz).
13. **The text template must not be longer than the text ROM.** With a 1349-byte
    template and a 1024-byte ROM, `tpos` wrapped around, the 0x00 terminator was
    never reached and the report repeated from the beginning forever (one capture
    showed 30+ repeated blocks). After growing the ROM to 2048 bytes
    (`reg [7:0] trom [0:2047]` and `tpos` widened to 11 bits) the report became
    complete.
14. **Do not grab the serial port with PowerShell's `SerialPort.Read`.** Every
    call blocks until the ReadTimeout expires, which at 9600 baud means data is
    dropped in large chunks: only 283 bytes arrived, which looks like "the FPGA
    stopped printing halfway". A tight pyserial loop got the complete 1414-byte
    report in one go. **When debugging this class of problem, suspect the host
    before you suspect the RTL.**
15. **If you are not sure whether the RTL is at fault, write a testbench.**
    `tb_printer.v` runs the real `text.hex` through iverilog and confirms
    offline that the template expansion logic and the terminator handling are
    correct (in this case it proved the RTL was fine and the problem was on the
    host side).

## Appendix: order of the registers in the diagnostic read

There are 12 diagnostic reads and their order is fixed (the order matters, see
pitfall 10):

| Slot | Register | Content | Expected value |
|---|---|---|---|
| 0 | 0x300A | Chip ID, high byte | 0x56 |
| 1 | 0x300B | Chip ID, low byte | 0x40 |
| 2 | 0x4300 | Output format | 0x30 (YUYV) |
| 3 | 0x3017 | DVP output enable | 0x7F |
| 4..7 | 0x3808..0x380B | Output window (width/height) | 02 80 01 E0 |
| 8..11 | 0x380C..0x380F | HTS / VTS | 07 68 03 D8 |

---

# Photo mode (`top_photo`) — camera -> serial port -> PNG on the host

`top.v` is the **self test**: it configures the camera, measures the DVP bytes
and prints a diagnostic report. `top_photo` is the **photo mode**: it sends the
image the camera sees out over the serial port, and the host stitches it into a
PNG.

The two entry points do not interfere with each other: the default flow (`make`)
is still the self test, and the photo version is built separately with
`make photo`.

## 2.1 How to use it

```bash
cd src/basic/verilog/ov5640

# 1) Build the photo firmware (defaults: 115200 baud / 8 rows per band)
make photo

# 2) Flash + capture (run on the Windows host; needs pyserial + numpy + pillow)
python host_capture.py --flash --baud 115200 --seconds 200
```

The host script prints progress and finally writes three files:

| File | Content |
|---|---|
| `photo.raw` | The reassembled raw YUYV (640x480x2 = 614400 bytes) |
| `photo.png` | The same image converted to RGB |
| `photo.stream` | The raw serial byte stream (for debugging) |

`--flash` first calls `icesprog.exe` to program the board (**do not use
drag-and-drop flashing**, the virtual USB stick is unreliable), then finds the
iCELink CDC port (VID_1D50 / PID_602B) and starts capturing.

Measured: **480 lines in 97 seconds, 539 packets, 0 CRC errors**.

## 2.2 Why "band scan"

One 640x480 YUYV frame is 614400 bytes, while all the BRAM of an iCE40UP5K is
only 30 x 4Kbit = 15KB — **a whole frame simply does not fit**. On top of that,
115200 baud is only 11520 bytes/second, while one image line goes by in 135 us.

So the design does a **band scan**:

* each band captures `KROWS = 8` lines (10240 bytes, 20 BRAM blocks) into an
  on-chip buffer;
* the serial port slowly ships those 8 lines out (8 x 1280 = 10240 bytes, 888 ms);
* once that band is out, the next band is captured, and **the next band starts at
  line `seg*8` of the next frame** (the camera keeps streaming; we only store the
  lines we need and drop the other frames);
* the host stitches the 60 bands into a complete picture using the row numbers.

A line has to be captured in one continuous 135 us burst (1280 bytes), while
sending one line over the serial port takes 111 ms — so **receiving and sending
at the same time is physically impossible**; a buffer is the only way out.

The band start row is re-armed at the **frame boundary (rising edge of VSYNC)**,
so the row index and the frame always stay in step and no half line or leftover
data from the previous frame is ever captured.

## 2.3 Serial protocol

One packet per line:

```
A5 5A            magic (the host uses it to re-synchronise)
row_lo row_hi    row number (little endian, 16 bit)
len_lo len_hi    length of this line's data (little endian, 16 bit, = 1280)
data[len]        raw YUYV bytes
crc_lo crc_hi    CRC16/CCITT-FALSE (poly 0x1021, init 0xFFFF)
```

* The CRC covers `row(2) + len(2) + data`; the **magic is not included**;
* Status packets use `row = 0xFFFF, len = 16` to carry telemetry (diagnostic
  code / flags / band index / lines captured so far / bytes captured so far /
  bytes in the last line). One is sent after every band, so you can see what the
  FPGA is doing;
* Right after reset a "hello beacon" status packet (diagnostic code = 3) is sent.
  As soon as the host sees it, it knows the bitstream is alive; if no data follows,
  the problem is in capture/configuration, not in the link.

## 2.4 Files of the photo mode

| File | Purpose |
|---|---|
| `top_photo.v` | Photo mode top level (PLL / IO / SCCB config / capture / packetising / state machine) |
| `top_photo.pcf` | Pin constraints (identical to `top.pcf`) |
| `dvp_linebuf.v` | DVP capture + on-chip line buffer (write port in the PCLK domain, read port in the clk24 domain) |
| `photo_tx.v` | Line buffer -> CRC-protected line packets -> serial port |
| `host_capture.py` | Host side: flash / receive / CRC check / assemble YUYV / convert to PNG |
| `tb_linebuf.v` | Offline test: synthesises a DVP stream and checks *which* lines were captured |
| `tb_photo.v` | Offline test: decodes the serial byte stream and compares it byte for byte with the host-side algorithm |
| `tb_top_photo.v` | Offline test: simulates the top level with stubbed SB_PLL40_PAD / SB_IO |
| `chk_photo.py` | The comparison script used by `tb_photo` |

Offline verification: `make sim_photo` (no hardware needed).

## 2.5 Resources and timing (measured)

| Item | Value |
|---|---|
| ICESTORM_LC | 1310 / 5280 (24%) |
| SB_RAM40_4K | 24 / 30 (80%, of which 20 are the line buffer and 4 the camera config ROM) |
| SB_GB | 8 / 8 (100%) |
| nextpnr timing | clk24 35.5 MHz / PCLK 35.5 MHz (PASS @ 24 MHz) |
| icetime | 29.36 ns (34.06 MHz) PASSED @ 24 MHz |
| Full frame time | 97 seconds (115200 baud, 60 bands) |
| Firmware | 104090 bytes from `make photo`, md5 `74fb99614a773b86300db571341254c2` (reproducible) |

## 2.6 Pitfalls of the photo mode (continuing the list above from 15)

16. **A register must not be driven by two always blocks.** In `dvp_linebuf`,
    `wr_addr_r` / `wr_data_r` were originally assigned by two always blocks;
    yosys reported `multiple conflicting drivers` and threw the entire memory
    mapping away (not a single `SB_RAM40_4K` in the JSON), and nextpnr added
    `Bram port B1 has incompatible clock type`. Verilog does not complain — it
    silently produces a wrong netlist. **Always read the yosys warnings for this
    class of problem.**

17. **Band capture must be armed at the frame boundary (rising edge of VSYNC),
    not at a line boundary.** The first version armed as soon as the next line
    boundary arrived, which broke for any band start row > 0 (say line 8): after
    arming it had to wait for line 8 of the current frame, but the frame ended
    in the meantime and VSYNC cleared `cap_en`, so the band was never captured
    and the 2-second timeout retried forever. The fix is to pend the request
    and arm it on the next VSYNC, where `line_idx = 0`, so the row index and the
    frame always stay in step.

18. **The CRC has to be reset for every row.** The CRC only covers *that row's*
    row number + length + data, but it used to be initialised to 0xFFFF only once
    per band (on `go`), so rows 2..8 of a band continued from the previous row's
    CRC remainder. On the host this looked like **"of the 8 rows in a band only
    the first one has a correct CRC"**, which looks exactly like serial data
    loss — but the FPGA was computing it wrong. Re-running the captured bytes
    with "init = previous row's CRC" reproduced it 100%, which is how it was
    found.

19. **The packet header needs the `A5 5A` magic.** The FPGA side initially
    forgot to send it, so the host could never find a sync point and not a
    single packet of a whole frame could be parsed — even though the serial line
    was full of data. If the protocol mentions a magic, the FPGA must send it.

20. **The BRAM clock enable must be tied to 1.** On the iCE40, `RCLKE`/`WCLKE` of
    `SB_RAM40_4K` are tied to the *global clock enable*. If the memory's write
    enable is mapped onto `WCLKE`, that global's enable becomes "there is a clock
    only while writing" — and the same global also drives the whole PCLK domain,
    so the entire domain gets gated. The symptom is **"the FPGA is completely
    dead, not a single byte comes out"**. The write port was therefore changed to
    "always write" (when not capturing it rewrites the same address with the
    same data, which is a no-op), which removes the write enable entirely.

21. **Toggle handshakes across clock domains need XOR edge detection.**
    `a & ~a_d` is a level test that only sees a 0->1 transition, so the second
    request (1->0) is never received — the symptom was "it hangs after
    capturing the second band".

22. **The UART receive model of a testbench has two pitfalls:**
    (a) The falling edge is the *start* of the start bit; waiting another half
        bit time from there still samples the start bit, so the whole byte comes
        out shifted by one bit (0xA5 decodes as 0x4A). The correct wait is
        **1.5 bit times**, i.e. the middle of data bit 0.
    (b) The receive model must spend **<= 10 bit times per byte** (a byte on the
        wire is 10 bits: 1 start + 8 data + 1 stop). If the model is slower than
        the wire, its phase drifts further and further away until it misses the
        falling edge of the next start bit, and **every other byte is lost**.

23. **A synthesised DVP stream must pull VSYNC low again.** Band capture is
    armed by the **rising edge** of VSYNC, so if the generator keeps VSYNC high
    there is no rising edge from the second frame onwards, the band request
    stays pend forever (watchdog timeout, `cap_en` stuck at 0).

24. **How to pick the chroma samples when decoding YUYV.** The byte order is
    `Y0 U Y1 V Y2 U Y3 V ...`: Y sits on the even positions (`a[:, 0::2]`, one per
    pixel), while U and V sit at `a[:, 1::4]` / `a[:, 3::4]` (**one sample shared
    by 2 pixels**, 320 of them). The chroma therefore has to be expanded with
    `np.repeat(..., 2)` to get one sample per pixel, otherwise the widths do not
    match. Using `a[:, 1::2]` mixes U and V together, and `a[:, 3::2]` yields only
    639 columns and numpy immediately reports a shape mismatch.

25. **Do not judge the YUYV byte alignment by "does it decode into an image"** —
    look at the **statistics of the whole frame**: being off by one byte swaps
    the roles of luma and chroma entirely. The misaligned version measured a luma
    standard deviation of only 3.8 (a dead flat picture), while the correctly
    aligned one measured 18.4 (real image structure). Both alignments were
    rendered to PNG and compared to confirm it.

26. **The ArduCAM register table mirrors the image left-to-right by default.**
    Both `OV5640YUV_Sensor_Dvp_Init` and `ov5640_vga_preview` in `ov5640_regs.h`
    contain `{ 0x3821, 0x01 }`, and ArduCAM's own comment reads
    "Sensor mirror on, ISP mirror on" — the sensor mirror and the ISP mirror are
    both enabled, the two mirrorings cancel out, and **what comes out of the
    camera is a left-right flipped picture**. The OV5640 is a BSI sensor whose
    raw readout is naturally mirrored, so the mirroring has to be corrected via
    the bits of 0x3821; `0x3821 = 0x07` (bit2 = "no mirror") is the orientation
    you actually want. With that change the config ROM goes from md5 `1cbdc7c7`
    to `d95ca008` and the firmware md5 becomes `74fb99614a773b86300db571341254c2`.
    **How to confirm the orientation**: take a picture **with a face in it** —
    if the nose points to the left of the frame and the ear is on the right side
    of the face, the orientation is correct (you are seeing that person's left
    ear); if the nose points right and the ear is on the left, the image is
    mirrored. This project was confirmed exactly that way, with a face photo.
    (The vertical direction needs no change: `0x3820 = 0x41` applies the ISP
    flip that corrects the BSI sensor's natural vertical inversion — in the face
    photo the hair is on top and the face points left, both correct.)
