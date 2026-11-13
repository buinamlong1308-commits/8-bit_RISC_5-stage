// sar_adc_ctrl.v - SAR ADC controller 8 bit
module sar_adc_ctrl (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       en,        // en=0: huy chuyen doi, ve IDLE, khong co ket qua
    input  wire       start,     // xung 1 clock, bo qua neu dang ban
    input  wire [1:0] ch_in,
    input  wire [7:0] smp,       // thoi gian sample = SMP+1 buoc
    input  wire [7:0] div,       // moi buoc = DIV+1 clock
    output reg        sample,
    output reg  [1:0] ch,
    output reg  [7:0] dac,
    input  wire       cmp,       // 1: Vhold >= Vdac, giu bit
    output wire       busy,
    output reg        eoc,       // xung 1 clock
    output reg  [7:0] result
);
    localparam [1:0] IDLE = 2'd0, SAMPLE = 2'd1, CONVERT = 2'd2;

    reg [1:0] state;
    reg [7:0] dcnt, scnt, next_v;
    reg [2:0] bitpos;
    wire      tick = (dcnt == div);

    assign busy = (state != IDLE);

    always @(posedge clk) begin
        eoc <= 1'b0;
        if (!rst_n) begin
            state <= IDLE; sample <= 1'b0; ch <= 2'd0; dac <= 8'd0;
            dcnt <= 8'd0; scnt <= 8'd0; bitpos <= 3'd0; result <= 8'd0;
        end else if (!en) begin
            state <= IDLE; sample <= 1'b0; dac <= 8'd0; dcnt <= 8'd0;
        end else begin
            case (state)
                IDLE: if (start) begin
                    sample <= 1'b1;
                    ch     <= ch_in;
                    dcnt   <= 8'd0;
                    scnt   <= 8'd0;
                    state  <= SAMPLE;
                end

                SAMPLE: if (!tick) dcnt <= dcnt + 8'd1;
                else begin
                    dcnt <= 8'd0;
                    if (scnt == smp) begin
                        sample <= 1'b0;
                        dac    <= 8'h80;
                        bitpos <= 3'd7;
                        state  <= CONVERT;
                    end else scnt <= scnt + 8'd1;
                end

                CONVERT: if (!tick) dcnt <= dcnt + 8'd1;
                else begin
                    dcnt   <= 8'd0;
                    next_v = cmp ? dac : (dac & ~(8'd1 << bitpos));
                    if (bitpos == 3'd0) begin
                        result <= next_v;
                        eoc    <= 1'b1;
                        dac    <= 8'd0;
                        state  <= IDLE;
                    end else begin
                        dac    <= next_v | (8'd1 << (bitpos - 3'd1));
                        bitpos <= bitpos - 3'd1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
