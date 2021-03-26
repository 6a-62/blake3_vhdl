# BLAKE3 VHDL
VHDL implementation of the [BLAKE3 cryptographic hash function](https://github.com/BLAKE3-team/BLAKE3).

Encompasses the Compression Function aspects of BLAKE3 (see: [BLAKE3 paper](https://github.com/BLAKE3-team/BLAKE3-specs/blob/master/blake3.pdf)), other aspects of the algorithm are expected to be handled by a host device. This implementation is functional but likely not optimal or performant.

Includes an AXI4-Lite peripheral and an AXI4-Stream peripheral intended for DMA functionality, this has been successfully implemented onto an FPGA and tested on a Xilinx Zynq-7020 SoC.

## Contents
* [`blake3.vhd`](blake3.vhd) implements the BLAKE3 Compression Function.
* [`axil_blake3.vhd`](axil_blake3.vhd) implements an AXI4-Lite slave peripheral.
* [`axis_blake3.vhd`](axis_blake3.vhd) implements an AXI4-Stream peripheral.
* Testbenches are provide to validate basic functionality, intended for use with Xilinx Vivado and may require adaptation for other VHDL simulators.

All contents are licensed under the [3-Clause BSD license](LICENSE).
