`timescale 1ns/1ps
module tb_timer8;
    reg clk = 0, rst_n = 0, en = 0;
    reg [7:0] presc = 1, load = 4, cmp = 2;
    wire [7:0] cnt;
    wire ovf, cmpp, pwm;

    timer8 dut (.clk(clk), .rst_n(rst_n), .en(en), .presc(presc), .load(load),
                .cmp(cmp), .cnt(cnt), .ovf_pulse(ovf), .cmp_pulse(cmpp), .pwm_out(pwm));

    always #5 clk = ~clk;

    integer n = 0, last_ovf = 0, last_cmp = 0, hi = 0, errors = 0, periods = 0;
    reg started = 0;

    always @(posedge clk) if (en) begin
        n = n + 1;
        if (cmpp) last_cmp = n;
        if (ovf) begin
            if (started) begin
                if (n - last_ovf !== 10) begin errors = errors + 1; $display("FAIL period %0d", n - last_ovf); end
                if (hi !== 4)            begin errors = errors + 1; $display("FAIL pwm high %0d", hi); end
                periods = periods + 1;
            end
            if (last_cmp != 0 && (n - last_cmp) !== 4) begin
                errors = errors + 1; $display("FAIL cmp->ovf %0d", n - last_cmp);
            end
            started = 1; last_ovf = n; hi = 0;
        end
        if (started && pwm) hi = hi + 1;
    end

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk); en = 1;
        repeat (50) @(posedge clk);
        if (periods < 3) begin errors = errors + 1; $display("FAIL: too few periods (%0d)", periods); end
        en = 0;
        repeat (2) @(posedge clk);
        if (cnt !== 0 || pwm !== 0) begin errors = errors + 1; $display("FAIL: EN=0 did not clear"); end
        if (errors == 0) $display("tb_timer8: PASS"); else $display("tb_timer8: FAIL (%0d errors)", errors);
        $finish;
    end
endmodule