`timescale 1ns / 1ps
// Create Date: 01/20/2025 01:31:56 PM

`include "uart.sv"

parameter UART_ADDR_OFFSET = 32'h0000_0400;

module alu_control(
    input logic [1:0] aluop,
    input logic isSub,
    input logic [2:0] funct3,
    output logic [3:0] alu_ctrl
);

    always_comb begin
        casez ({aluop, isSub, funct3})
            6'b00_?_???: alu_ctrl = 4'b0010; // lw, sw
            6'b?1_?_???: alu_ctrl = 4'b0110; // beq
            6'b1?_0_000: alu_ctrl = 4'b0010; // add
            6'b1?_1_000: alu_ctrl = 4'b0110; // sub
            6'b1?_0_111: alu_ctrl = 4'b0000; // and
            6'b1?_0_110: alu_ctrl = 4'b0001; // or
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

    localparam INST_COUNT = 3;

    logic [31:0] mem [0:INST_COUNT-1] = '{
        32'h40000293,
        32'h04800313,
        32'h0062a023
    };

    /*從1加到10
    logic [31:0] mem [0:INST_COUNT-1] = '{
        32'h00000133,
        32'h00a00093,
        32'h00110133,
        32'hfff08093,
        32'hfe009ce3,
        32'h00202223
    };
*/

    always_comb begin
        if (pc < 4*INST_COUNT) begin
            inst = mem[pc[31:2]];
        end else begin
            inst = 32'h0;
        end
    end
    //assign inst = 32'h00402303; // lw t1,4(zero) # 4
    //assign inst = (pc == 0) ? 32'h000000b3 : 32'h00000000; // add     ra,zero,zero
    //assign inst = (pc == 0) ? 32'h00900093 : 32'h0; // li      ra,9
    //assign inst = mem[pc >> 2];

endmodule

module data_memory(
    input clk,
    input logic [31:0] address,
    input logic [31:0] write_data,
    input logic MemRead,
    input logic MemWrite,
    output logic [31:0] read_data
);

    logic [31:0] mem [0:63];

    always_comb begin
        if (MemRead) begin
            read_data = mem[address[31:2]];
        end else begin
            read_data = 32'h0;
        end
    end

    always_ff @(posedge clk) begin
        if (MemWrite) begin
            mem[address[31:2]] <= write_data;
        end
    end

endmodule

module address_decoder(
    input logic [31:0] address,
    input logic MemRead,
    input logic MemWrite,
    output logic ram_en,
    output logic uart_en
);

    always_comb begin
        if (MemRead || MemWrite) begin
            if (address < UART_ADDR_OFFSET) begin : RAM
                ram_en = 1;
                uart_en = 0;
            end else begin : UART
                ram_en = 0;
                uart_en = 1;
            end
        end else begin
            ram_en = 0;
            uart_en = 0;
        end
    end
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
    input logic [31:0] inst,
    output logic ALUSrc,
    output logic MemtoReg,
    output logic RegWrite,
    output logic MemRead,
    output logic MemWrite,
    output logic Branch,
    output logic [1:0] ALUOp,
    output logic isSub,
    output logic isValid
);

    always_comb begin
        casez (inst[6:0])
            7'b0110011: begin // R-format
                ALUSrc = 0;
                MemtoReg = 0;
                RegWrite = 1;
                MemRead = 0;
                MemWrite = 0;
                Branch = 0;
                ALUOp = 2'b10;
                isSub = ((inst[14:12] == 3'b000) && (inst[30] == 1'b1)) ? 1 : 0; // 避免誤判 sra
                isValid = 1;
            end
            7'b0010011: begin // I-format
                ALUSrc = 1;
                MemtoReg = 0;
                RegWrite = 1;
                MemRead = 0;
                MemWrite = 0;
                Branch = 0;
                ALUOp = 2'b10;
                isSub = 0;
                isValid = 1;
            end
            7'b0000011: begin // lw
                ALUSrc = 1;
                MemtoReg = 1;
                RegWrite = 1;
                MemRead = 1;
                MemWrite = 0;
                Branch = 0;
                ALUOp = 2'b00;
                isSub = 0;
                isValid = 1;
            end
            7'b0100011: begin // sw
                ALUSrc = 1;
                MemtoReg = 0;
                RegWrite = 0;
                MemRead = 0;
                MemWrite = 1;
                Branch = 0;
                ALUOp = 2'b00;
                isSub = 0;
                isValid = 1;
            end
            7'b1100011: begin // beq
                ALUSrc = 0;
                MemtoReg = 0;
                RegWrite = 0;
                MemRead = 0;
                MemWrite = 0;
                Branch = 1;
                ALUOp = 2'b01;
                isSub = 1;
                isValid = 1;
            end
            default: begin
                ALUSrc = 0;
                MemtoReg = 0;
                RegWrite = 0;
                MemRead = 0;
                MemWrite = 0;
                Branch = 0;
                ALUOp = 2'b00;
                isSub = 0;
                isValid = 0;
            end
        endcase
    end

endmodule

module branch_unit(
    input logic [31:0] inst,
    input logic Branch,
    input logic zero,
    output logic branch_taken
);

    always_comb begin
        if (Branch) begin
            unique case(inst[14:12])
                3'b000: // beq
                    branch_taken = zero;
                3'b001: // bne
                    branch_taken = !zero;
                default:
                    branch_taken = 0;
            endcase
        end else begin
            branch_taken = 0;
        end
    end

