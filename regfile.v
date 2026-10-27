// =====================================================================
//  FILE    : rtl/regfile.v
//  MODULE  : regfile      (read in ID, write in WB)
// ---------------------------------------------------------------------
//  8 x 8-bit registers R0..R7 (R0 is an ordinary register).
//  Two read ports (A, B) - combinational.
//  One write port        - on the rising clock edge.
//
//  WRITE-THROUGH BYPASS: if WB writes register X in the same cycle that
//  ID reads register X, the read port returns the NEW value (wr_data).
//  This covers a producer/consumer distance of 3 instructions.
// =====================================================================
`timescale 1ns/1ps

module regfile (
    input  wire       clk,
    input  wire       rst,
    // read port A (ID)
    input  wire [2:0] ra_addr,
    output wire [7:0] ra_data,
    // read port B (ID)
    input  wire [2:0] rb_addr,
    output wire [7:0] rb_data,
    // write port (WB)
    input  wire       we,
    input  wire [2:0] wr_addr,
    input  wire [7:0] wr_data
);

    reg [7:0] r [0:7];          // r[0] = R0 ... r[7] = R7
    integer   i;

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 8; i = i + 1)
                r[i] <= 8'h00;
        end else if (we) begin
            r[wr_addr] <= wr_data;
        end
    end

    wire bypass_a = we && (wr_addr == ra_addr);
    wire bypass_b = we && (wr_addr == rb_addr);

    assign ra_data = bypass_a ? wr_data : r[ra_addr];
    assign rb_data = bypass_b ? wr_data : r[rb_addr];

endmodule
