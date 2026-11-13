// sync_fifo.v - hang doi 8 muc, first-word fall-through
module sync_fifo #(
    parameter W = 10                 // {ch[1:0], data[7:0]}
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         push,
    input  wire [W-1:0] din,
    input  wire         pop,
    output wire [W-1:0] dout,        // phan tu cu nhat (0 khi rong)
    output wire [3:0]   level,       // 0..8
    output wire         empty,
    output wire         full,
    output reg          overflow     // xung 1 clock: push khi da day
);
    localparam DEPTH = 8;

    reg [W-1:0] mem [0:DEPTH-1];
    reg [2:0]   wptr, rptr;
    reg [3:0]   cnt;

    assign empty = (cnt == 4'd0);
    assign full  = (cnt == DEPTH);
    assign level = cnt;
    assign dout  = empty ? {W{1'b0}} : mem[rptr];

    wire do_push = push && !full;
    wire do_pop  = pop  && !empty;

    always @(posedge clk) begin
        overflow <= 1'b0;
        if (!rst_n) begin
            wptr <= 3'd0;
            rptr <= 3'd0;
            cnt  <= 4'd0;
        end else begin
            if (push && full) overflow <= 1'b1;
            if (do_push) begin
                mem[wptr] <= din;
                wptr      <= wptr + 3'd1;
            end
            if (do_pop) rptr <= rptr + 3'd1;
            case ({do_push, do_pop})
                2'b10:   cnt <= cnt + 4'd1;
                2'b01:   cnt <= cnt - 4'd1;
                default: cnt <= cnt;
            endcase
        end
    end
endmodule
