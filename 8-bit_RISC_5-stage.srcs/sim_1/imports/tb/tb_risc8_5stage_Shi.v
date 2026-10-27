// =====================================================================
//  FILE        : tb/tb_risc8_5stage.v
//  MODULE      : tb_risc8_5stage   (TESTBENCH - simulation only)
//  PROJECT     : 8-bit RISC Processor Core with 5-Stage Pipeline
// ---------------------------------------------------------------------
//  WHAT THIS FILE DOES
//    1. Generates clock and reset.
//    2. Runs program.hex on the 5-stage core until it halts.
//    3. Prints what is in each of the 5 stages every cycle.
//    4. Checks registers, memory and flags -> PASS / FAIL.
//    5. Reports cycles, instructions, CPI, stalls, flushes, forwards.
//    6. Dumps risc8_5stage.vcd for GTKWave.
//
//  MODULES CALLED (instantiated) IN THIS FILE
//    risc8_5stage_core  from rtl/risc8_5stage_core.v  -> instance "dut"
//
//  INTERNAL SIGNALS READ (hierarchical references, simulation only)
//    dut.* pipeline registers, stall, take_branch, fwd_*_sel, flags
//                                            -> rtl/risc8_5stage_core.v
//    dut.u_rf.r[...]      register array     -> rtl/regfile.v
//    dut.u_dmem.mem[...]  data memory array  -> rtl/dmem.v
//
//  FILES NEEDED AT RUN TIME
//    program.hex  (made by sw/asm8.py from sw/program.s)
//
//  HOW TO RUN
//    python3 sw/asm8.py sw/program.s program.hex
//    iverilog -g2005 -o sim.vvp rtl/*.v tb/tb_risc8_5stage.v
//    vvp sim.vvp
//    gtkwave risc8_5stage.vcd
// =====================================================================

`timescale 1ns/1ps

module tb_risc8_5stage;

    reg clk = 0;
    reg rst = 1;
    wire       halted;
    wire [7:0] pc;
    wire [1:0] flags;        // {Z, C} from the core
    wire       instr_done;   // 1 when an instruction finishes WB

    // -----------------------------------------------------------------
    // CALL: module risc8_5stage_core from rtl/risc8_5stage_core.v
    // IMEM_FILE is passed on to imem (rtl/imem.v) -> $readmemh.
    // -----------------------------------------------------------------
    risc8_5stage_core #(.IMEM_FILE("program.hex")) dut (
        .clk    (clk),
        .rst    (rst),
        .halted     (halted),
        .pc_out     (pc),
        .flags_out  (flags),
        .instr_done (instr_done)
    );

    // 100 MHz clock (10 ns period): flip clk every 5 ns, forever
    initial forever #5 clk = ~clk;

    // -----------------------------------------------------------------
    // Counters
    // -----------------------------------------------------------------
    integer cycles  = 0;   // cycles from reset release until halted
    integer retired = 0;   // valid instructions that reached WB
    integer stalls  = 0;   // load-use stall cycles
    integer flushes = 0;   // taken branches (each flushes 2 instructions)
    integer fwds    = 0;   // EX operands supplied by forwarding
    integer errors  = 0;

    // -----------------------------------------------------------------
    // Per-cycle monitor
    // -----------------------------------------------------------------
    always @(posedge clk) if (!rst && !halted) begin
        cycles <= cycles + 1;
        if (instr_done)      retired <= retired + 1;
        if (dut.stall)       stalls  <= stalls  + 1;
        if (dut.take_branch) flushes <= flushes + 1;
        // hazard_unit.v only forwards into operands that are really used
        if (dut.idex_valid && (dut.fwd_a_sel != 2'b00 || dut.fwd_b_sel != 2'b00))
            fwds <= fwds + 1;

        // IF/ID instruction shown in hex; '--' means bubble
        $display("t=%6t PC=%02h | ID:%s%04h | EX:v%b | MEM:v%b | WB:%s R%0d<=%02h | Z=%b C=%b %s%s%s",
                 $time, pc,
                 dut.ifid_valid ? " " : "-", dut.ifid_instr,
                 dut.idex_valid, dut.exmem_valid,
                 dut.memwb_reg_we ? "w" : "-", dut.memwb_rd, dut.memwb_data,
                 flags[1], flags[0],
                 dut.stall       ? " STALL"            : "",
                 dut.take_branch ? " BRANCH->flush 2" : "",
                 (dut.idex_valid && (dut.fwd_a_sel != 2'b00 || dut.fwd_b_sel != 2'b00)) ? " fwd" : "");
    end

    // -----------------------------------------------------------------
    // TASK: check one register (array inside rtl/regfile.v)
    // -----------------------------------------------------------------
    task check_reg(input [2:0] r, input [7:0] exp);
        if (dut.u_rf.r[r] !== exp) begin
            $display("FAIL  R%0d = %02h, expected %02h", r, dut.u_rf.r[r], exp);
            errors = errors + 1;
        end else
            $display("PASS  R%0d = %02h", r, exp);
    endtask

    // -----------------------------------------------------------------
    // Main sequence
    // -----------------------------------------------------------------
    initial begin
        $dumpfile("risc8_5stage.vcd");
        $dumpvars(0, tb_risc8_5stage);

        #22 rst = 0;            // release reset after ~2 cycles
        wait (halted);          // run until HLT leaves the pipeline
        @(posedge clk); @(posedge clk);

        // Expected values come from sw/program.s (same as 3-stage design)
        $display("\n------------- register / memory check -------------");
        check_reg(1, 8'h00);  check_reg(2, 8'h0F);
        check_reg(3, 8'h01);  check_reg(4, 8'h20);
        check_reg(5, 8'h00);  check_reg(6, 8'h66);
        check_reg(7, 8'h00);

        if (dut.u_dmem.mem[8'h20] !== 8'h0F) begin
            $display("FAIL  MEM[20] = %02h", dut.u_dmem.mem[8'h20]); errors = errors + 1;
        end else $display("PASS  MEM[20] = 0F");

        if (flags !== 2'b11) begin
            $display("FAIL  flags Z=%b C=%b", flags[1], flags[0]); errors = errors + 1;
        end else $display("PASS  flags Z=1 C=1");

        $display("\ncycles=%0d  instructions=%0d  CPI=%0.2f  load-use stalls=%0d  taken branches=%0d  forwards=%0d",
                 cycles, retired, cycles * 1.0 / retired, stalls, flushes, fwds);
        if (errors == 0) $display("*** ALL TESTS PASSED ***");
        else             $display("*** %0d TEST(S) FAILED ***", errors);
        $finish;
    end

    // Watchdog: stop if the CPU never halts
    initial begin #20000 $display("TIMEOUT"); $finish; end

endmodule
