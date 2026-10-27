# 8-bit RISC Processor Core with a 5-Stage Pipeline

A synthesizable 8-bit RISC CPU in Verilog-2001 with a classic **IF, ID, EX, MEM, WB** pipeline, verified with
self-checking testbenches, a random-program comparison against a reference model, and a Vivado run.

This is a custom 8-bit RISC instruction set, not RISC-V (RISC-V's smallest base is 32-bit).

> Coursework project: *Semiconductor & VLSI Industry*, FPT University. Author: Bui Nam Long.
> The architecture, the reference testbench and the software tools (`sw/`, `tb/tb_dump.v`) come from the course
> material supplied by the supervisor. The RTL in `rtl/` was rewritten for this project, and `tb/tb_custom.v` is the author's own test suite.

## Specification

| Item | Value |
|---|---|
| Data width | 8 bits |
| Instruction width | 16 bits, fixed, 16 opcodes |
| Registers | 8 x 8-bit (R0 to R7), R0 is an ordinary register |
| Memory | Harvard: 256 x 16 instruction ROM, 256 x 8 data RAM |
| Flags | Z (zero), C (carry / borrow) |
| Pipeline | IF, ID, EX, MEM, WB |
| Data hazards | Forwarding EX/MEM to EX and MEM/WB to EX, write-through bypass in the register file |
| Load-use hazard | 1-cycle stall |
| Branches | Resolved in EX, 2-cycle penalty when taken (not taken costs 0) |
| Halt | HLT stops fetch, older instructions drain, `halted` rises when HLT reaches WB |


## Repository layout

```
.
├── rtl/
│   ├── risc8_5stage_core.v   top level: PC, 4 pipeline registers, flags, branch and halt logic
│   ├── imem.v                instruction ROM (demo program built in, optional program.hex override)
│   ├── control_unit.v        opcode decoder (combinational)
│   ├── regfile.v             8 x 8 registers, 2 read ports, 1 write port, write-through bypass
│   ├── hazard_unit.v         forwarding select and load-use stall
│   ├── alu.v                 8 operations, flags Z and C
│   └── dmem.v                256 x 8 data RAM
├── tb/
│   ├── tb_risc8_5stage.v     directed test of sw/program.s (PASS / FAIL, cycle statistics)
│   ├── tb_custom.v           own suite: 43 programs, 204 checks
│   └── tb_dump.v             dumps final state for random_test.py (no PASS / FAIL)
├── sw/
│   ├── program.s             demo program (25 lines, 34 instructions executed)
│   ├── asm8.py               assembler: program.s -> program.hex
│   ├── iss.py                golden reference model (no pipeline)
│   └── random_test.py        random programs: RTL vs reference model
├── constraints/risc8.xdc     100 MHz clock constraint, optional Basys-3 pin examples (commented)
├── scripts/run_vivado.tcl    batch synthesis, implementation and reports
├── program.hex               assembled demo program
├── files.f, files_custom.f   file lists for Icarus Verilog
└── run_sim.sh, run_sim.bat   one-step simulation
```

## Tools

Xilinx Vivado 2026.1 (XSim), Icarus Verilog 12, Yosys, Python 3.
