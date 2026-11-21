# OV5640 DVP 功能验证 (iCESugar + iCE40UP5K + PMOD-CAMERA)

> 英文版见 [`README_en.md`](README_en.md)（内容一一对应，方便国外的朋友阅读）。

在 iCESugar (iCE40UP5K-SG48I) 上驱动 PMOD-CAMERA (OV5640)。上电后自动完成
"SCCB 配置 -> 回读关键寄存器 -> 统计 1 秒 DVP 出流 -> 字节序判定"，
最后用 9600 8N1 从 UART 打印一份自检报告。

目的只有两个：**确认 SCCB 通信正常**、**确认 DVP 真的在出流**。

当前状态：**实机验证通过**（2026-11-20，报告见下方"实测结果"，
`verdict = 15` = 0b01111，五项结论全绿）。

## 硬件连接

| FPGA 引脚 | 信号 | 方向 | 说明 |
|---|---|---|---|
| 35 | clk12 | in | 板载 12MHz (iCELink MCO 经 ICE_CLK) |
| 43 | XMCLK | out | 24MHz (PLL 12->24, IOB DDR 50% 占空) |
| 44 | PCLK | in | DVP 像素时钟 (接成全局时钟) |
| 38 | VSYNC | in | DVP 场同步 |
| 42 | HREF | in | DVP 行同步 |
| 37 | SCL | bidir | SCCB 时钟 (开漏 + 内部上拉) |
| 36 | SDA | bidir | SCCB 数据 (开漏 + 内部上拉) |
| 23 / 25 / 26 / 27 / 28 / 31 / 32 / 34 | D0..D7 | in | DVP 数据 Y2..Y9 (PMOD3) |
| 6 | TX | out | UART 输出 (iCELink CDC, 9600 8N1) |
| 40 / 41 / 39 | LED_R/G/B | out | 绿=全通过, 红=有失败, 蓝=工作中 |

SCCB 两根线用开漏物理层：`SB_IO PIN_TYPE=6'b1010_01` + `D_OUT_0=0` +
`OUTPUT_ENABLE=*_low` + `PULLUP=1`，由 FPGA 拉低、从机/上拉释放。

引脚依据 `src/common/io.pcf` 与 `schematic/pmod-camera-v1.0.pdf` 核对。

## 构建

```
make                # 默认 FPS=15 (0x3035=0x21 -> PCLK 28MHz)
make FPS=30         # 0x3035=0x11 -> PCLK 56MHz
make sim            # 离线仿真报表展开(iverilog, 不需要硬件)
```

需要 yosys / nextpnr-ice40 / icetime / icepack。`ov5640_cfg.hex` 与 `text.hex`
由 `gen_cfg_hex.py` / `gen_text_hex.py` 自动生成，不需要手工维护。

资源占用与时序 (up5k / sg48, yosys 0.9 + nextpnr + icetime):

| 项 | 用量 |
|---|---|
| SB_LUT4 | 3420 |
| 触发器 | 2251 |
| SB_CARRY | 1244 |
| SB_RAM40_4K | 8 (配置 ROM 1 + 文本模板 4 + 其他 3) |
| icetime | 36.44 ns / 27.44 MHz **PASSED** (约束 24 MHz) |
| nextpnr | clk24 26.74 MHz / PCLK 31.52 MHz，均 PASS |
| top.bin | 104090 字节 |

## 烧录与看结果

iCELink 的 HID 命令行工具：

```
../../../tools/src/icesprog top.bin
```

**顺序很重要**：本设计跑一次测量就停在 ST_DONE，不会自己重跑。
所以要先烧录（烧录会让 DAPLink 复位目标，FPGA 重新开始测量），
再开串口收数 —— 复位后大约 8 秒才开始打印。

Windows 侧建议用 pyserial 紧密循环收，**不要用 PowerShell 的
`System.IO.Ports.SerialPort.Read`**（它每次调用会阻塞满 ReadTimeout，
9600bps 下会成片丢数据，实测只能收到 283 字节）：

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

## 实测结果 (2026-11-20, iCESugar + PMOD-CAMERA)

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

