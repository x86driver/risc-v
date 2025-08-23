`timescale 1ps / 1ps

// Minimal UART stub for iverilog simulation
module uart(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        MemRead,
    input  logic        MemWrite,
    input  logic [31:0] address,
    input  logic [31:0] write_data,
    output logic        read_data_valid,
    output logic [31:0] read_data,
    output logic        write_done,
    output logic        tx,
    input  logic        rx
);

    logic [31:0] rx_reg;
    logic [31:0] tx_reg;

    always_comb begin
        tx = 1'b1;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_data        <= 32'h0;
            read_data_valid  <= 1'b0;
            write_done       <= 1'b0;
            rx_reg           <= 32'h0;
            tx_reg           <= 32'h0;
        end else begin
            read_data_valid  <= 1'b0;
            write_done       <= 1'b0;

            if (MemRead) begin
                read_data       <= rx_reg;
                read_data_valid <= 1'b1;
            end
            if (MemWrite) begin
                tx_reg     <= write_data;
                write_done <= 1'b1;
            end
        end
    end

endmodule


