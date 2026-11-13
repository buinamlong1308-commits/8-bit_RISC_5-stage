// timer8.v - 8-bit timer: prescaler, counter, compare, PWM, one-shot
module timer8 (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       en,
    input  wire       oneshot,    // 1: dung sau lan overflow dau tien
    input  wire [7:0] presc,      // tick moi PRESC+1 clock
    input  wire [7:0] load,       // dem 0..LOAD roi wrap
    input  wire [7:0] cmp,        // nguong compare / PWM
    output reg  [7:0] cnt,
    output reg        ovf_pulse,  // 1 clock khi wrap
    output reg        cmp_pulse,  // 1 clock khi cnt == CMP
    output wire       pwm_out
);
    reg [7:0] pre;
    reg       stopped;            // one-shot da xong, cho EN ha xuong

    always @(posedge clk) begin
        ovf_pulse <= 1'b0;
        cmp_pulse <= 1'b0;
        if (!rst_n || !en) begin
            pre     <= 8'd0;
            cnt     <= 8'd0;
            stopped <= 1'b0;
        end else if (stopped) begin
            // dong bang cho den khi EN = 0
        end else if (pre < presc) begin
            pre <= pre + 8'd1;
        end else begin
            pre <= 8'd0;
            if (cnt == cmp) cmp_pulse <= 1'b1;
            if (cnt >= load) begin
                cnt       <= 8'd0;
                ovf_pulse <= 1'b1;
                if (oneshot) stopped <= 1'b1;
            end else begin
                cnt <= cnt + 8'd1;
            end
        end
    end

    assign pwm_out = en & ~stopped & (cnt < cmp);
endmodule
