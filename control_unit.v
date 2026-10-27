// =====================================================================
//  FILE    : rtl/control_unit.v
//  MODULE  : control_unit (Stage 2 - ID, combinational decoder)
// ---------------------------------------------------------------------
//  Opcode map (must match sw/asm8.py):
//    0 NOP  1 ADD  2 SUB  3 AND  4 OR   5 XOR  6 SHL  7 SHR
//    8 LDI  9 ADDI A LD   B ST   C JMP  D BZ   E BNZ  F HLT
//
//  Signals travel down the pipeline with the instruction:
//    EX : alu_op alu_src_imm flag_we jump br_z br_nz halt
//    MEM: mem_we mem_to_reg            WB : reg_we
//  uses_a / uses_b tell the hazard unit which read ports are real.
// =====================================================================
`timescale 1ns/1ps

module control_unit (
    input  wire [3:0] opcode,
    output reg  [2:0] alu_op,
    output reg        alu_src_imm,   // 1: ALU B = imm8
    output reg        ra_is_rd,      // 1: read port A reads rd   (ADDI)
    output reg        rb_is_rd,      // 1: read port B reads rd   (ST data)
    output reg        uses_a,
    output reg        uses_b,
    output reg        reg_we,
    output reg        mem_to_reg,    // 1: write-back value comes from memory
    output reg        mem_we,
    output reg        flag_we,
    output reg        jump,
    output reg        br_z,
    output reg        br_nz,
    output reg        halt
);

    localparam OP_NOP  = 4'h0, OP_ADD = 4'h1, OP_SUB = 4'h2, OP_AND = 4'h3,
               OP_OR   = 4'h4, OP_XOR = 4'h5, OP_SHL = 4'h6, OP_SHR = 4'h7,
               OP_LDI  = 4'h8, OP_ADDI= 4'h9, OP_LD  = 4'hA, OP_ST  = 4'hB,
               OP_JMP  = 4'hC, OP_BZ  = 4'hD, OP_BNZ = 4'hE, OP_HLT = 4'hF;

    always @(*) begin
        // ---- defaults: NOP (also prevents latches) ----
        alu_op      = 3'd0;
        alu_src_imm = 1'b0;
        ra_is_rd    = 1'b0;
        rb_is_rd    = 1'b0;
        uses_a      = 1'b0;
        uses_b      = 1'b0;
        reg_we      = 1'b0;
        mem_to_reg  = 1'b0;
        mem_we      = 1'b0;
        flag_we     = 1'b0;
        jump        = 1'b0;
        br_z        = 1'b0;
        br_nz       = 1'b0;
        halt        = 1'b0;

        case (opcode)
            // rd = rs1 op rs2
            OP_ADD : begin alu_op = 3'd0; uses_a = 1'b1; uses_b = 1'b1; reg_we = 1'b1; flag_we = 1'b1; end
            OP_SUB : begin alu_op = 3'd1; uses_a = 1'b1; uses_b = 1'b1; reg_we = 1'b1; flag_we = 1'b1; end
            OP_AND : begin alu_op = 3'd2; uses_a = 1'b1; uses_b = 1'b1; reg_we = 1'b1; flag_we = 1'b1; end
            OP_OR  : begin alu_op = 3'd3; uses_a = 1'b1; uses_b = 1'b1; reg_we = 1'b1; flag_we = 1'b1; end
            OP_XOR : begin alu_op = 3'd4; uses_a = 1'b1; uses_b = 1'b1; reg_we = 1'b1; flag_we = 1'b1; end
            // rd = rs1 << 1 , rd = rs1 >> 1
            OP_SHL : begin alu_op = 3'd5; uses_a = 1'b1; reg_we = 1'b1; flag_we = 1'b1; end
            OP_SHR : begin alu_op = 3'd6; uses_a = 1'b1; reg_we = 1'b1; flag_we = 1'b1; end
            // rd = imm8 (flags unchanged)
            OP_LDI : begin alu_op = 3'd7; alu_src_imm = 1'b1; reg_we = 1'b1; end
            // rd = rd + imm8
            OP_ADDI: begin alu_op = 3'd0; alu_src_imm = 1'b1; ra_is_rd = 1'b1; uses_a = 1'b1;
                           reg_we = 1'b1; flag_we = 1'b1; end
            // rd = mem[rs1]
            OP_LD  : begin uses_a = 1'b1; reg_we = 1'b1; mem_to_reg = 1'b1; end
            // mem[rs1] = rd
            OP_ST  : begin uses_a = 1'b1; uses_b = 1'b1; rb_is_rd = 1'b1; mem_we = 1'b1; end
            // control flow (target = imm8 field)
            OP_JMP : jump  = 1'b1;
            OP_BZ  : br_z  = 1'b1;
            OP_BNZ : br_nz = 1'b1;
            OP_HLT : halt  = 1'b1;
            default: ;     // OP_NOP: keep defaults
        endcase
    end

endmodule
