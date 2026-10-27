// =====================================================================
//  FILE    : rtl/risc8_5stage_core.v
//  MODULE  : risc8_5stage_core   (TOP LEVEL)
// ---------------------------------------------------------------------
//  8-bit RISC CPU, 5-stage pipeline:  IF -> ID -> EX -> MEM -> WB
//
//  Pipeline registers : IF/ID (ifid_*)  ID/EX (idex_*)
//                       EX/MEM (exmem_*) MEM/WB (memwb_*)
//
//  Hazards
//    data (RAW)   : forwarding EX/MEM->EX and MEM/WB->EX (hazard_unit)
//                   + write-through bypass in regfile
//    load-use     : 1-cycle stall (hazard_unit)
//    control      : branch/jump resolved in EX, the 2 younger
//                   instructions are flushed (2-cycle penalty)
//    HLT          : at EX stop fetching; older instructions drain
//                   through MEM/WB; 'halted' = 1 when HLT reaches WB
//
//  Priority for PC / IF-ID :  branch flush > halt > stall > normal
//
//  Naming: if_ id_ ex_ mem_ wb_ = stage      ifid_ idex_ exmem_ memwb_ = register
// =====================================================================
`timescale 1ns/1ps

module risc8_5stage_core #(
    parameter IMEM_FILE = "program.hex"
) (
    input  wire       clk,
    input  wire       rst,          // synchronous, active high
    output reg        halted,       // 1 after HLT has left the pipeline
    output wire [7:0] pc_out,       // debug: PC
    output wire [1:0] flags_out,    // debug: {Z, C}
    output wire       instr_done    // debug: a valid instruction is in WB
);

    // =================================================================
    //  State (all registers declared first)
    // =================================================================
    reg  [7:0]  pc;

    // IF/ID
    reg  [15:0] ifid_instr;
    reg         ifid_valid;

    // ID/EX
    reg         idex_valid;
    reg  [2:0]  idex_alu_op;
    reg         idex_alu_src_imm, idex_uses_a, idex_uses_b;
    reg         idex_reg_we, idex_mem_to_reg, idex_mem_we, idex_flag_we;
    reg         idex_jump, idex_br_z, idex_br_nz, idex_halt;
    reg  [2:0]  idex_rd, idex_ra_addr, idex_rb_addr;
    reg  [7:0]  idex_ra_data, idex_rb_data, idex_imm;

    // EX/MEM
    reg         exmem_valid;
    reg         exmem_reg_we, exmem_mem_to_reg, exmem_mem_we, exmem_halt;
    reg  [2:0]  exmem_rd;
    reg  [7:0]  exmem_alu_y;         // ALU result
    reg  [7:0]  exmem_addr;          // memory address  = R[rs1]
    reg  [7:0]  exmem_store_data;    // data to store   = R[rd]

    // MEM/WB
    reg         memwb_valid, memwb_reg_we, memwb_halt;
    reg  [2:0]  memwb_rd;
    reg  [7:0]  memwb_data;

    // flags and halt control
    reg         flag_z, flag_c;
    reg         draining;            // HLT has been seen in EX

    // =================================================================
    //  STAGE 1 : IF
    // =================================================================
    wire [15:0] if_instr;

    imem #(.INIT_FILE(IMEM_FILE)) u_imem (
        .addr  (pc),
        .instr (if_instr)
    );

    // =================================================================
    //  STAGE 2 : ID
    // =================================================================
    wire [3:0] id_opcode = ifid_instr[15:12];
    wire [2:0] id_rd     = ifid_instr[11:9];
    wire [2:0] id_rs1    = ifid_instr[8:6];
    wire [2:0] id_rs2    = ifid_instr[5:3];
    wire [7:0] id_imm8   = ifid_instr[7:0];

    wire [2:0] id_alu_op;
    wire       id_alu_src_imm, id_ra_is_rd, id_rb_is_rd, id_uses_a, id_uses_b;
    wire       id_reg_we, id_mem_to_reg, id_mem_we, id_flag_we;
    wire       id_jump, id_br_z, id_br_nz, id_halt;

    control_unit u_ctrl (
        .opcode      (id_opcode),
        .alu_op      (id_alu_op),
        .alu_src_imm (id_alu_src_imm),
        .ra_is_rd    (id_ra_is_rd),
        .rb_is_rd    (id_rb_is_rd),
        .uses_a      (id_uses_a),
        .uses_b      (id_uses_b),
        .reg_we      (id_reg_we),
        .mem_to_reg  (id_mem_to_reg),
        .mem_we      (id_mem_we),
        .flag_we     (id_flag_we),
        .jump        (id_jump),
        .br_z        (id_br_z),
        .br_nz       (id_br_nz),
        .halt        (id_halt)
    );

    // ADDI reads rd on port A; ST reads rd (store data) on port B
    wire [2:0] id_ra_addr = id_ra_is_rd ? id_rd : id_rs1;
    wire [2:0] id_rb_addr = id_rb_is_rd ? id_rd : id_rs2;
    wire [7:0] id_ra_data, id_rb_data;

    wire [7:0] wb_data = memwb_data;     // Stage 5 result

    regfile u_rf (
        .clk     (clk),
        .rst     (rst),
        .ra_addr (id_ra_addr), .ra_data (id_ra_data),
        .rb_addr (id_rb_addr), .rb_data (id_rb_data),
        .we      (memwb_reg_we),         // write in WB
        .wr_addr (memwb_rd),
        .wr_data (wb_data)
    );

    // =================================================================
    //  HAZARD UNIT
    // =================================================================
    wire [1:0] fwd_a_sel, fwd_b_sel;
    wire       stall;

    hazard_unit u_hazard (
        .id_valid       (ifid_valid),
        .id_ra_addr     (id_ra_addr),
        .id_rb_addr     (id_rb_addr),
        .id_uses_a      (id_uses_a),
        .id_uses_b      (id_uses_b),
        .ex_valid       (idex_valid),
        .ex_mem_to_reg  (idex_mem_to_reg),
        .ex_rd          (idex_rd),
        .ex_ra_addr     (idex_ra_addr),
        .ex_rb_addr     (idex_rb_addr),
        .ex_uses_a      (idex_uses_a),
        .ex_uses_b      (idex_uses_b),
        .mem_reg_we     (exmem_reg_we),
        .mem_mem_to_reg (exmem_mem_to_reg),
        .mem_rd         (exmem_rd),
        .wb_reg_we      (memwb_reg_we),
        .wb_rd          (memwb_rd),
        .fwd_a_sel      (fwd_a_sel),
        .fwd_b_sel      (fwd_b_sel),
        .stall          (stall)
    );

    // =================================================================
    //  STAGE 3 : EX
    // =================================================================
    // forwarding muxes: 10 = EX/MEM, 01 = MEM/WB, 00 = value read in ID
    wire [7:0] ex_opA = (fwd_a_sel == 2'b10) ? exmem_alu_y :
                        (fwd_a_sel == 2'b01) ? wb_data     : idex_ra_data;
    wire [7:0] ex_opB = (fwd_b_sel == 2'b10) ? exmem_alu_y :
                        (fwd_b_sel == 2'b01) ? wb_data     : idex_rb_data;

    wire [7:0] ex_alu_b = idex_alu_src_imm ? idex_imm : ex_opB;
    wire [7:0] ex_alu_y;
    wire       ex_alu_c, ex_alu_z;

    alu u_alu (
        .a      (ex_opA),
        .b      (ex_alu_b),
        .alu_op (idex_alu_op),
        .y      (ex_alu_y),
        .c      (ex_alu_c),
        .z      (ex_alu_z)
    );

    // branch resolution: flags were written at the end of the previous
    // instruction's EX cycle, so they are already up to date here
    wire take_branch = idex_valid &&
                       (idex_jump || (idex_br_z && flag_z) || (idex_br_nz && !flag_z));
    wire [7:0] branch_target = idex_imm;

    wire ex_halt    = idex_valid && idex_halt;
    wire fetch_stop = draining || ex_halt;

    // =================================================================
    //  STAGE 4 : MEM
    // =================================================================
    wire [7:0] mem_rdata;

    dmem u_dmem (
        .clk   (clk),
        .we    (exmem_mem_we && !halted),
        .addr  (exmem_addr),
        .wdata (exmem_store_data),
        .rdata (mem_rdata)
    );

    wire [7:0] mem_result = exmem_mem_to_reg ? mem_rdata : exmem_alu_y;

    // =================================================================
    //  SEQUENTIAL LOGIC (one block per pipeline register)
    // =================================================================

    // ---- PC and IF/ID : branch flush > halt > stall > normal ----
    always @(posedge clk) begin
        if (rst) begin
            pc         <= 8'h00;
            ifid_instr <= 16'h0000;
            ifid_valid <= 1'b0;
        end else if (!halted) begin
            if (take_branch) begin
                pc         <= branch_target;
                ifid_instr <= 16'h0000;
                ifid_valid <= 1'b0;
            end else if (fetch_stop) begin
                ifid_instr <= 16'h0000;       // PC frozen, nothing more fetched
                ifid_valid <= 1'b0;
            end else if (stall) begin
                // keep PC and IF/ID
            end else begin
                pc         <= pc + 8'd1;
                ifid_instr <= if_instr;
                ifid_valid <= 1'b1;
            end
        end
    end

    // ---- ID/EX : every control bit is gated by id_go, so a bubble is inert ----
    wire id_go = ifid_valid && !take_branch && !fetch_stop && !stall;

    always @(posedge clk) begin
        if (rst) begin
            idex_valid       <= 1'b0;
            idex_alu_op      <= 3'd0;
            idex_alu_src_imm <= 1'b0;
            idex_uses_a      <= 1'b0;
            idex_uses_b      <= 1'b0;
            idex_reg_we      <= 1'b0;
            idex_mem_to_reg  <= 1'b0;
            idex_mem_we      <= 1'b0;
            idex_flag_we     <= 1'b0;
            idex_jump        <= 1'b0;
            idex_br_z        <= 1'b0;
            idex_br_nz       <= 1'b0;
            idex_halt        <= 1'b0;
            idex_rd          <= 3'd0;
            idex_ra_addr     <= 3'd0;
            idex_rb_addr     <= 3'd0;
            idex_ra_data     <= 8'h00;
            idex_rb_data     <= 8'h00;
            idex_imm         <= 8'h00;
        end else if (!halted) begin
            idex_valid       <= id_go;
            idex_alu_op      <= id_alu_op;
            idex_alu_src_imm <= id_go & id_alu_src_imm;
            idex_uses_a      <= id_go & id_uses_a;
            idex_uses_b      <= id_go & id_uses_b;
            idex_reg_we      <= id_go & id_reg_we;
            idex_mem_to_reg  <= id_go & id_mem_to_reg;
            idex_mem_we      <= id_go & id_mem_we;
            idex_flag_we     <= id_go & id_flag_we;
            idex_jump        <= id_go & id_jump;
            idex_br_z        <= id_go & id_br_z;
            idex_br_nz       <= id_go & id_br_nz;
            idex_halt        <= id_go & id_halt;
            idex_rd          <= id_rd;
            idex_ra_addr     <= id_ra_addr;
            idex_rb_addr     <= id_rb_addr;
            idex_ra_data     <= id_ra_data;
            idex_rb_data     <= id_rb_data;
            idex_imm         <= id_imm8;
        end
    end

    // ---- EX/MEM, flags, draining ----
    always @(posedge clk) begin
        if (rst) begin
            exmem_valid      <= 1'b0;
            exmem_reg_we     <= 1'b0;
            exmem_mem_to_reg <= 1'b0;
            exmem_mem_we     <= 1'b0;
            exmem_halt       <= 1'b0;
            exmem_rd         <= 3'd0;
            exmem_alu_y      <= 8'h00;
            exmem_addr       <= 8'h00;
            exmem_store_data <= 8'h00;
            flag_z           <= 1'b0;
            flag_c           <= 1'b0;
            draining         <= 1'b0;
        end else if (!halted) begin
            exmem_valid      <= idex_valid;
            exmem_reg_we     <= idex_valid && idex_reg_we;
            exmem_mem_to_reg <= idex_valid && idex_mem_to_reg;
            exmem_mem_we     <= idex_valid && idex_mem_we;
            exmem_halt       <= ex_halt;
            exmem_rd         <= idex_rd;
            exmem_alu_y      <= ex_alu_y;
            exmem_addr       <= ex_opA;       // R[rs1], forwarded
            exmem_store_data <= ex_opB;       // R[rd] for ST, forwarded

            if (idex_valid && idex_flag_we) begin
                flag_z <= ex_alu_z;
                flag_c <= ex_alu_c;
            end

            if (ex_halt)
                draining <= 1'b1;
        end
    end

    // ---- MEM/WB and halted ----
    always @(posedge clk) begin
        if (rst) begin
            memwb_valid  <= 1'b0;
            memwb_reg_we <= 1'b0;
            memwb_rd     <= 3'd0;
            memwb_data   <= 8'h00;
            memwb_halt   <= 1'b0;
            halted       <= 1'b0;
        end else if (!halted) begin
            memwb_valid  <= exmem_valid;
            memwb_reg_we <= exmem_reg_we;
            memwb_rd     <= exmem_rd;
            memwb_data   <= mem_result;
            memwb_halt   <= exmem_halt;
            if (memwb_halt)
                halted <= 1'b1;               // HLT is in WB: all older ones are done
        end else begin
            memwb_reg_we <= 1'b0;             // frozen: no more register writes
        end
    end

    // ---- debug outputs ----
    assign pc_out     = pc;
    assign flags_out  = {flag_z, flag_c};
    assign instr_done = memwb_valid;

endmodule
