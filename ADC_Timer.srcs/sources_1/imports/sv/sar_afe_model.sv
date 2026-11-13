module sar_afe_model (
    input  wire       sample,
    input  wire [1:0] ch,
    input  wire [7:0] dac,
    output reg        cmp
);
    localparam real VREF = 3.3;
    localparam real LSB  = VREF / 256.0;

    real vin [0:3];        // testbench gán qua afe.vin[k]
    real vhold, vdac;

    initial begin
        vin[0] = 0.0; vin[1] = 0.0; vin[2] = 0.0; vin[3] = 0.0;
        vhold = 0.0; vdac = 0.0; cmp = 1'b0;
    end

    always @(negedge sample) vhold = vin[ch];     // sample hạ xuống: đóng băng điện áp
    always @(dac)            vdac  = dac * LSB;
    always @(vhold or vdac)  cmp   = (vhold >= vdac);
endmodule