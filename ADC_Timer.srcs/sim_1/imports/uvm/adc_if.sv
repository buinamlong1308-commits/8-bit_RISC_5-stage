interface adc_if (input logic clk);
    logic        rst_n;
    logic        en;
    logic        start;
    logic [1:0]  ch_in;
    logic [7:0]  smp;
    logic [7:0]  div;
    logic        busy;
    logic        eoc;
    logic [7:0]  result;
    logic [11:0] vin_mv [4];     // điện áp 4 kênh, đơn vị mV
endinterface