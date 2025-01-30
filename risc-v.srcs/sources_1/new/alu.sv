`timescale 1ns / 1ps
// Create Date: 01/20/2025 01:31:56 PM

module alu_control(
    input logic [3:0] opcode,
    input logic [1:0] aluop,
    output logic [3:0] alu_func
);

    always_comb begin
        casez ({aluop, opcode})
            6'b00????: alu_func = 4'b0010; // lw, sw
            6'b?1????: alu_func = 4'b0110; // beq
            6'b1?0000: alu_func = 4'b0010; // add
            6'b1?1000: alu_func = 4'b0110; // sub
            6'b1?0111: alu_func = 4'b0000; // and
            6'b1?0110: alu_func = 4'b0001; // or
            default:   alu_func = 4'b0000;
        endcase
    end

endmodule
