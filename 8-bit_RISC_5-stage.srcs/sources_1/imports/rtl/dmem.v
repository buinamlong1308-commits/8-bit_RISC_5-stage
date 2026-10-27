// =====================================================================
//  FILE    : rtl/dmem.v
//  MODULE  : dmem         (Stage 4 - MEM)
// ---------------------------------------------------------------------
//  Data RAM, 256 x 8 bits.  Read: asynchronous.  Write: rising edge.
//  LD rd,[rs1]  -> rd = mem[R[rs1]]        ST rd,[rs1] -> mem[R[rs1]] = R[rd]
// =====================================================================
`timescale 1ns/1ps

module dmem (
    input  wire       clk,
    input  wire       we,
    input  wire [7:0] addr,
    input  wire [7:0] wdata,
    output wire [7:0] rdata
);

    reg [7:0] mem [0:255];
    integer   i;

    initial begin
        for (i = 0; i < 256; i = i + 1)
            mem[i] = 8'h00;
    end

    always @(posedge clk) begin
        if (we)
            mem[addr] <= wdata;
    end

    assign rdata = mem[addr];

endmodule
