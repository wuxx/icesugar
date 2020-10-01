# Courtesy of https://github.com/laanwj/yosys-ice-experiments

- Display: Digilent PmodOLED 128x32 grid SSD1306 module
- Connected to iCEstick evaluation board
- Using 4-wire SPI 10MHz max
- iCE40HX-1k FPGA, programmed using open source FPGA toolchain Yosys + Arachne-pnr + IceStorm
- Image generated using Python script, sent from PC through FTDI serial-over-USB 1000000 baud

```
+------+         +------------+        +------+      +---------+
| Host |<------->| FTDI 2232H |------->| FPGA |----->| Display |
+------+   USB   +------------+ Serial +------+ SPI  +---------+
                                1M baud         (pmod conn)
```

PmodOLED
------------

Connector Pmod

Pin   | Signal    | Description
------|-----------|---------------------------------
1     | CS        | SPI Chip Select (Slave Select)
2     | SDIN      | SPI Data In (MOSI)
3     | None      | Unused Pin
4     | SCLK      | SPI Clock
7     | D/C       | Data/Command Control
8     | RES       | Power Reset
9     | VBATC     | V BAT Battery Voltage Control
10    | VDDC      | V DD Logic Voltage Control
5, 11 | GND       |
6, 12 | VCC       | Power Supply G

Pins on FPGA
--------------

Connecting PMODoled: on module: when connector is to the left, pin 1 is at the top right.
Pin 1 is clearly indicated on the iCEstick itself.

Pin  | Signal  | Pkgpin
-----|---------|---------
1    | PIO1_02 | 78
2    | PIO1_03 | 79
3    | PIO1_04 | 80
4    | PIO1_05 | 81
5    | GND     |
6    | VCC     |
7    | PIO1_06 | 87
8    | PIO1_07 | 88
9    | PIO1_08 | 90
10   | PIO1_09 | 91
11   | GND     |
12   | VCC     |