结论:

- **SCCB 正常**: 芯片 ID 0x56/0x40 读回正确；271 个寄存器写全部有应答；
  12 个关键寄存器全部读回正确值；**0x38xx 输出窗口/时序寄存器 8 个全部读对**
  (0x3808=0x02 / 0x3809=0x80 -> 640；0x380A=0x01 / 0x380B=0xE0 -> 480；
  HTS=0x0768 / VTS=0x03D8)。地址探测只有 0x78 有应答 (mask=0x01)，
  说明总线上只有相机一个从机。SCL/SDA 上拉正常、引脚自检通过、
  应答窗口内 SCL 回读零异常。
- **DVP 出流正常**: PCLK 28MHz；每帧 480 行；每行 1279 字节 (640 像素 x
  YUV422 2 字节/像素 = 1280，减 1 是行首那一拍)；8 根数据线全在跳变
  (changed=0xFF)；采样字节范围 0x16..0x91。
- **字节序**: "色度在奇数字节位 + 正常位序" 的指标最小 (146461，比其它三个
  假设小 14 倍以上)，即 Y,U,Y,V 交替，和 0x4300=0x30 (YUYV) 一致。
- **行/帧时序**: 行周期 3791 个 PCLK 周期 = 2 x HTS(0x0768=1896)，完全对得上；
  帧周期 11374103 周期 ≈ 0.406 秒，也就是实测帧率约 2.5fps 而不是寄存器
  算出来的 15fps，**这是 OV5640 自动曝光把帧间隔拉长(垂直消隐加大)的结果，
  不是 FPGA 侧的问题** —— 行时间与 HTS 严格一致就是证据。
  (相机在强光下会自己降帧，不同光照下实测在 2~6fps 之间浮动，
  所以 `dvp link` 的判据是 frames >= 2 而不是 >= 5。)

## 文件

| 文件 | 作用 |
|---|---|
| `top.v` | 顶层: 复位/PLL/引脚 IO/主状态机/报表 |
| `sccb_master.v` | SCCB 主机 (开漏物理层 + 应答检测 + 引脚自检) |
| `ov5640_cfg.v` | 271 个寄存器的配置序列 (ROM 里只有写操作) |
| `dvp_capture.v` | DVP 采集/统计/字节序判定 (PCLK 时钟域) |
| `uart_tx.v` | 9600 8N1 串口发送 |
| `uart_printer.v` | 文本模板解释器 (text.hex) |
| `tb_printer.v` | uart_printer 的 iverilog 测试台 (离线验证报表展开) |
| `gen_cfg_hex.py` | 从 `ov5640_regs.h` 生成配置 ROM |
| `gen_text_hex.py` | 生成报表文本模板 |
| `ov5640_regs.h` | OV5640 寄存器表 (ArduCAM 版) |

## 踩过的坑 (留给后来人)

1. **SCCB 的 SCL 低电平期必须等满半位周期**。第一版把"准备相位(SCL 低)"
   写成只等 1 个系统时钟，于是 SCL 低脉冲只有 42ns，从机识别不出 SCL 的
   下降沿，**永远不会回 ACK** (现象：acks=0、failed=全部)。改成等满
   HALF 拍之后一次就通了。位时序必须是
   `相0: SCL 低 + 放数据 (等 HALF 拍) / 相1: SCL 高 (等 HALF 拍, 中点采样)`。
2. **同一块寄存器不能被两个 always 块驱动**。自检标志 `sda_pin_ok` /
   `scl_pin_ok` / `scl_mismatch_cnt` 一开始在独立 always 块里复位、在主
   状态机里赋值，结果值永远停在复位值 (自检永远 FAIL)。Verilog 不会报错，
   但综合结果是不确定的。
3. **16 位计数器做 4,800,000 的上电延时**会溢出，条件永远不成立。
4. **复位计数器必须饱和**，16 位自由自增会每 65536 拍 (2.73ms) 回绕一次，
   `rst_n` 就被反复拉低，设计永远走不到打印阶段。
