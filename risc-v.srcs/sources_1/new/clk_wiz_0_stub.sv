`timescale 1ps / 1ps

// Simple stub for Xilinx clk_wiz_0 IP to enable iverilog simulation
module clk_wiz_0(
    output wire clk_out1,
    output wire clk_out2,
    input  wire resetn,
    output wire locked,
    input  wire clk_in1
);
    assign clk_out1 = clk_in1;
    assign clk_out2 = clk_in1;
    assign locked   = resetn;
endmodule


