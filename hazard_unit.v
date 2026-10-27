// =====================================================================
//  FILE    : rtl/hazard_unit.v
//  MODULE  : hazard_unit  (combinational)
// ---------------------------------------------------------------------
//  1) FORWARDING into EX (select codes):
//       2'b10 : value from EX/MEM  (producer is 1 instruction ahead)
//       2'b01 : value from MEM/WB  (producer is 2 instructions ahead)
//       2'b00 : value read in ID   (producer 3+ ahead; regfile bypass)
//     EX/MEM has priority (it holds the NEWER value).
//     A load in MEM is not forwarded (its data is not ready) - the
//     load-use stall below makes sure that case never reaches EX.
//
//  2) LOAD-USE STALL: LD in EX and the instruction in ID reads LD's rd
//     -> freeze PC and IF/ID one cycle, insert a bubble into ID/EX.
// =====================================================================
`timescale 1ns/1ps

module hazard_unit (
    // instruction in ID
    input  wire       id_valid,
    input  wire [2:0] id_ra_addr,
    input  wire [2:0] id_rb_addr,
    input  wire       id_uses_a,
    input  wire       id_uses_b,
    // instruction in EX
    input  wire       ex_valid,
    input  wire       ex_mem_to_reg,
    input  wire [2:0] ex_rd,
    input  wire [2:0] ex_ra_addr,
    input  wire [2:0] ex_rb_addr,
    input  wire       ex_uses_a,
    input  wire       ex_uses_b,
    // instruction in MEM
    input  wire       mem_reg_we,
    input  wire       mem_mem_to_reg,
    input  wire [2:0] mem_rd,
    // instruction in WB
    input  wire       wb_reg_we,
    input  wire [2:0] wb_rd,
    // results
    output reg  [1:0] fwd_a_sel,
    output reg  [1:0] fwd_b_sel,
    output wire       stall
);

    // EX/MEM can supply a value only if it will write a register and is not a load
    wire mem_can_fwd = mem_reg_we && !mem_mem_to_reg;

    always @(*) begin
        fwd_a_sel = 2'b00;
        if      (ex_uses_a && mem_can_fwd && (mem_rd == ex_ra_addr)) fwd_a_sel = 2'b10;
        else if (ex_uses_a && wb_reg_we   && (wb_rd  == ex_ra_addr)) fwd_a_sel = 2'b01;
    end

    always @(*) begin
        fwd_b_sel = 2'b00;
        if      (ex_uses_b && mem_can_fwd && (mem_rd == ex_rb_addr)) fwd_b_sel = 2'b10;
        else if (ex_uses_b && wb_reg_we   && (wb_rd  == ex_rb_addr)) fwd_b_sel = 2'b01;
    end

    wire hit_a = id_uses_a && (id_ra_addr == ex_rd);
    wire hit_b = id_uses_b && (id_rb_addr == ex_rd);

    assign stall = id_valid && ex_valid && ex_mem_to_reg && (hit_a || hit_b);

endmodule
