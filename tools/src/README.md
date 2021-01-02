# iCELink Tips
## GPIO control
```
$icesprog --gpio PB14 --mode out
$icesprog --gpio PB14 --write 0
$icesprog --gpio PB14 --write 1
$icesprog --gpio PB14 --read
```

## JTAG select (available on iCESugar-pro)
```
$icesprog --jtag-sel ?
$icesprog --jtag-sel 1
$icesprog --jtag-sel 2
```

## MCO config (available on iCESugar-nano)
```
$icesprog --clk-sel ?
$icesprog --clk-sel 1
$icesprog --clk-sel 2
$icesprog --clk-sel 3
$icesprog --clk-sel 4
```
