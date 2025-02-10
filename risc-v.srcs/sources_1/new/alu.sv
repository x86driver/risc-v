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
            6'b01_?_???: alu_ctrl = 4'b0110; // beq
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

    localparam INST_COUNT = 5;

    logic [31:0] mem [0:INST_COUNT-1] = '{
        32'h00500113,
        32'h00a00193,
        32'h00310233,
        32'h002202b3,
        32'h40328333
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
    always_comb begin
        if ((read_reg1 == write_reg) && RegWrite && (write_reg != 5'b0)) begin
            read_data1 = write_data;
        end else begin
            read_data1 = (read_reg1 == 5'b0) ? 32'h0 : registers[read_reg1];
        end
        if ((read_reg2 == write_reg) && RegWrite && (write_reg != 5'b0)) begin
            read_data2 = write_data;
        end else begin
            read_data2 = (read_reg2 == 5'b0) ? 32'h0 : registers[read_reg2];
        end
    end

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

module mux3to1(
    input logic [1:0] sel,
    input logic [31:0] A,
    input logic [31:0] B,
    input logic [31:0] C,
    output logic [31:0] mux_out
);

    always_comb begin
        unique case (sel)
            2'b00: mux_out = A;
            2'b01: mux_out = B;
            2'b10: mux_out = C;
            default: mux_out = A;
        endcase
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

module if_id_pipeline(
    input logic clk,
    input logic rst_n,
    input logic [31:0] if_pc,
    input logic [31:0] if_inst,
    output logic [31:0] id_pc,
    output logic [31:0] id_inst
);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            id_pc <= 32'h0;
            id_inst <= 32'h0;
        end else begin
            id_pc <= if_pc;
            id_inst <= if_inst;
        end
    end

endmodule

module id_ex_pipeline(
    input logic clk,
    input logic rst_n,

    input logic id_ALUSrc,
    input logic id_MemtoReg,
    input logic id_RegWrite,
    input logic id_MemRead,
    input logic id_MemWrite,
    input logic id_Branch,
    input logic [1:0] id_ALUOp,
    input logic id_isSub,
    input logic id_isValid,

    input logic [31:0] id_pc,
    input logic [31:0] id_inst,
    input logic [31:0] id_read_data1,
    input logic [31:0] id_read_data2,
    input logic [31:0] id_imm32,
    input logic [2:0] id_funct3,
    input logic [4:0] id_rd,

    output logic ex_ALUSrc,
    output logic ex_MemtoReg,
    output logic ex_RegWrite,
    output logic ex_MemRead,
    output logic ex_MemWrite,
    output logic ex_Branch,
    output logic [1:0] ex_ALUOp,
    output logic ex_isSub,
    output logic ex_isValid,

    output logic [31:0] ex_pc,
    output logic [31:0] ex_inst,
    output logic [31:0] ex_read_data1,
    output logic [31:0] ex_read_data2,
    output logic [31:0] ex_imm32,
    output logic [2:0] ex_funct3,
    output logic [4:0] ex_rd
);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            ex_ALUSrc <= 0;
            ex_MemtoReg <= 0;
            ex_RegWrite <= 0;
            ex_MemRead <= 0;
            ex_MemWrite <= 0;
            ex_Branch <= 0;
            ex_ALUOp <= 0;
            ex_isSub <= 0;
            ex_isValid <= 0;

            ex_pc <= 0;
            ex_inst <= 0;
            ex_read_data1 <= 0;
            ex_read_data2 <= 0;
            ex_imm32 <= 0;
            ex_funct3 <= 0;
            ex_rd <= 0;
        end else begin
            ex_ALUSrc <= id_ALUSrc;
            ex_MemtoReg <= id_MemtoReg;
            ex_RegWrite <= id_RegWrite;
            ex_MemRead <= id_MemRead;
            ex_MemWrite <= id_MemWrite;
            ex_Branch <= id_Branch;
            ex_ALUOp <= id_ALUOp;
            ex_isSub <= id_isSub;
            ex_isValid <= id_isValid;

            ex_pc <= id_pc;
            ex_inst <= id_inst;
            ex_read_data1 <= id_read_data1;
            ex_read_data2 <= id_read_data2;
            ex_imm32 <= id_imm32;
            ex_funct3 <= id_funct3;
            ex_rd <= id_rd;
        end
    end

endmodule

module ex_mem_pipeline(
    input logic clk,
    input logic rst_n,
    input logic ex_MemtoReg,
    input logic ex_RegWrite,
    input logic ex_Branch,
    input logic ex_MemRead,
    input logic ex_MemWrite,
    input logic [31:0] ex_pc,
    input logic [31:0] ex_inst,
    input logic ex_Zero,
    input logic [31:0] ex_alu_out,
    input logic [31:0] ex_read_data2,
    input logic [4:0] ex_rd,
    output logic mem_MemtoReg,
    output logic mem_RegWrite,
    output logic mem_Branch,
    output logic mem_MemRead,
    output logic mem_MemWrite,
    output logic [31:0] mem_pc,
    output logic [31:0] mem_inst,
    output logic mem_Zero,
    output logic [31:0] mem_alu_out,
    output logic [31:0] mem_read_data2,
    output logic [4:0] mem_rd
);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            mem_MemtoReg <= 0;
            mem_RegWrite <= 0;
            mem_Branch <= 0;
            mem_MemRead <= 0;
            mem_MemWrite <= 0;
            mem_pc <= 0;
            mem_inst <= 0;
            mem_Zero <= 0;
            mem_alu_out <= 0;
            mem_read_data2 <= 0;
            mem_rd <= 0;
        end else begin
            mem_MemtoReg <= ex_MemtoReg;
            mem_RegWrite <= ex_RegWrite;
            mem_Branch <= ex_Branch;
            mem_MemRead <= ex_MemRead;
            mem_MemWrite <= ex_MemWrite;
            mem_pc <= ex_pc;
            mem_inst <= ex_inst;
            mem_Zero <= ex_Zero;
            mem_alu_out <= ex_alu_out;
            mem_read_data2 <= ex_read_data2;
            mem_rd <= ex_rd;
        end
    end

endmodule

module mem_wb_pipeline(
    input logic clk,
    input logic rst_n,
    input logic mem_RegWrite,
    input logic mem_MemtoReg,
    input logic [31:0] mem_memory_read_data,
    input logic [31:0] mem_alu_out,
    input logic [4:0] mem_rd,
    output logic wb_RegWrite,
    output logic wb_MemtoReg,
    output logic [31:0] wb_memory_read_data,
    output logic [31:0] wb_alu_out,
    output logic [4:0] wb_rd
);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            wb_RegWrite <= 0;
            wb_MemtoReg <= 0;
            wb_memory_read_data <= 0;
            wb_alu_out <= 0;
            wb_rd <= 0;
        end else begin
            wb_RegWrite <= mem_RegWrite;
            wb_MemtoReg <= mem_MemtoReg;
            wb_memory_read_data <= mem_memory_read_data;
            wb_alu_out <= mem_alu_out;
            wb_rd <= mem_rd;
        end
    end

endmodule

module forwarding_unit(
    input logic mem_RegWrite,
    input logic wb_RegWrite,
    input logic [4:0] mem_rd,
    input logic [4:0] wb_rd,
    input logic [4:0] ex_rs1,
    input logic [4:0] ex_rs2,
    output logic [1:0] ForwardA,
    output logic [1:0] ForwardB
);

    always_comb begin
        // ---------------------
        // ForwardA (for ex_rs1)
        // ---------------------
        if (mem_RegWrite && (mem_rd != 0) && (mem_rd == ex_rs1)) begin
            // MEM->EX
            ForwardA = 2'b10;
        end else if (wb_RegWrite && (wb_rd != 0) && (wb_rd == ex_rs1)) begin
            // WB->EX
            ForwardA = 2'b01;
        end else begin
            // No forward
            ForwardA = 2'b00;
        end

        // ---------------------
        // ForwardB (for ex_rs2)
        // ---------------------
        if (mem_RegWrite && (mem_rd != 0) && (mem_rd == ex_rs2)) begin
            // MEM->EX
            ForwardB = 2'b10;
        end else if (wb_RegWrite && (wb_rd != 0) && (wb_rd == ex_rs2)) begin
            // WB->EX
            ForwardB = 2'b01;
        end else begin
            // No forward
            ForwardB = 2'b00;
        end
    end

endmodule

module riscv_cpu(
//    input logic clk,
//    input logic rst_n,
);

    logic clk = 0;
    logic rst_n = 1;
    initial begin
        clk = 0;
    end
    always #10 clk = ~clk;

    wire [31:0] pc_current;
    wire [31:0] pc_next;
    wire [31:0] if_inst;

    wire [31:0] id_pc;
    wire [31:0] id_inst;

    wire mem_PCSrc;

    wire [31:0] id_imm32;
    wire [31:0] ex_imm32;

    wire id_ALUSrc;
    wire id_MemtoReg;
    wire id_RegWrite;
    wire id_MemRead;
    wire id_MemWrite;
    wire id_Branch;
    wire [1:0] id_ALUOp;
    wire id_isSub;
    wire id_isValid;

    wire ex_ALUSrc;
    wire ex_MemtoReg;
    wire ex_RegWrite;
    wire ex_MemRead;
    wire ex_MemWrite;
    wire ex_Branch;
    wire [1:0] ex_ALUOp;
    wire ex_isSub;
    wire ex_isValid;

    wire [2:0] ex_funct3;
    wire [4:0] ex_rd;
    wire [31:0] ex_pc;
    wire [31:0] ex_inst;

    wire [1:0] ForwardA;
    wire [1:0] ForwardB;
    wire [31:0] mux3to1_alu_a_out;
    wire [31:0] mux3to1_alu_b_out;

    wire mem_MemtoReg;
    wire mem_RegWrite;
    wire mem_Branch;
    wire mem_MemRead;
    wire mem_MemWrite;
    wire [31:0] mem_pc;
    wire [31:0] mem_inst;
    wire mem_Zero;
    wire [31:0] mem_alu_out;
    wire [31:0] mem_read_data2;
    wire [4:0] mem_rd;

    wire [31:0] mux_alu_out;

    wire [3:0] alu_ctrl;

    wire ex_Zero;
    wire [31:0] ex_alu_out;

    wire [31:0] id_read_data1;
    wire [31:0] id_read_data2;
    wire [31:0] ex_read_data1;
    wire [31:0] ex_read_data2;

    wire wb_RegWrite;
    wire wb_MemtoReg;
    wire [31:0] wb_memory_read_data;
    wire [31:0] wb_alu_out;
    wire [4:0] wb_rd;

    wire [31:0] mem_memory_read_data;

    wire [31:0] wb_reg_write_data;

    program_counter pc_module(
        .clk(clk),
        .rst_n(rst_n),
        .pc_next(pc_next),
        .pc_current(pc_current)
    );

    branch_unit branch_unit_0(
        .inst(mem_inst),
        .Branch(mem_Branch),
        .zero(mem_Zero),
        .branch_taken(mem_PCSrc)
    );

    mux2to1 mux2to1_pc(
        .sel(mem_PCSrc),
        .A(pc_current + 32'd4),
        .B(mem_pc),
        .mux_out(pc_next)
    );

    instruction_memory inst_mem(
        .pc(pc_current),
        .inst(if_inst)
    );

    if_id_pipeline if_id_pipeline_0(
        .clk(clk),
        .rst_n(rst_n),
        .if_pc(pc_current),
        .if_inst(if_inst),
        .id_pc(id_pc),
        .id_inst(id_inst)
    );

    id_ex_pipeline id_ex_pipeline_0(
        .clk(clk),
        .rst_n(rst_n),

        .id_ALUSrc(id_ALUSrc),
        .id_MemtoReg(id_MemtoReg),
        .id_RegWrite(id_RegWrite),
        .id_MemRead(id_MemRead),
        .id_MemWrite(id_MemWrite),
        .id_Branch(id_Branch),
        .id_ALUOp(id_ALUOp),
        .id_isSub(id_isSub),
        .id_isValid(id_isValid),

        .id_pc(id_pc),
        .id_inst(id_inst),
        .id_read_data1(id_read_data1),
        .id_read_data2(id_read_data2),
        .id_imm32(id_imm32),
        .id_funct3(id_inst[14:12]),
        .id_rd(id_inst[11:7]),

        .ex_ALUSrc(ex_ALUSrc),
        .ex_MemtoReg(ex_MemtoReg),
        .ex_RegWrite(ex_RegWrite),
        .ex_MemRead(ex_MemRead),
        .ex_MemWrite(ex_MemWrite),
        .ex_Branch(ex_Branch),
        .ex_ALUOp(ex_ALUOp),
        .ex_isSub(ex_isSub),
        .ex_isValid(ex_isValid),

        .ex_pc(ex_pc),
        .ex_inst(ex_inst),
        .ex_read_data1(ex_read_data1),
        .ex_read_data2(ex_read_data2),
        .ex_imm32(ex_imm32),
        .ex_funct3(ex_funct3),
        .ex_rd(ex_rd)
    );

    ex_mem_pipeline ex_mem_pipeline0(
        .clk(clk),
        .rst_n(rst_n),
        .ex_MemtoReg(ex_MemtoReg),
        .ex_RegWrite(ex_RegWrite),
        .ex_Branch(ex_Branch),
        .ex_MemRead(ex_MemRead),
        .ex_MemWrite(ex_MemWrite),
        .ex_pc(ex_pc + ex_imm32),
        .ex_inst(ex_inst),
        .ex_Zero(ex_Zero),
        .ex_alu_out(ex_alu_out),
        .ex_read_data2(ex_read_data2),
        .ex_rd(ex_rd),
        .mem_MemtoReg(mem_MemtoReg),
        .mem_RegWrite(mem_RegWrite),
        .mem_Branch(mem_Branch),
        .mem_MemRead(mem_MemRead),
        .mem_MemWrite(mem_MemWrite),
        .mem_pc(mem_pc),
        .mem_inst(mem_inst),
        .mem_Zero(mem_Zero),
        .mem_alu_out(mem_alu_out),
        .mem_read_data2(mem_read_data2),
        .mem_rd(mem_rd)
    );

    mem_wb_pipeline mem_wb_pipeline_0(
        .clk(clk),
        .rst_n(rst_n),
        .mem_RegWrite(mem_RegWrite),
        .mem_MemtoReg(mem_MemtoReg),
        .mem_memory_read_data(mem_memory_read_data),
        .mem_alu_out(mem_alu_out),
        .mem_rd(mem_rd),
        .wb_RegWrite(wb_RegWrite),
        .wb_MemtoReg(wb_MemtoReg),
        .wb_memory_read_data(wb_memory_read_data),
        .wb_alu_out(wb_alu_out),
        .wb_rd(wb_rd)
    );

    imm32_gen imm32_gen_0(
        .inst(id_inst),
        .imm32(id_imm32)
    );

    control_unit controL_unit_0(
        .inst(id_inst),
        .ALUSrc(id_ALUSrc),
        .MemtoReg(id_MemtoReg),
        .RegWrite(id_RegWrite),
        .MemRead(id_MemRead),
        .MemWrite(id_MemWrite),
        .Branch(id_Branch),
        .ALUOp(id_ALUOp),
        .isSub(id_isSub),
        .isValid(id_isValid)
    );

    forwarding_unit forwarding_unit_0(
        .mem_RegWrite(mem_RegWrite),
        .wb_RegWrite(wb_RegWrite),
        .mem_rd(mem_rd),
        .wb_rd(wb_rd),
        .ex_rs1(ex_inst[19:15]),
        .ex_rs2(ex_inst[24:20]),
        .ForwardA(ForwardA),
        .ForwardB(ForwardB)
    );

    alu_control alu_control_0(
        .aluop(ex_ALUOp),
        .isSub(ex_isSub),
        .funct3(ex_funct3),
        .alu_ctrl(alu_ctrl)
    );

    mux3to1 mux3to1_alu_a(
        .sel(ForwardA),
        .A(ex_read_data1),
        .B(wb_reg_write_data),
        .C(mem_alu_out),
        .mux_out(mux3to1_alu_a_out)
    );

    mux3to1 mux3to1_alu_b(
        .sel(ForwardB),
        .A(ex_read_data2),
        .B(wb_reg_write_data),
        .C(mem_alu_out),
        .mux_out(mux3to1_alu_b_out)
    );

    mux2to1 mux2to1_alu(
        .sel(ex_ALUSrc),
        .A(mux3to1_alu_b_out),
        .B(ex_imm32),
        .mux_out(mux_alu_out)
    );

    alu alu_0(
        .alu_ctrl(alu_ctrl),
        .A(mux3to1_alu_a_out),
        .B(mux_alu_out),
        .alu_out(ex_alu_out),
        .zero(ex_Zero)
    );

    register_file reg_file_0(
        .clk(clk),
        .read_reg1(id_inst[19:15]),
        .read_reg2(id_inst[24:20]),
        .write_reg(wb_rd),
        .RegWrite(wb_RegWrite),
        .write_data(wb_reg_write_data),
        .read_data1(id_read_data1),
        .read_data2(id_read_data2)
    );

    mux2to1 mux2to1_memory(
        .sel(wb_MemtoReg),
        .A(wb_alu_out),
        .B(wb_memory_read_data),
        .mux_out(wb_reg_write_data)
    );

    data_memory data_memory_0(
        .clk(clk),
        .address(mem_alu_out),
        .write_data(mem_read_data2),
        .MemRead(mem_MemRead),
        .MemWrite(mem_MemWrite),
        .read_data(mem_memory_read_data)
    );

endmodule
