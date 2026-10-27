// =====================================================================
//  FILE    : tb/tb_risc8_5stage.v
//  MODULE  : tb_risc8_5stage   (directed test of sw/program.s)
// ---------------------------------------------------------------------
//  Runs program.hex until HLT, prints the 5 stages every cycle, checks
//  registers / memory / flags (PASS / FAIL) and reports CPI figures.
//  Needs program.hex (python3 sw/asm8.py sw/program.s program.hex).
// =====================================================================
`timescale 1ns/1ps

module tb_risc8_5stage;

    reg clk = 0;
    reg rst = 1;
    wire       halted;
    wire [7:0] pc;
    wire [1:0] flags;          // {Z, C}
    wire       instr_done;

    risc8_5stage_core #(.IMEM_FILE("program.hex")) dut (
        .clk(clk), .rst(rst), .halted(halted), .pc_out(pc),
        .flags_out(flags), .instr_done(instr_done)
    );

    initial forever #5 clk = ~clk;           // 100 MHz

    integer cycles = 0, retired = 0, stalls = 0, flushes = 0, fwds = 0;
    integer errors = 0;

    always @(posedge clk) if (!rst && !halted) begin
        cycles <= cycles + 1;
        if (instr_done)      retired <= retired + 1;
        if (dut.stall)       stalls  <= stalls  + 1;
        if (dut.take_branch) flushes <= flushes + 1;
        if (dut.idex_valid && (dut.fwd_a_sel != 2'b00 || dut.fwd_b_sel != 2'b00))
            fwds <= fwds + 1;

        $display("t=%6t PC=%02h | ID:%s%04h | EX:v%b | MEM:v%b | WB:%s R%0d<=%02h | Z=%b C=%b %s%s",
                 $time, pc,
                 dut.ifid_valid ? " " : "-", dut.ifid_instr,
                 dut.idex_valid, dut.exmem_valid,
                 dut.memwb_reg_we ? "w" : "-", dut.memwb_rd, dut.memwb_data,
                 flags[1], flags[0],
                 dut.stall       ? " STALL" : "",
                 dut.take_branch ? " BRANCH->flush 2" : "");
    end

    task check_reg;
        input [2:0] r;
        input [7:0] expected;
        begin
            if (dut.u_rf.r[r] !== expected) begin
                $display("FAIL  R%0d = %02h, expected %02h", r, dut.u_rf.r[r], expected);
                errors = errors + 1;
            end else
                $display("PASS  R%0d = %02h", r, expected);
        end
    endtask

    initial begin
        #22 rst = 0;
        wait (halted);
        @(posedge clk); @(posedge clk);

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

        $display("\ncycles=%0d  instructions=%0d  CPI=%0.2f  load-use stalls=%0d  taken branches=%0d  forward-cycles=%0d",
                 cycles, retired, cycles * 1.0 / retired, stalls, flushes, fwds);
        if (errors == 0) $display("*** ALL TESTS PASSED ***");
        else             $display("*** %0d TEST(S) FAILED ***", errors);
        $finish;
    end

    initial begin #20000 $display("TIMEOUT"); $finish; end

endmodule
