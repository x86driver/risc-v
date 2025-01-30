`timescale 1ns / 1ps
// Create Date: 01/20/2025 01:31:56 PM

module alu_control(
    input logic [3:0] opcode,
    input logic [1:0] aluop,
    output logic [3:0] alu_ctrl
);

    always_comb begin
        casez ({aluop, opcode})
            6'b00????: alu_ctrl = 4'b0010; // lw, sw
            6'b?1????: alu_ctrl = 4'b0110; // beq
            6'b1?0000: alu_ctrl = 4'b0010; // add
            6'b1?1000: alu_ctrl = 4'b0110; // sub
            6'b1?0111: alu_ctrl = 4'b0000; // and
            6'b1?0110: alu_ctrl = 4'b0001; // or
            default:   alu_ctrl = 4'b0000;
        endcase
    end

endmodule

module alu(
    input logic [3:0] alu_ctrl,
    input logic [31:0] A,
    input logic [31:0] B,
    output logic [31:0] alu_out,
    output logic zero
);

    assign zero = (alu_out == 0);

    always_comb begin
        case (alu_ctrl)
            0: alu_out = A & B;
            1: alu_out = A | B;
            2: alu_out = A + B;
            6: alu_out = A - B;
            default: alu_out = 0;
        endcase
    end

endmodule

module instruction_memory(
    input logic [31:0] pc,
    output logic [31:0] inst
);

    logic [31:0] mem [0:16];
    //assign inst = 32'h00402303; // lw t1,4(zero) # 4
    assign inst = (pc == 0) ? 32'h000000b3 : 32'h00000000;
    //assign inst = mem[pc >> 2];

endmodule

module register_file(
    input logic clk,
    input logic [4:0] read_reg1,
    input logic [4:0] read_reg2,
    input logic [4:0] write_reg,
    input logic RegWrite,
    input logic [31:0] write_data,
    output logic [31:0] read_data1,
    output logic [31:0] read_data2
);

    logic [31:0] registers [0:31];
    assign read_data1 = (read_reg1 == 5'b0) ? 32'h0 : registers[read_reg1];
    assign read_data2 = (read_reg2 == 5'b0) ? 32'h0 : registers[read_reg2];

    always_ff @(posedge clk) begin
        if (RegWrite && (write_reg != 5'b0)) begin
            registers[write_reg] <= write_data;
        end
    end

endmodule

module control_unit(
    input logic [6:0] opcode,
    output logic ALUSrc,
    output logic MemtoReg,
    output logic RegWrite,
    output logic MemRead,
    output logic MemWrite,
    output logic Branch,
    output logic [1:0] ALUOp
);

    always_comb begin
        casez (opcode)
            7'b0110011: begin // R-format
                ALUSrc = 0;
                MemtoReg = 0;
                RegWrite = 1;
                MemRead = 0;
                MemWrite = 0;
                Branch = 0;
                ALUOp = 2'b10;
            end
            7'b0000011: begin // lw
                ALUSrc = 1;
                MemtoReg = 1;
                RegWrite = 1;
                MemRead = 1;
                MemWrite = 0;
                Branch = 0;
                ALUOp = 2'b00;
            end
            7'b0100011: begin // sw
                ALUSrc = 1;
                MemtoReg = 0;
                RegWrite = 0;
                MemRead = 0;
                MemWrite = 1;
                Branch = 0;
                ALUOp = 2'b00;
            end
            7'b1100011: begin // beq
                ALUSrc = 0;
                MemtoReg = 0;
                RegWrite = 0;
                MemRead = 0;
                MemWrite = 0;
                Branch = 1;
                ALUOp = 2'b01;
            end
            default: begin
                ALUSrc = 0;
                MemtoReg = 0;
                RegWrite = 0;
                MemRead = 0;
                MemWrite = 0;
                Branch = 0;
                ALUOp = 2'b00;
            end
        endcase
    end

endmodule

module program_counter(
    input logic clk,
    input logic rst_n,
    input logic pc_sel,
    input logic [31:0] pc_next,
    output logic [31:0] pc_current
);

    logic power_on_reset = 0;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            pc_current <= 0;
        end else begin
            if (pc_sel) begin
                pc_current <= pc_next;
            end else begin
                if (!power_on_reset) begin
                    pc_current <= 0;
                    power_on_reset <= 1'b1;
                end else begin
                    pc_current <= pc_current + 32'd4;
                end
            end
        end
    end

endmodule

module riscv_cpu(
    input logic clk,
    input logic rst_n
);

    logic [31:0] pc_current;
    logic [31:0] inst;

    logic ALUSrc;
    logic MemtoReg;
    logic RegWrite;
    logic MemRead;
    logic MemWrite;
    logic Branch;
    logic [1:0] ALUOp;

    logic [3:0] alu_ctrl;

    logic [31:0] alu_out;
    logic zero;

    logic [31:0] read_data1;
    logic [31:0] read_data2;

    program_counter pc_module(
        .clk(clk),
        .rst_n(rst_n),
        .pc_sel(1'b0),
        .pc_next(32'd0),
        .pc_current(pc_current)
    );

    instruction_memory inst_mem(
        .pc(pc_current),
        .inst(inst)
    );

    control_unit controL_unit_0(
        .opcode(inst[6:0]),
        .ALUSrc(ALUSrc),
        .MemtoReg(MemtoReg),
        .RegWrite(RegWrite),
        .MemRead(MemRead),
        .MemWrite(MemWrite),
        .Branch(Branch),
        .ALUOp(ALUOp)
    );

    alu_control alu_control_0(
        .opcode({inst[30], inst[14:12]}),
        .aluop(ALUOp),
        .alu_ctrl(alu_ctrl)
    );

    alu alu_0(
        .alu_ctrl(alu_ctrl),
        .A(read_data1),
        .B(read_data2), // 應該要有 mux
        .alu_out(alu_out),
        .zero(zero)
    );

    register_file reg_file_0(
        .clk(clk),
        .read_reg1(inst[19:15]),
        .read_reg2(inst[24:20]),
        .write_reg(inst[11:7]),
        .RegWrite(RegWrite),
        .write_data(alu_out), // 應該要有 mux
        .read_data1(read_data1),
        .read_data2(read_data2)
    );

endmodule