endmodule

module imm32_gen(
    input logic [31:0] inst,
    output logic [31:0] imm32
);

    always_comb begin
        unique case (inst[6:0])
            7'b0000011, // Load
            7'b0010011: // ALU immediate
                imm32 = {{20{inst[31]}}, inst[31:20]};
            7'b0100011: // Store
                imm32 = {{20{inst[31]}}, inst[31:25], inst[11:7]};
            7'b1100011: // Branch
                imm32 = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
            default:
                imm32 = 32'h0;
        endcase
    end

endmodule

module program_counter(
    input logic clk,
    input logic rst_n,
    input logic [31:0] pc_next,
    output logic [31:0] pc_current
);

    logic power_on_reset = 0;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            pc_current <= 0;
        end else begin
            if (!power_on_reset) begin
                pc_current <= 0;
                power_on_reset <= 1'b1;
            end else begin
                pc_current <= pc_next;
            end
        end
    end

endmodule

module mux2to1(
    input logic sel,
    input logic [31:0] A,
    input logic [31:0] B,
    output logic [31:0] mux_out
);

    always_comb begin
        mux_out = sel ? B : A;
    end

endmodule

module uart_addr_offset(
    input logic [31:0] addr,
    output logic [1:0] uart_addr
);

    logic [31:0] tmp;
    always_comb begin
        tmp = addr - UART_ADDR_OFFSET;
        uart_addr = tmp[3:2];
    end

endmodule

module riscv_cpu(
    input logic clk,
    input logic rst_n,
    output logic uart_tx_pin
);

    logic [31:0] pc_current;
    logic [31:0] pc_next;
    logic [31:0] inst;

    logic branch_taken;

    logic [31:0] imm32;

    logic ALUSrc;
    logic MemtoReg;
    logic RegWrite;
    logic MemRead;
    logic MemWrite;
    logic Branch;
    logic [1:0] ALUOp;
    logic isSub;
    logic isValid;

    logic [31:0] mux_alu_out;

    logic [3:0] alu_ctrl;

    logic [31:0] alu_out;
    logic zero;

    logic [31:0] read_data1;
    logic [31:0] read_data2;

    logic ram_en;
    logic uart_en;

    logic [31:0] memory_read_data;

    logic [31:0] reg_write_data;

    program_counter pc_module(
        .clk(clk),
        .rst_n(rst_n),
        .pc_next(pc_next),
        .pc_current(pc_current)
    );

    branch_unit branch_unit_0(
        .inst(inst),
        .Branch(Branch),
        .zero(zero),
        .branch_taken(branch_taken)
    );

    mux2to1 mux2to1_pc(
        .sel(branch_taken),
        .A(pc_current + 32'd4),
        .B(pc_current + imm32),
        .mux_out(pc_next)
    );

    instruction_memory inst_mem(
        .pc(pc_current),
        .inst(inst)
    );

    imm32_gen imm32_gen_0(
        .inst(inst),
        .imm32(imm32)
    );

    control_unit controL_unit_0(
        .inst(inst),
        .ALUSrc(ALUSrc),
        .MemtoReg(MemtoReg),
        .RegWrite(RegWrite),
        .MemRead(MemRead),
        .MemWrite(MemWrite),
        .Branch(Branch),
        .ALUOp(ALUOp),
        .isSub(isSub),
        .isValid(isValid)
    );

    alu_control alu_control_0(
        .aluop(ALUOp),
        .isSub(isSub),
        .funct3(inst[14:12]),
        .alu_ctrl(alu_ctrl)
    );

    mux2to1 mux2to1_alu(
        .sel(ALUSrc),
        .A(read_data2),
        .B(imm32),
        .mux_out(mux_alu_out)
    );

    alu alu_0(
        .alu_ctrl(alu_ctrl),
        .A(read_data1),
        .B(mux_alu_out),
        .alu_out(alu_out),
        .zero(zero)
    );

    register_file reg_file_0(
        .clk(clk),
        .read_reg1(inst[19:15]),
        .read_reg2(inst[24:20]),
        .write_reg(inst[11:7]),
        .RegWrite(RegWrite),
        .write_data(reg_write_data),
        .read_data1(read_data1),
        .read_data2(read_data2)
    );

    mux2to1 mux2to1_memory(
        .sel(MemtoReg),
        .A(alu_out),
        .B(memory_read_data),
        .mux_out(reg_write_data)
    );

    address_decoder address_decoder_0(
        .address(alu_out),
        .MemRead(MemRead),
        .MemWrite(MemWrite),
        .ram_en(ram_en),
        .uart_en(uart_en)
    );

    data_memory data_memory_0(
        .clk(clk),
        .address(alu_out),
        .write_data(read_data2),
        .MemRead(MemRead && ram_en),
        .MemWrite(MemWrite && ram_en),
        .read_data(memory_read_data)
    );

    logic [1:0] uart_addr;

    uart_addr_offset uart_addr_offset_0(
        .addr(alu_out),
        .uart_addr(uart_addr)
    );

    uart uart_0(
        .clk(clk),
        .rst_n(rst_n),
        .wen(uart_en),
        .addr(uart_addr),
        .wdata(read_data2),
        .tx_pin(uart_tx_pin)
    );

endmodule
