// =====================================================================
//  FILE    : rtl/alu.v
//  MODULE  : alu          (Stage 3 - EX, purely combinational)
// ---------------------------------------------------------------------
//  y = result, c = carry/borrow/shifted-out bit, z = (y == 0)
//
//  alu_op : 0 ADD   1 SUB   2 AND   3 OR   4 XOR   5 SHL   6 SHR   7 PASS B
//
//  CARRY CONVENTION (must match sw/iss.py)
//    ADD : c = 1 when the 9-bit sum overflows 8 bits
//    SUB : c = 1 when a < b  (a BORROW happened)
//    SHL : c = old bit 7        SHR : c = old bit 0
//    logic / PASS : c = 0
// =====================================================================
`timescale 1ns/1ps

module alu (
    input  wire [7:0] a,        // operand A (after forwarding)
    input  wire [7:0] b,        // operand B (register value or imm8)
    input  wire [2:0] alu_op,   // operation select (control_unit)
    output reg  [7:0] y,        // 8-bit result
    output reg        c,        // carry / borrow / shifted-out bit
    output wire       z         // 1 when y == 0
);

    localparam OP_ADD   = 3'd0,
               OP_SUB   = 3'd1,
               OP_AND   = 3'd2,
               OP_OR    = 3'd3,
               OP_XOR   = 3'd4,
               OP_SHL   = 3'd5,
               OP_SHR   = 3'd6,
               OP_PASSB = 3'd7;

    // 9-bit results: bit 8 is the carry (ADD) or the borrow (SUB)
    wire [8:0] sum  = {1'b0, a} + {1'b0, b};
    wire [8:0] diff = {1'b0, a} - {1'b0, b};

    always @(*) begin
        // defaults first: every output is assigned in every path (no latch)
        y = 8'h00;
        c = 1'b0;
        case (alu_op)
            OP_ADD  : {c, y} = sum;
            OP_SUB  : {c, y} = diff;
            OP_AND  : y = a & b;
            OP_OR   : y = a | b;
            OP_XOR  : y = a ^ b;
            OP_SHL  : begin y = {a[6:0], 1'b0}; c = a[7]; end
            OP_SHR  : begin y = {1'b0, a[7:1]}; c = a[0]; end
            OP_PASSB: y = b;
            default : begin y = 8'h00; c = 1'b0; end
        endcase
    end

    assign z = (y == 8'h00);

endmodule
