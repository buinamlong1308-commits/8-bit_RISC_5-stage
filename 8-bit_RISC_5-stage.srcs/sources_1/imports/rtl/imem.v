// =====================================================================
//  FILE    : rtl/imem.v
//  MODULE  : imem         (Stage 1 - IF)
// ---------------------------------------------------------------------
//  Instruction ROM, 256 x 16 bits, asynchronous read (Harvard memory).
//
//  PROGRAM SOURCE (two layers, so Vivado works out of the box):
//    1) the demo program of sw/program.s is BUILT IN below
//       (no external file needed - Vivado cannot lose it);
//    2) if INIT_FILE is not "", $readmemh then overwrites the ROM with
//       that file. A missing file only gives a warning and the built-in
//       program stays. Files from sw/asm8.py are padded to 256 words;
//       an unpadded file leaves the built-in words after its last line.
//
//  INIT_FILE = "" : built-in program only (tb_custom fills rom[] itself).
// =====================================================================
`timescale 1ns/1ps

module imem #(
    parameter INIT_FILE = "program.hex"
) (
    input  wire [7:0]  addr,     // = PC
    output wire [15:0] instr
);

    reg [15:0] rom [0:255];
    integer    i;

    initial begin
        for (i = 0; i < 256; i = i + 1)
            rom[i] = 16'h0000;                  // NOP
        // ---- built-in demo program (generated from sw/program.s) ----
        rom[  0] = 16'h823C;   // 00: LDI  R1, 0x3C
        rom[  1] = 16'h840F;   // 01: LDI  R2, 0x0F
        rom[  2] = 16'h3650;   // 02: AND  R3, R1, R2
        rom[  3] = 16'h4850;   // 03: OR   R4, R1, R2
        rom[  4] = 16'h5AE0;   // 04: XOR  R5, R3, R4
        rom[  5] = 16'h6D40;   // 05: SHL  R6, R5
        rom[  6] = 16'h7F80;   // 06: SHR  R7, R6
        rom[  7] = 16'h2FE8;   // 07: SUB  R7, R7, R5
        rom[  8] = 16'hD00A;   // 08: BZ   skip1
        rom[  9] = 16'h8EFF;   // 09: LDI  R7, 0xFF
        rom[ 10] = 16'h8205;   // 10: LDI  R1, 5
        rom[ 11] = 16'h8400;   // 11: LDI  R2, 0
        rom[ 12] = 16'h8601;   // 12: LDI  R3, 1
        rom[ 13] = 16'h1488;   // 13: ADD  R2, R2, R1
        rom[ 14] = 16'h2258;   // 14: SUB  R1, R1, R3
        rom[ 15] = 16'hE00D;   // 15: BNZ  loop
        rom[ 16] = 16'h8820;   // 16: LDI  R4, 0x20
        rom[ 17] = 16'hB500;   // 17: ST   R2, [R4]
        rom[ 18] = 16'hAB00;   // 18: LD   R5, [R4]
        rom[ 19] = 16'h9AF0;   // 19: ADDI R5, 0xF0
        rom[ 20] = 16'h9A01;   // 20: ADDI R5, 1
        rom[ 21] = 16'hC017;   // 21: JMP  done
        rom[ 22] = 16'h8CEE;   // 22: LDI  R6, 0xEE
        rom[ 23] = 16'hF000;   // 23: HLT
        rom[ 24] = 16'h8CAA;   // 24: LDI  R6, 0xAA
        // ---- optional override from a hex file ----
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, rom);
    end

    assign instr = rom[addr];

endmodule