5. **报表变量别都用寄存器存**。57 个 32bit 变量 = 1824 个 FF，UP5K 只有
   5280 个 LC，nextpnr 直接报 `Failed to expand region`。改成组合连线直接
   指向源信号(配置结果寄存器 / 冻结后的快照 / 只增计数器)，0 个 FF。
6. **同一 always 块里后面的赋值会覆盖前面的**：原来 `line_bytes <= 0` 写在
   HREF 上升沿分支里，而后面无条件又写了 `line_bytes <= line_bytes + 1`，
   复位被覆盖，"每行字节数" 变成了 16 位自由回绕计数器的随机值。
7. **冻结快照后要停止统计**。否则快照里的"帧数"会被冻结之后继续来的
   VSYNC 覆盖掉 (报表里 vsync=18 而 frames=6 就是这么来的)。
8. **写操作要有超时**。相机没接 / 没应答时，状态机会永远卡在等待握手的地方，
   一条字节都发不出来。加上超时后带着已有数据继续跑，报表里就能看出
   "哪一级是空的"。
9. **串口十进制转换的位序**：`dec_dig[k]` 是 10^k 位，输出要从最高位往下打，
   `emit_idx` 从 0 计、取 `dec_dig[dec_start - emit_idx]`；另外报表变量的
   索引要留 6 位，否则 v32 以上的变量取不到 (5 位时打印出来全是别的值)。
10. **0x38xx 组(输出窗口/时序寄存器)必须排在诊断读的最后**。
    0x300A / 0x300B / 0x4300 / 0x3017 任何时候都读得对；0x38xx 组排在前面
    一律读回 0x00，排在最后 8 个槽位就 8 个全对 (nonzero=8/8)。
    试过并排除的假设：读方式 (Sr vs STOP+START 都一样)、双读、cfg 阶段回读、
    300ms settle、两轮读 + 间隔、`rd_addr()` 函数 vs 字面量地址、ST_WAITV
    等待时长。**最后是靠"重排诊断读顺序"解决的**。
11. **hex32 打印的 nibble 取法**。原来写的是
    `emit_val[31 - {emit_idx[1:0], 2'b00}]`，`emit_idx` 只用了 2 位，
    8 个 nibble 只有 4 个不同位置、循环打印两遍 —— 所有小于 0x10000 的值
    (HTS / VTS / 640x480) 全都显示成 `00000000`，看起来像"没读到"。
    改成用 32 位移位寄存器 `hex32_sr`，每发一个 nibble 左移 4 位。
12. **十进制转换的"最高非零位"优先编码链会拖垮时序**。
    `dec_start` 是在 9 个 `dec_dig[i] != 0` 上串出来的 4 级 LUT，
    后面还要接"按 dec_start 选位 + 加 0x30 + 进串口移位寄存器"，
    整条关键路径 42.1ns > 41.67ns，nextpnr 直接报 FAIL。
    解法：在 `S_DEC4` 拍先把 `dec_start` 寄存到 `dec_start_r`，发射时只用
    寄存器值 (改完 clk24 从 23.7MHz 回到 26.7MHz)。
13. **文本模板长度必须 <= 文本 ROM 容量**。模板涨到 1349 字节而 ROM 还是
    1024 字节时，`tpos` 会回绕，终止符 0x00 永远读不到，报表从头无限重复
    (一次抓取里能看到 30 多段重复内容)。ROM 扩到 2048 字节
    (`reg [7:0] trom [0:2047]` + `tpos` 改成 11 位) 之后报表才完整。
14. **别用 PowerShell 的 `SerialPort.Read` 抓串口**。它每次调用会阻塞到
    ReadTimeout，9600bps 下等于成片丢数据，实测只能收到 283 字节，
    看起来像"FPGA 打印到一半停了"。换 pyserial 紧密循环后一次拿到
    1414 字节完整报告。**排查这类问题时，先怀疑上位机，再怀疑 RTL。**
15. **拿不准 RTL 有没有问题，就写 testbench**。`tb_printer.v` 用 iverilog
    把真实的 `text.hex` 跑一遍，能离线确认模板展开逻辑和终止符处理
    (本例中它证明 RTL 是好的，问题出在上位机)。

