# flash_icesugar

In this directory, the user can compile and test using either `apio` (in which case, they can also output the simulation files), or with the standard Lattice OS toolchain

When compiled, the user should observe that the `MISO` line responds with the Manufacturer ID - hex `EF` (as noted in the W25Q64F flash [docs](https://www.pjrc.com/store/w25q64fv.pdf) in section 6.2.30), followed by the Device ID

This directory is tested and verified as working on the `icesugar v1.5`
