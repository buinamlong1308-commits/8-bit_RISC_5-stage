`timescale 1ns/1ps
module tb_sar_adc;
    reg clk = 0, rst_n = 0, en = 0, start = 0;
    reg [1:0] ch_in = 0;
    reg [7:0] smp = 2, div = 0;
    wire sample, cmp, busy, eoc;
    wire [1:0] ch;
    wire [7:0] dac, result;

    sar_adc_ctrl dut (.clk(clk), .rst_n(rst_n), .en(en), .start(start), .ch_in(ch_in),
                      .smp(smp), .div(div), .sample(sample), .ch(ch), .dac(dac), .cmp(cmp),
                      .busy(busy), .eoc(eoc), .result(result));
    sar_afe_model afe (.sample(sample), .ch(ch), .dac(dac), .cmp(cmp));

    always #5 clk = ~clk;

    integer errors = 0, lat, expv, L;

    task convert(input integer chan, input real v, input integer s, input integer d);
    begin
        afe.vin[chan] = v;  ch_in = chan;  smp = s;  div = d;
        @(negedge clk); start = 1;
        @(negedge clk); start = 0;
        lat = 0;
        while (!eoc && lat < 5000) begin @(negedge clk); lat = lat + 1; end
        expv = $rtoi(v / (3.3 / 256.0));
        if (expv > 255) expv = 255;
        L = (s + 9) * (d + 1);
        if (result !== expv[7:0] || lat !== L) begin
            errors = errors + 1;
            $display("FAIL ch%0d v=%f smp=%0d div=%0d: result=%0d (exp %0d) latency=%0d (exp %0d)",
                     chan, v, s, d, result, expv, lat, L);
        end else
            $display("ok   ch%0d v=%f -> %0d (%02h), %0d clocks", chan, v, result, result, lat);
        @(negedge clk);
    end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1; en = 1;
        @(negedge clk);

        convert(0, 0.0,   2, 0);
        convert(0, 0.005, 2, 0);
        convert(2, 1.111, 2, 0);    // ví dụ trong tài liệu: 86 = 0x56, 11 clock
        convert(1, 2.0,   2, 0);
        convert(3, 2.5,   2, 0);
        convert(0, 3.2,   2, 0);
        convert(0, 3.29,  2, 0);
        convert(0, 3.3,   2, 0);
        convert(2, 1.111, 4, 1);    // smp và div khác mặc định

        // hủy giữa chừng bằng en=0
        afe.vin[0] = 1.0; ch_in = 0; smp = 2; div = 0;
        @(negedge clk); start = 1;
        @(negedge clk); start = 0;
        repeat (3) @(negedge clk);
        en = 0;
        @(negedge clk);
        if (busy !== 0 || eoc !== 0) begin errors = errors + 1; $display("FAIL: abort"); end
        repeat (15) @(negedge clk);
        if (eoc !== 0) begin errors = errors + 1; $display("FAIL: eoc after abort"); end
        en = 1;

        if (errors == 0) $display("tb_sar_adc: PASS"); else $display("tb_sar_adc: FAIL (%0d errors)", errors);
        $finish;
    end
endmodule