module sar_afe_model_mv (
    input  wire        sample,
    input  wire [1:0]  ch,
    input  wire [7:0]  dac,
    input  wire [11:0] vin_mv0, vin_mv1, vin_mv2, vin_mv3,
    output reg         cmp
);
    reg [11:0] vhold;

    initial begin vhold = 12'd0; cmp = 1'b0; end

    // sample hạ xuống: đóng băng điện áp của kênh đang chọn
    always @(negedge sample) begin
        case (ch)
            2'd0: vhold = vin_mv0;
            2'd1: vhold = vin_mv1;
            2'd2: vhold = vin_mv2;
            2'd3: vhold = vin_mv3;
        endcase
    end

    // comparator: Vhold >= Vdac, với Vdac = dac * 3300/256 mV
    always @(vhold or dac) cmp = ((vhold * 256) >= (dac * 3300));
endmodule