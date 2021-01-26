# BLAKE3 VHDL
VHDL implementation of the BLAKE3 cryptographic hash function: https://github.com/BLAKE3-team/BLAKE3

Encompasses the Compression Function aspects of BLAKE3 (see: https://github.com/BLAKE3-team/BLAKE3-specs/blob/master/blake3.pdf), other aspects of the algorithm are expected to be handled by a host device. This implementation is functional but likely not optimal or performant.

Includes an AXI4-Lite peripheral controller, this has been successfully implemented onto an FPGA and tested on a Xilinx Zynq-7000 SoC.

## Contents
* `blake3.vhd` implements the BLAKE3 Compression Function.
* `axi_blake3.vhd` implements an AXI4-Lite slave controller.
* Testbenches are provide to validate basic functionality, intended for use with Xilinx Vivado and may require adaptation for other VHDL simulators.

All contents are licensed under the 3-Clause BSD license.
