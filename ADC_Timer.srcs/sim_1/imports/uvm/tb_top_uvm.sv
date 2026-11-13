`timescale 1ns/1ps
module tb_top_uvm;
    import uvm_pkg::*;
    import adc_pkg::*;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    adc_if   aif (clk);
    timer_if tif (clk);

    // ---------------- ADC ----------------
    wire        sample, cmp;
    wire [1:0]  ch;
    wire [7:0]  dac;

    sar_adc_ctrl dut (
        .clk(clk), .rst_n(aif.rst_n), .en(aif.en), .start(aif.start),
        .ch_in(aif.ch_in), .smp(aif.smp), .div(aif.div),
        .sample(sample), .ch(ch), .dac(dac), .cmp(cmp),
        .busy(aif.busy), .eoc(aif.eoc), .result(aif.result)
    );

    sar_afe_model_mv afe (
        .sample(sample), .ch(ch), .dac(dac),
        .vin_mv0(aif.vin_mv[0]), .vin_mv1(aif.vin_mv[1]),
        .vin_mv2(aif.vin_mv[2]), .vin_mv3(aif.vin_mv[3]),
        .cmp(cmp)
    );

    // ---------------- Timer ----------------
    assign tif.rst_n = aif.rst_n;

    timer8 dut_t (
        .clk(clk), .rst_n(tif.rst_n), .en(tif.en),
        .presc(tif.presc), .load(tif.load), .cmp(tif.cmp_th),
        .cnt(tif.cnt), .ovf_pulse(tif.ovf), .cmp_pulse(tif.cmp_pulse),
        .pwm_out(tif.pwm)
    );

    // ---------------- Khởi tạo ----------------
    initial begin
        aif.rst_n = 1'b0; aif.en = 1'b0; aif.start = 1'b0;
        aif.ch_in = 2'd0; aif.smp = 8'd2; aif.div = 8'd0;
        for (int i = 0; i < 4; i++) aif.vin_mv[i] = 12'd0;
        tif.en = 1'b0; tif.presc = 8'd0; tif.load = 8'd0; tif.cmp_th = 8'd0;
        repeat (3) @(negedge clk);
        aif.rst_n = 1'b1;
        aif.en    = 1'b1;
    end

    initial begin
        uvm_config_db#(virtual adc_if)::set(null, "*", "vif", aif);
        uvm_config_db#(virtual timer_if)::set(null, "*", "vif", tif);
        run_test("all_test");
    end
endmodule