## 附: 各寄存器在诊断读中的顺序

诊断读共 12 次，顺序固定（顺序有讲究，见坑 10）：

| 槽位 | 寄存器 | 内容 | 期望值 |
|---|---|---|---|
| 0 | 0x300A | 芯片 ID 高字节 | 0x56 |
| 1 | 0x300B | 芯片 ID 低字节 | 0x40 |
| 2 | 0x4300 | 输出格式 | 0x30 (YUYV) |
| 3 | 0x3017 | DVP 输出使能 | 0x7F |
| 4..7 | 0x3808..0x380B | 输出窗口 (宽/高) | 02 80 01 E0 |
| 8..11 | 0x380C..0x380F | HTS / VTS | 07 68 03 D8 |

---

# 拍照模式 (`top_photo`) —— 相机 → 串口 → 主机端 PNG

`top.v` 是"功能自检"：配置相机、统计 DVP 字节、打印一份诊断报表。
`top_photo` 是"拍照"：把相机看到的图像原样通过串口送出去，主机端拼成 PNG。

两个入口互不影响，默认流程 (`make`) 仍然是自检版；拍照版单独用 `make photo` 构建。

## 2.1 怎么用

```bash
cd src/basic/verilog/ov5640

# 1) 构建拍照固件 (默认 115200 波特率 / 每段 8 行)
make photo

# 2) 烧录 + 收图 (在 Windows 主机上跑, 需要 pyserial + numpy + pillow)
python host_capture.py --flash --baud 115200 --seconds 200
```

主机端会打印进度，最后写出三个文件：

| 文件 | 内容 |
|---|---|
| `photo.raw` | 拼好的原始 YUYV (640x480x2 = 614400 字节) |
| `photo.png` | 转成 RGB 的 PNG |
| `photo.stream` | 原始串口字节流 (排查用) |

`--flash` 会先调 `icesprog.exe` 烧录（**不要用拖拽烧录**，虚拟 U 盘不可靠），
然后自动找 iCELink 的 CDC 串口 (VID_1D50 / PID_602B) 收数据。

实测：**97 秒收满 480 行，539 个包，0 个 CRC 错误**。

## 2.2 为什么要"分段扫描"

640x480 YUYV 一帧 = 614400 字节，而 iCE40UP5K 全部 BRAM 只有 30 x 4Kbit = 15KB，
**整帧根本存不下**，而且串口 115200 只有 11520 字节/秒，相机一行数据 135us 就过去了。

所以改成"分段扫描"（band scan）：

* 每段采 `KROWS = 8` 行（10240 字节，20 个 BRAM 块）存进片上缓冲；
* 串口慢慢把这 8 行发出去（8 x 1280 = 10240 字节，888ms）；
* 发完再采下一段，**下一段从下一帧的行 `seg*8` 开始采**（相机一直在出流，
  我们只在需要的那几行存数据，其余帧丢掉）；
* 主机端按行号把 60 段拼成一整幅图。

一行必须在 135us 内连续采完（一行 1280 字节），所以串口发一行要 111ms，
**不可能边收边发**，缓冲是唯一出路。

段起始行号在**帧边界（VSYNC 上升沿）**重新武装，这样行号和帧永远对得上，
不会采到半行或者上一帧的残留。

## 2.3 串口协议

每行一个包：

```
A5 5A            magic (主机端靠它重新同步)
row_lo row_hi    行号 (小端, 16 位)
len_lo len_hi    本行数据长度 (小端, 16 位, = 1280)
data[len]        原始 YUYV 字节
crc_lo crc_hi    CRC16/CCITT-FALSE (poly 0x1021, init 0xFFFF)
```

* CRC 覆盖范围 = `行号(2) + 长度(2) + 数据`，**不含 magic**；
* 状态包用 `row = 0xFFFF, len = 16` 承载遥测（诊断码 / flags / 段号 /
  已采行数 / 已采字节数 / 末行字节数），每段之后发一个，方便看 FPGA 在干什么；
