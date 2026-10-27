// =====================================================================
//  FILE    : tb/tb_custom.v
//  MODULE  : tb_custom   (own self-checking test suite)
// ---------------------------------------------------------------------
//  Each test builds a tiny program with the i_xxx tasks, loads it into
//  the instruction ROM (dut.u_imem.rom), resets the CPU, runs to HLT
//  and checks registers, memory, flags and pipeline statistics.
//
//  Groups:  A ALU + flags      B memory        C forwarding (dist 1-4)
//           D load-use stall   E branches      F HLT / reset
//           G stall + branch together
//  After EVERY program the accounting identity is also checked:
//           cycles = instructions + 4 + stalls + 2 * taken_branches
// =====================================================================
`timescale 1ns/1ps

module tb_custom;

    reg clk = 0;
    reg rst = 1;
    wire       halted;
    wire [7:0] pc;
    wire [1:0] flags;                 // {Z, C}
    wire       instr_done;

    risc8_5stage_core #(.IMEM_FILE("")) dut (
        .clk(clk), .rst(rst), .halted(halted), .pc_out(pc),
        .flags_out(flags), .instr_done(instr_done)
    );

    initial forever #5 clk = ~clk;

    // -----------------------------------------------------------------
    //  Statistics of the current run
    // -----------------------------------------------------------------
    reg     counting = 0;
    integer cycles, retired, stalls, taken, fwds;

    always @(posedge clk) if (counting && !rst && !halted) begin
        cycles <= cycles + 1;
        if (instr_done)      retired <= retired + 1;
        if (dut.stall)       stalls  <= stalls  + 1;
        if (dut.take_branch) taken   <= taken   + 1;
        if (dut.idex_valid && (dut.fwd_a_sel != 2'b00 || dut.fwd_b_sel != 2'b00))
            fwds <= fwds + 1;
    end

    // -----------------------------------------------------------------
    //  Check helpers
    // -----------------------------------------------------------------
    integer errors = 0;
    integer checks = 0;

    task chk_reg;
        input [2:0] r;
        input [7:0] expected;
        begin
            checks = checks + 1;
            if (dut.u_rf.r[r] === expected)
                $display("  PASS R%0d = %02h", r, expected);
            else begin
                $display("  FAIL R%0d = %02h (expected %02h)", r, dut.u_rf.r[r], expected);
                errors = errors + 1;
            end
        end
    endtask

    task chk_mem;
        input [7:0] a;
        input [7:0] expected;
        begin
            checks = checks + 1;
            if (dut.u_dmem.mem[a] === expected)
                $display("  PASS MEM[%02h] = %02h", a, expected);
            else begin
                $display("  FAIL MEM[%02h] = %02h (expected %02h)", a, dut.u_dmem.mem[a], expected);
                errors = errors + 1;
            end
        end
    endtask

    task chk_flags;
        input z;
        input c;
        begin
            checks = checks + 1;
            if (flags === {z, c})
                $display("  PASS flags Z=%b C=%b", z, c);
            else begin
                $display("  FAIL flags Z=%b C=%b (expected Z=%b C=%b)", flags[1], flags[0], z, c);
                errors = errors + 1;
            end
        end
    endtask

    task chk_int;
        input [8*32:1] name;
        input integer got;
        input integer expected;
        begin
            checks = checks + 1;
            if (got === expected)
                $display("  PASS %0s = %0d", name, got);
            else begin
                $display("  FAIL %0s = %0d (expected %0d)", name, got, expected);
                errors = errors + 1;
            end
        end
    endtask

    // -----------------------------------------------------------------
    //  Program builder (same encoding as sw/asm8.py)
    //    R  : op | rd | rs1 | rs2 | 000        R1 : op | rd | rs1 | 000000
    //    I  : op | rd | 0   | imm8            J  : op | 0000 | addr8
    // -----------------------------------------------------------------
    reg [15:0] prog [0:255];
    integer    pn;

    task new_prog;
        input [8*40:1] title;
        integer j;
        begin
            for (j = 0; j < 256; j = j + 1) prog[j] = 16'h0000;
            pn = 0;
            $display("\n[%0s]", title);
        end
    endtask

    task emit;
        input [15:0] w;
        begin prog[pn] = w; pn = pn + 1; end
    endtask

    task i_nop;                         begin emit(16'h0000);                    end endtask
    task i_add;  input [2:0] d, a, b;   begin emit({4'h1, d, a, b, 3'b000});     end endtask
    task i_sub;  input [2:0] d, a, b;   begin emit({4'h2, d, a, b, 3'b000});     end endtask
    task i_and;  input [2:0] d, a, b;   begin emit({4'h3, d, a, b, 3'b000});     end endtask
    task i_or;   input [2:0] d, a, b;   begin emit({4'h4, d, a, b, 3'b000});     end endtask
    task i_xor;  input [2:0] d, a, b;   begin emit({4'h5, d, a, b, 3'b000});     end endtask
    task i_shl;  input [2:0] d, a;      begin emit({4'h6, d, a, 6'b000000});     end endtask
    task i_shr;  input [2:0] d, a;      begin emit({4'h7, d, a, 6'b000000});     end endtask
    task i_ldi;  input [2:0] d; input [7:0] v; begin emit({4'h8, d, 1'b0, v});   end endtask
    task i_addi; input [2:0] d; input [7:0] v; begin emit({4'h9, d, 1'b0, v});   end endtask
    task i_ld;   input [2:0] d, a;      begin emit({4'hA, d, a, 6'b000000});     end endtask
    task i_st;   input [2:0] d, a;      begin emit({4'hB, d, a, 6'b000000});     end endtask
    task i_jmp;  input [7:0] t;         begin emit({4'hC, 4'h0, t});             end endtask
    task i_bz;   input [7:0] t;         begin emit({4'hD, 4'h0, t});             end endtask
    task i_bnz;  input [7:0] t;         begin emit({4'hE, 4'h0, t});             end endtask
    task i_hlt;                         begin emit(16'hF000);                    end endtask

    // -----------------------------------------------------------------
    //  Run the loaded program: load ROM, clear RAM, reset, run to HLT
    // -----------------------------------------------------------------
    integer k, guard;

    task run;
        begin
            for (k = 0; k < 256; k = k + 1) begin
                dut.u_imem.rom[k] = prog[k];
                dut.u_dmem.mem[k] = 8'h00;
            end
            cycles = 0; retired = 0; stalls = 0; taken = 0; fwds = 0;
            rst = 1;
            repeat (2) @(posedge clk);
            #1 rst = 0;
            counting = 1;
            guard = 0;
            while (!halted && guard < 2000) begin
                @(posedge clk);
                guard = guard + 1;
            end
            counting = 0;
            @(posedge clk); #1;
            checks = checks + 1;
            if (!halted) begin
                $display("  FAIL program did not halt (TIMEOUT)");
                errors = errors + 1;
            end
            // pipeline accounting identity
            chk_int("cycles = N+4+stalls+2*taken", cycles, retired + 4 + stalls + 2 * taken);
        end
    endtask

    // =================================================================
    //  TESTS
    // =================================================================
    initial begin
        $display("==================== tb_custom ====================");

        // ---------------- A : ALU and flags ----------------
        new_prog("A1 ADD no carry");
        i_ldi(1, 8'h3C); i_ldi(2, 8'h0F); i_add(3, 1, 2); i_hlt;
        run; chk_reg(3, 8'h4B); chk_flags(0, 0);

        new_prog("A2 ADD carry out (FF+01)");
        i_ldi(1, 8'hFF); i_ldi(2, 8'h01); i_add(3, 1, 2); i_hlt;
        run; chk_reg(3, 8'h00); chk_flags(1, 1);

        new_prog("A3 SUB 5-3");
        i_ldi(1, 8'h05); i_ldi(2, 8'h03); i_sub(3, 1, 2); i_hlt;
        run; chk_reg(3, 8'h02); chk_flags(0, 0);

        new_prog("A4 SUB borrow 3-5");
        i_ldi(1, 8'h03); i_ldi(2, 8'h05); i_sub(3, 1, 2); i_hlt;
        run; chk_reg(3, 8'hFE); chk_flags(0, 1);

        new_prog("A5 SUB equal 7-7");
        i_ldi(1, 8'h07); i_ldi(2, 8'h07); i_sub(3, 1, 2); i_hlt;
        run; chk_reg(3, 8'h00); chk_flags(1, 0);

        new_prog("A6 AND OR XOR, logic clears C");
        i_ldi(1, 8'hFF); i_add(0, 1, 1);              // R0 = FE, C = 1
        i_ldi(2, 8'hCD); i_ldi(3, 8'hAB);             // odd operands: bit 0 = 1
        i_and(4, 2, 3); i_or(5, 2, 3); i_xor(6, 2, 3);
        i_hlt;
        run; chk_reg(0, 8'hFE); chk_reg(4, 8'h89); chk_reg(5, 8'hEF); chk_reg(6, 8'h66);
        chk_flags(0, 0);

        new_prog("A7 AND to zero");
        i_ldi(1, 8'hF0); i_ldi(2, 8'h0F); i_and(3, 1, 2); i_hlt;
        run; chk_reg(3, 8'h00); chk_flags(1, 0);

        new_prog("A8 SHL with carry (81)");
        i_ldi(1, 8'h81); i_shl(2, 1); i_hlt;
        run; chk_reg(2, 8'h02); chk_flags(0, 1);

        new_prog("A9 SHL no carry (40)");
        i_ldi(1, 8'h40); i_shl(2, 1); i_hlt;
        run; chk_reg(2, 8'h80); chk_flags(0, 0);

        new_prog("A10 SHR with carry (03)");
        i_ldi(1, 8'h03); i_shr(2, 1); i_hlt;
        run; chk_reg(2, 8'h01); chk_flags(0, 1);

        new_prog("A11 SHR to zero (01)");
        i_ldi(1, 8'h01); i_shr(2, 1); i_hlt;
        run; chk_reg(2, 8'h00); chk_flags(1, 1);

        new_prog("A12 ADDI chain with wrap");
        i_ldi(1, 8'h10); i_addi(1, 8'h20); i_addi(1, 8'hD0); i_hlt;
        run; chk_reg(1, 8'h00); chk_flags(1, 1);

        new_prog("A13 LDI / ST / LD keep flags");
        i_ldi(1, 8'hFF); i_ldi(2, 8'h01); i_add(3, 1, 2);   // Z=1 C=1
        i_ldi(4, 8'h55); i_ldi(5, 8'h20); i_st(4, 5); i_ld(6, 5);
        i_hlt;
        run; chk_reg(6, 8'h55); chk_mem(8'h20, 8'h55); chk_flags(1, 1);

        // ---------------- B : memory ----------------
        new_prog("B1 ST then LD same address");
        i_ldi(4, 8'h20); i_ldi(2, 8'hAB); i_st(2, 4); i_ld(5, 4); i_hlt;
        run; chk_mem(8'h20, 8'hAB); chk_reg(5, 8'hAB); chk_int("stalls", stalls, 0);

        new_prog("B2 first and last address");
        i_ldi(1, 8'h00); i_ldi(2, 8'h11); i_st(2, 1);
        i_ldi(3, 8'hFF); i_ldi(4, 8'h22); i_st(4, 3);
        i_ld(5, 1); i_ld(6, 3); i_hlt;
        run; chk_mem(8'h00, 8'h11); chk_mem(8'hFF, 8'h22); chk_reg(5, 8'h11); chk_reg(6, 8'h22);

        new_prog("B3 overwrite then read");
        i_ldi(4, 8'h30); i_ldi(1, 8'h01); i_ldi(2, 8'h02);
        i_st(1, 4); i_st(2, 4); i_ld(3, 4); i_hlt;
        run; chk_reg(3, 8'h02); chk_mem(8'h30, 8'h02);

        // ---------------- C : forwarding ----------------
        new_prog("C1 forward dist 1 (EX/MEM)");
        i_ldi(1, 8'h05); i_add(2, 1, 1); i_hlt;
        run; chk_reg(2, 8'h0A); chk_int("forward cycles", fwds, 1); chk_int("stalls", stalls, 0);

        new_prog("C2 forward dist 2 (MEM/WB)");
        i_ldi(1, 8'h05); i_nop; i_add(2, 1, 1); i_hlt;
        run; chk_reg(2, 8'h0A); chk_int("forward cycles", fwds, 1);

        new_prog("C3 dist 3 (regfile bypass)");
        i_ldi(1, 8'h05); i_nop; i_nop; i_add(2, 1, 1); i_hlt;
        run; chk_reg(2, 8'h0A); chk_int("forward cycles", fwds, 0);

        new_prog("C4 dist 4 (plain read)");
        i_ldi(1, 8'h05); i_nop; i_nop; i_nop; i_add(2, 1, 1); i_hlt;
        run; chk_reg(2, 8'h0A); chk_int("forward cycles", fwds, 0);

        new_prog("C5 newest value wins");
        i_ldi(1, 8'h01); i_ldi(1, 8'h02); i_ldi(1, 8'h03); i_add(2, 1, 1); i_hlt;
        run; chk_reg(2, 8'h06);

        new_prog("C6 port A and B from different stages");
        i_ldi(1, 8'h03); i_ldi(2, 8'h04); i_sub(3, 2, 1);
        i_nop; i_ldi(4, 8'h09); i_nop; i_sub(5, 4, 1);   // R4 dist 2, R1 old
        i_hlt;
        run; chk_reg(3, 8'h01); chk_reg(5, 8'h06);

        new_prog("C7 ADDI chain");
        i_ldi(3, 8'h01); i_addi(3, 8'h01); i_addi(3, 8'h01); i_addi(3, 8'h01); i_hlt;
        run; chk_reg(3, 8'h04); chk_int("stalls", stalls, 0);

        new_prog("C8 forward into SHL / SHR");
        i_ldi(1, 8'h21); i_shl(2, 1); i_shr(3, 2); i_hlt;
        run; chk_reg(2, 8'h42); chk_reg(3, 8'h21);

        new_prog("C9 forward store data and address");
        i_ldi(4, 8'h30); i_ldi(2, 8'h77); i_st(2, 4); i_hlt;
        run; chk_mem(8'h30, 8'h77);

        new_prog("C10 R0 is an ordinary register");
        i_ldi(0, 8'h09); i_add(1, 0, 0); i_hlt;
        run; chk_reg(0, 8'h09); chk_reg(1, 8'h12);

        // ---------------- D : load-use stall ----------------
        new_prog("D1 load-use on port A");
        i_ldi(4, 8'h40); i_ldi(2, 8'h5A); i_st(2, 4);
        i_ld(5, 4); i_addi(5, 8'h01); i_hlt;
        run; chk_reg(5, 8'h5B); chk_int("stalls", stalls, 1);

        new_prog("D2 load-use on port B (store data)");
        i_ldi(4, 8'h40); i_ldi(7, 8'h41); i_ldi(2, 8'h5A); i_st(2, 4);
        i_ld(6, 4); i_st(6, 7); i_hlt;
        run; chk_mem(8'h41, 8'h5A); chk_int("stalls", stalls, 1);

        new_prog("D3 load, 1 instruction gap: no stall");
        i_ldi(4, 8'h40); i_ldi(2, 8'h5A); i_st(2, 4);
        i_ld(5, 4); i_ldi(1, 8'h01); i_add(6, 5, 1); i_hlt;
        run; chk_reg(6, 8'h5B); chk_int("stalls", stalls, 0);

        new_prog("D4 load result used as address");
        i_ldi(3, 8'h10); i_ldi(4, 8'h60); i_st(4, 3);      // MEM[10] = 60
        i_ldi(2, 8'h99); i_st(2, 4);                        // MEM[60] = 99
        i_ld(4, 3); i_ld(5, 4); i_hlt;
        run; chk_reg(4, 8'h60); chk_reg(5, 8'h99); chk_int("stalls", stalls, 1);

        // ---------------- E : branches ----------------
        new_prog("E1 BZ taken, wrong path flushed");
        i_ldi(1, 8'h01); i_ldi(2, 8'h01); i_sub(3, 1, 2);   // 0..2  Z=1
        i_bz(6);                                            // 3
        i_ldi(4, 8'hEE); i_ldi(5, 8'hEE);                   // 4,5  wrong path
        i_ldi(6, 8'h66); i_hlt;                             // 6,7
        run; chk_reg(4, 8'h00); chk_reg(5, 8'h00); chk_reg(6, 8'h66); chk_int("taken", taken, 1);

        new_prog("E2 BZ not taken");
        i_ldi(1, 8'h01); i_ldi(2, 8'h02); i_sub(3, 1, 2);   // Z=0
        i_bz(7);                                            // 3
        i_ldi(4, 8'h44); i_ldi(5, 8'h55);                   // 4,5
        i_hlt;                                              // 6
        run; chk_reg(4, 8'h44); chk_reg(5, 8'h55); chk_int("taken", taken, 0);

        new_prog("E3 BNZ loop: sum 3+2+1");
        i_ldi(1, 8'h03); i_ldi(2, 8'h00); i_ldi(3, 8'h01); // 0..2
        i_add(2, 2, 1); i_sub(1, 1, 3); i_bnz(3);          // 3..5 loop
        i_hlt;                                              // 6
        run; chk_reg(2, 8'h06); chk_reg(1, 8'h00); chk_flags(1, 0); chk_int("taken", taken, 2);

        new_prog("E4 BNZ not taken when Z=1");
        i_ldi(1, 8'h01); i_ldi(2, 8'h01); i_sub(3, 1, 2);   // Z=1
        i_bnz(5);                                           // 3
        i_ldi(4, 8'h44);                                    // 4
        i_hlt;                                              // 5
        run; chk_reg(4, 8'h44); chk_int("taken", taken, 0);

        new_prog("E5 JMP skips two instructions");
        i_ldi(1, 8'h01); i_jmp(4);                          // 0,1
        i_ldi(1, 8'hEE); i_ldi(2, 8'hEE);                   // 2,3 wrong path
        i_ldi(3, 8'h03); i_hlt;                             // 4,5
        run; chk_reg(1, 8'h01); chk_reg(2, 8'h00); chk_reg(3, 8'h03); chk_int("taken", taken, 1);

        new_prog("E6 branch to a branch");
        i_ldi(1, 8'h00); i_addi(1, 8'h00); i_bz(5);         // 0..2  Z=1
        i_ldi(7, 8'hEE); i_ldi(7, 8'hEE);                   // 3,4 wrong path
        i_jmp(8);                                           // 5
        i_ldi(6, 8'hEE); i_ldi(6, 8'hEE);                   // 6,7 wrong path
        i_ldi(5, 8'h55); i_hlt;                             // 8,9
        run; chk_reg(7, 8'h00); chk_reg(6, 8'h00); chk_reg(5, 8'h55); chk_int("taken", taken, 2);

        new_prog("E7 wrong-path JMP must not run");
        i_ldi(1, 8'h00); i_addi(1, 8'h00); i_bz(5);         // 0..2  Z=1
        i_jmp(7);                                           // 3 wrong path
        i_ldi(7, 8'hEE);                                    // 4 wrong path
        i_ldi(5, 8'h55); i_ldi(6, 8'h66); i_hlt;            // 5,6,7
        run; chk_reg(5, 8'h55); chk_reg(6, 8'h66); chk_reg(7, 8'h00); chk_int("taken", taken, 1);

        new_prog("E8 wrong-path ST and flags");
        i_ldi(4, 8'h50); i_ldi(1, 8'h00); i_addi(1, 8'h00); // 0..2  Z=1
        i_bz(7);                                            // 3
        i_st(4, 4);                                         // 4 wrong path (store)
        i_addi(1, 8'h01);                                   // 5 wrong path (flags)
        i_addi(1, 8'h01);                                   // 6 never fetched
        i_hlt;                                              // 7
        run; chk_mem(8'h50, 8'h00); chk_reg(1, 8'h00); chk_flags(1, 0);

        // ---------------- F : HLT and reset ----------------
        new_prog("F1 HLT only");
        i_hlt;
        run; chk_int("instructions", retired, 1); chk_int("cycles", cycles, 5);
        chk_reg(1, 8'h00);

        new_prog("F2 instruction before HLT completes");
        i_ldi(1, 8'h05); i_add(2, 1, 1); i_hlt; i_ldi(3, 8'h09);
        run; chk_reg(2, 8'h0A); chk_reg(3, 8'h00);

        new_prog("F3 ST and LD right before HLT");
        i_ldi(4, 8'h20); i_ldi(2, 8'h3C); i_st(2, 4); i_ld(5, 4); i_hlt;
        run; chk_mem(8'h20, 8'h3C); chk_reg(5, 8'h3C);

        new_prog("F4 pipeline frozen after halt");
        i_ldi(1, 8'h07); i_ldi(2, 8'h08); i_hlt; i_ldi(3, 8'hEE);
        run;
        begin : frozen
            reg [7:0] pc_before;
            pc_before = pc;
            repeat (10) @(posedge clk);
            #1;
            chk_int("halted stays 1", halted, 1);
            chk_int("pc unchanged", pc, pc_before);
            chk_reg(1, 8'h07); chk_reg(2, 8'h08); chk_reg(3, 8'h00);
        end

        // reset after halt
        rst = 1; @(posedge clk); #1;
        chk_int("halted after reset", halted, 0);
        chk_int("pc after reset", pc, 0);
        chk_reg(1, 8'h00); chk_reg(2, 8'h00);
        chk_flags(0, 0);

        // ---------------- G : stall and branch together ----------------
        new_prog("G1 load-use stall then BZ");
        i_ldi(4, 8'h20); i_ldi(2, 8'h80); i_st(2, 4);        // 0..2  MEM[20] = 80
        i_ldi(5, 8'h01); i_ld(5, 4);                         // 3,4   R5 = 80
        i_add(6, 5, 5);                                      // 5     stall, 80+80 = 00, Z=1 C=1
        i_bz(9);                                             // 6
        i_ldi(7, 8'hEE); i_ldi(7, 8'hEE);                    // 7,8   wrong path
        i_hlt;                                               // 9
        run; chk_reg(5, 8'h80); chk_reg(6, 8'h00); chk_reg(7, 8'h00);
        chk_flags(1, 1); chk_int("stalls", stalls, 1); chk_int("taken", taken, 1);

        // ---------------- summary ----------------
        $display("\n====================================================");
        if (errors == 0)
            $display("tb_custom PASSED: %0d of %0d checks OK", checks, checks);
        else
            $display("tb_custom FAILED: %0d of %0d checks failed", errors, checks);
        $display("====================================================\n");
        $finish;
    end

    initial begin #5000000 $display("GLOBAL TIMEOUT"); $finish; end

endmodule
