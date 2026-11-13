interface timer_if (input logic clk);
    logic       rst_n;
    logic       en;
    logic [7:0] presc, load, cmp_th;
    logic [7:0] cnt;
    logic       ovf, cmp_pulse, pwm;
endinterface