* 复位后立刻发一个"上电信标"状态包（诊断码 = 3），
  主机端一收到它就知道比特流跑起来了，后面没数据就是采集/配置问题，不是链路问题。

## 2.4 拍照模式的文件

| 文件 | 作用 |
|---|---|
| `top_photo.v` | 拍照模式顶层 (PLL / IO / SCCB 配置 / 采集 / 打包 / 状态机) |
| `top_photo.pcf` | 引脚约束 (和 `top.pcf` 完全一致) |
| `dvp_linebuf.v` | DVP 采集 + 片上行缓冲 (写口 PCLK 域, 读口 clk24 域) |
| `photo_tx.v` | 行缓冲 → 带 CRC 的行包 → 串口 |
| `host_capture.py` | 主机端: 烧录 / 收包 / CRC 校验 / 拼 YUYV / 转 PNG |
| `tb_linebuf.v` | 离线验证: 合成 DVP 流, 检查"到底抓到了哪几行" |
| `tb_photo.v` | 离线验证: 把串口字节流还原出来, 和主机端算法逐字节比对 |
| `tb_top_photo.v` | 离线验证: 桩件替掉 SB_PLL40_PAD/SB_IO, 直接仿真顶层 |
| `chk_photo.py` | `tb_photo` 的比对脚本 |

离线验证：`make sim_photo`（不需要硬件）。

## 2.5 资源与时序（实测）

| 项 | 值 |
|---|---|
| ICESTORM_LC | 1310 / 5280 (24%) |
| SB_RAM40_4K | 24 / 30 (80%，其中 20 个是行缓冲, 4 个是相机配置 ROM) |
| SB_GB | 8 / 8 (100%) |
| nextpnr 时序 | clk24 35.5 MHz / PCLK 35.5 MHz (PASS @ 24 MHz) |
| icetime | 29.36 ns (34.06 MHz) PASSED @ 24 MHz |
| 整帧时间 | 97 秒 (115200 baud, 60 段) |
| 固件 | `make photo` 产物 104090 字节, md5 `74fb99614a773b86300db571341254c2` (可复现) |

## 2.6 拍照模式踩过的坑（接着上面第 15 条往下数）

16. **同一个寄存器不能被两个 always 块驱动**。`dvp_linebuf` 里 `wr_addr_r` /
    `wr_data_r` 一开始被两个 always 块赋值，yosys 报
    `multiple conflicting drivers` 并把整个内存映射废掉（JSON 里一个
    `SB_RAM40_4K` 都没有），nextpnr 还会报
    `Bram port B1 has incompatible clock type`。Verilog 不会报错，
    只会安静地生成一个错的网表 —— **这类问题一定要看 yosys 的 warning**。

17. **段采集必须在帧边界（VSYNC 上升沿）武装，不能在行边界武装**。
    最初是"请求到了就等下一个行边界武装"，结果段起始行号 > 0 时
    （比如要第 8 行），armed 之后要一直等到本帧的第 8 行 ——
    可是等的过程中帧又结束了，VSYNC 把 `cap_en` 清掉，
    段永远采不到，2 秒超时重试死循环。改成"请求 pend 住，
    等下一个 VSYNC 才武装，此时 line_idx = 0"，行号和帧永远对得上。

18. **CRC 必须每行复位**。CRC 只覆盖"本行"的行号+长度+数据，
    之前只在段起始（`go`）初始化了一次 0xFFFF，同一段的第 2~8 行
    就接着上一行的 CRC 余数继续算 —— 主机端表现为
    **"每段 8 行里只有第 1 行 CRC 对，其余全错"**，
    看起来像串口丢数据，其实是 FPGA 自己算错了。
    抓包脚本按"init=上一行 CRC"重算一遍能 100% 复现，才定位到。

19. **包头必须有 magic `A5 5A`**。FPGA 侧一开始漏发了魔数，
    主机端找不到同步点，于是一帧数据一个包都解析不出来 ——
    但串口上明明有数据。协议里写了魔数就一定要发。

20. **BRAM 的时钟使能必须恒为 1**。iCE40 的 `SB_RAM40_4K` 上
    `RCLKE/WCLKE` 接的是"全局时钟使能"，如果内存的写使能被映射到
    `WCLKE`，这个全局的使能就变成"只有写的时候才有时钟" ——
    而同一个全局还驱动着整个 pclk 时钟域，于是整个域被门控，
    表现为 **"FPGA 整机不动，一个字节都发不出来"**。
    写口因此改成"总是写"（不采的时候重复写同一个地址/同一个数据，
    写上去的值和原来一样，没有副作用），把写使能彻底消掉。

21. **toggle 跨域信号必须用 XOR 做边沿检测**。`a & ~a_d` 是电平检测，
    只能认出 0→1 的跳变，第 2 次请求（1→0）永远收不到 ——
    表现为"采到第 2 段就卡死"。

22. **testbench 的 UART 接收模型有两个坑**：
    (a) 下降沿是起始位的前沿，从那里再等**半个**位时间采到的还是起始位，
        整个字节会**整体错一位**（0xA5 被解成 0x4A）；正确是等 **1.5** 个位时间，
        即第 0 个数据位的正中间。
    (b) 接收模型每个字节的耗时必须 **<= 10 个位时间**（线上一个字节就是 10 位：
        起始 1 + 数据 8 + 停止 1）。如果模型比线上慢，相位会越飘越远，
        最后错过下一个起始位的下降沿，**隔一个字节丢一个**。

23. **合成 DVP 流时 VSYNC 必须拉回低**。段采集靠 VSYNC **上升沿**武装，
    合成器如果让 VSYNC 一直保持高，第二帧之后就没有上升沿了，
    段请求永远 pend 住（看门狗超时，`cap_en` 一直是 0）。

24. **YUYV 解码的取法**。字节序是 `Y0 U Y1 V Y2 U Y3 V ...`：
    Y 在偶数位（`a[:, 0::2]`，每像素一个），
    U/V 在 `a[:, 1::4]` / `a[:, 3::4]`（**每 2 个像素共享一个采样**，320 个），
    所以 U/V 取出来要用 `np.repeat(..., 2)` 复制回每像素一个，否则宽度对不上。
    用 `a[:, 1::2]` 会把 U/V 混在一起，而且 `a[:, 3::2]` 只有 639 列直接报 shape 不匹配。

25. **判断 YUYV 字节对齐不能只看"能不能解出图"**，要看**整帧的统计量**：
    对齐错 1 字节的话，luma 和 chroma 的角色会整体对调 ——
    实测错位那版 luma 标准差只有 3.8（几乎一片死板），
    对齐正确那版是 18.4（有真正的图像结构）。
    最终两种对齐都渲染成 PNG 对比才确认。

26. **ArduCAM 的寄存器表默认把画面左右镜像了**。`ov5640_regs.h` 里
    `OV5640YUV_Sensor_Dvp_Init` 和 `ov5640_vga_preview` 两个数组都写着
    `{ 0x3821, 0x01 }`，ArduCAM 自己的注释是
    "Sensor mirror on, ISP mirror on" —— 传感器镜像和 ISP 镜像同时打开，
    两次镜像互相抵消，**输出的就是一张左右翻转的图**。
    OV5640 是 BSI 传感器，原始读出天然左右相反，必须靠 0x3821 的镜像位纠正；
    `0x3821 = 0x07`（bit2 = 不镜像）才是正常方向。
    改完之后配置 ROM 从 md5 `1cbdc7c7` 变成 `d95ca008`，固件 md5 变成 `74fb99614a773b86300db571341254c2`。
    **怎么确认方向对不对**：让相机拍一张**有人脸**的照片 ——
    鼻子朝画面左边、耳朵在脸的右边，就是正常方向（看到的是他/她的左耳）；
    如果鼻子朝右、耳朵在左，就是被镜像了。本工程最后就是靠这张人脸照片确认的。
    （上下方向不用动：`0x3820 = 0x41` 的 ISP 翻转正好把 BSI 传感器天然的上下倒置纠正回来，
    人脸照片里头在上、脸朝左，方向都对。）
