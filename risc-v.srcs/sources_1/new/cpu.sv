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

    localparam INST_COUNT = 6;

/* uart rx with interrupt */

    logic [31:0] mem [INST_COUNT] = '{
        32'h40000093, // addi x1, x0, 0x400
        32'h01000113, // addi x2, x0, 16
        32'h0020a623, // sw x2, 0xc(x1)
        32'h0000a183, // _RECV: lw x3, 0x0(x1)
        32'hfe000ee3, // beq x0, x0, _RECV
        32'h00400213  // addi x4, x0, 4
    };

/* 送 16 次 tx */
/*
    logic [31:0] mem [0:INST_COUNT-1] = '{
        32'h40000093, // addi x1, x0, 0x400
        32'h05500113, // addi x2, x0, 0x55
        32'h01000193, // li x3, 16
        32'h0020a223, // _SEND: sw x2, 4(x1)
        32'hfff18193, // addi x3, x3, -1
        32'hfe019ce3, // bne x3, x0, _SEND
        32'h0080a203  // lw x4, 8(x1)
    };
*/
/* test uart rx */
/*
    logic [31:0] mem [0:INST_COUNT-1] = '{
        32'h40000093, // addi x1, x0, 0x400
        32'h0000a183, // _RECV: lw x3, 0x0(x1)
        32'hfe000ee3, // beq x0, x0, _RECV
        32'h00400213, // addi x4, x0, 4
        32'h00500293, // addi x5, x0, 5
        32'h00600313, // addi x6, x0, 6
        32'h00700393  // addi x7, x0, 7
    };
*/

/* read uartlite status register, x3 = 0x404 */
/*
    logic [31:0] mem [0:INST_COUNT-1] = '{
        32'h40000093,
        32'h0080a103,
        32'h002081b3
    };
*/
/*
    logic [31:0] mem [0:INST_COUNT-1] = '{
        32'h00002083, // lw x1, 0(x0)
        32'h00108a63, // beq x1, x1, .L1
        32'h00200113, // addi x2, x0, 2
        32'h00300193, // addi x3, x0, 3
        32'h00400213, // addi x4, x0, 4
        32'h00500293, // addi x5, x0, 5
        32'h00600313  // .L1: addi x6, x0, 6
    };
*/
/* 分開測試EX/MEM hazard、MEM/WB hazard 與 load-use hazard */
/*
    logic [31:0] mem [0:INST_COUNT-1] = '{
        32'h00a00093, // addi   x1, x0, 10  # x1 = 0xa
        32'h00500113, // addi   x2, x0, 5   # x2 = 0x5
        32'h002081b3, // add    x3, x1, x2  # x3 = 0xf
        32'h40218233, // sub    x4, x3, x2  # x4 = 0xa
        32'h00408263, // beq    x1, x4, _NEXT
        32'h003202b3, // _NEXT: add    x5, x4, x3  # x5 = 0x19
        32'h00800313, // addi   x6, x0, 8   # x6 = 8
        32'h00432383, // lw     x7, 4(x6)   # x7 = 0xabc
        32'h00730433  // add    x8, x6, x7  # x8 = 0xac4
    };
*/
/* 從 ram lw, 再直接寫入 sw 到 uart, 並且測試 not taken 的 beq */
/*
    logic [31:0] mem [0:INST_COUNT-1] = '{
        32'h40000093, // _start: addi x1, x0, 0x400
        32'h00002103, // lw x2, 0(x0)
        32'h0020a223, // sw x2, 4(x1)
        32'hfe208ae3, // beq x1, x2, _start
        32'h00110113  // addi x2, x2, 1
    };
*/
    /*從1加到10*/
/*
    logic [31:0] mem [0:INST_COUNT-1] = '{
        32'h00000133,
        32'h00a00093,
        32'h00110133,
        32'hfff08093,
        32'hfe009ce3,
        32'h00202223
    };
*/
/* 測試 x2 會不會被寫入 也就是測試 flush 訊號來的時間對不對 */
/*
    logic [31:0] mem [0:INST_COUNT-1] = '{
        32'h00100093, // _start: addi x1, x0, 1
        32'hfe009ee3, // bne x1,	x0, _start
        32'h00200113  // addi x2, x0, 2
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

    initial begin
        mem[0] = 32'h123;
        mem[1] = 32'h456;
        mem[2] = 32'h789;
        mem[3] = 32'habc;
    end

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
    input logic mem_MemRead,
    input logic mem_MemWrite,
    output logic mem_data_MemRead,
    output logic mem_data_MemWrite,
    output logic mem_uart_MemRead,
    output logic mem_uart_MemWrite
);

    always_comb begin
        if (address < UART_ADDR_OFFSET) begin : RAM
            mem_data_MemRead = mem_MemRead;
            mem_data_MemWrite = mem_MemWrite;
            mem_uart_MemRead = 1'b0;
            mem_uart_MemWrite = 1'b0;
        end else begin : UART
            mem_data_MemRead = 1'b0;
            mem_data_MemWrite = 1'b0;
            mem_uart_MemRead = mem_MemRead;
            mem_uart_MemWrite = mem_MemWrite;
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
    input logic PCWrite,
    input logic [31:0] pc_next,
    output logic [31:0] pc_current
);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            pc_current <= 0;
        end else begin
            if (PCWrite) begin
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
    input logic if_id_Write,
    input logic if_Flush,
    input logic [31:0] if_pc,
    input logic [31:0] if_inst,
    output logic [31:0] id_pc,
    output logic [31:0] id_inst
);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            id_pc <= 32'h0;
            id_inst <= 32'h0;
        end else if (if_Flush) begin
            id_pc <= 32'h0;
            id_inst <= 32'h00000013; // NOP
        end else if (if_id_Write) begin
            id_pc <= if_pc;
            id_inst <= if_inst;
        end
    end

endmodule

module id_ex_pipeline(
    input logic clk,
    input logic rst_n,
    input logic id_ex_Write,
    input logic id_Flush,

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
        end else if (id_Flush) begin
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
            ex_inst <= 32'h00000013; // NOP
            ex_read_data1 <= 0;
            ex_read_data2 <= 0;
            ex_imm32 <= 0;
            ex_funct3 <= 0;
            ex_rd <= 0;
        end else if (id_ex_Write) begin
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
    input logic ex_mem_Write,
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
        end else if (ex_mem_Write) begin
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
    input logic mem_wb_Write,
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
        end else if (mem_wb_Write) begin
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

module hazard_detection_unit(
    input logic ex_MemRead,
    input logic [4:0] ex_rd,
    input logic [4:0] id_rs1,
    input logic [4:0] id_rs2,
    output logic if_id_Write,
    output logic PCWrite,
    output logic hazard_control_mux_sel
);

    always_comb begin
        if (ex_MemRead && (ex_rd == id_rs1 || ex_rd == id_rs2)) begin
            PCWrite = 0;
            if_id_Write = 0;
            hazard_control_mux_sel = 0;
        end else begin
            PCWrite = 1;
            if_id_Write = 1;
            hazard_control_mux_sel = 1;
        end
    end

endmodule

module hazard_mux_2to2(
    input logic sel,
    input logic MemWrite,
    input logic RegWrite,
    output logic mux_MemWrite,
    output logic mux_RegWrite
);

    always_comb begin
        if (sel) begin
            mux_MemWrite = MemWrite;
            mux_RegWrite = RegWrite;
        end else begin
            mux_MemWrite = 1'b0;
            mux_RegWrite = 1'b0;
        end
    end

endmodule

module control_hazard_detection_unit(
    input logic [31:0] ex_inst,
    input logic [31:0] ex_pc,
    input logic [31:0] ex_imm32,
    input logic [31:0] ex_mux3to1_alu_a_out,
    input logic [31:0] ex_mux3to1_alu_b_out,
    output logic if_Flush,
    output logic id_Flush,
    output logic pc_branch_sel,
    output logic [31:0] pc_branch_target
);

    logic branch_taken = 0;

    always_comb begin
        branch_taken      = 1'b0;
        if_Flush          = 1'b0;
        id_Flush          = 1'b0;
        pc_branch_sel     = 1'b0;
        pc_branch_target  = ex_pc;
        case (ex_inst[6:0])
            7'b1100011: begin // branch
                unique case(ex_inst[14:12])
                    3'b000: begin // beq
                        if (ex_mux3to1_alu_a_out == ex_mux3to1_alu_b_out) begin
                            branch_taken = 1;
                        end
                    end
                    3'b001: begin // bne
                        if (ex_mux3to1_alu_a_out != ex_mux3to1_alu_b_out) begin
                            branch_taken = 1;
                        end
                    end
                    default: begin
                    end
                endcase
            end
            default: begin
            end
        endcase

        if (branch_taken) begin
            pc_branch_sel    = 1'b1;              // pc mux 選 branch
            pc_branch_target = ex_pc + ex_imm32;  // 計算好的目標位址
            if_Flush         = 1'b1;              // flush IF 取指
            id_Flush         = 1'b1;              // flush ID 解碼
        end
    end

endmodule

module stall_unit(
    // -------------------
    // 1) hazard_stall : load-use hazard
    // -------------------
    input  logic       ex_MemRead,   // EX 階段有指令正在讀記憶體 (lw)
    input  logic [4:0] ex_rd,        // 該 lw 寫回的暫存器
    input  logic [4:0] id_rs1,       // 下一條指令在 ID 階段的讀取暫存器1
    input  logic [4:0] id_rs2,       // 下一條指令在 ID 階段的讀取暫存器2

    // -------------------
    // 2) mem_stall : memory/uart stall
    // -------------------
    input  logic       mem_uart_MemRead,
    input  logic       mem_uart_MemWrite,
    input  logic       mem_uart_read_data_valid,
    input  logic       mem_uart_write_done,

    // -------------------
    // 輸出：給 pipeline 的各級 write enable
    // 以及控制訊號是否要清 0
    // -------------------
    output logic       hazard_control_mux_sel, // ID 階段控制訊號 mux
    output logic       PCWrite,
    output logic       if_id_Write,
    output logic       id_ex_Write,
    output logic       ex_mem_Write,
    output logic       mem_wb_Write
);

    logic hazard_stall;
    logic mem_stall;

    //==========================================================
    // (1) load-use hazard 偵測
    //==========================================================
    always_comb begin
        hazard_stall = 1'b0;
        if (ex_MemRead && (ex_rd != 0)) begin
            if ((ex_rd == id_rs1) || (ex_rd == id_rs2)) begin
                hazard_stall = 1'b1;
            end
        end
    end

    //==========================================================
    // (2) memory/uart stall 偵測
    //==========================================================
    always_comb begin
        mem_stall = 1'b0;
        // 需要多週期讀
        if (mem_uart_MemRead  && !mem_uart_read_data_valid) begin
            mem_stall = 1'b1;
        end
        // 需要多週期寫
        if (mem_uart_MemWrite && !mem_uart_write_done) begin
            mem_stall = 1'b1;
        end
    end

    //==========================================================
    // (3) 合併結果
    //==========================================================
    // 先判斷 mem_stall (最優先)，如果是 mem_stall 就要整條 pipeline freeze
    // 如果不是 mem_stall，才考慮是否 hazard_stall
    //==========================================================
    always_comb begin
        if (mem_stall) begin
            // === 全部 freeze ===
            PCWrite     = 1'b0;
            if_id_Write = 1'b0;
            id_ex_Write = 1'b0;
            ex_mem_Write= 1'b0;
            mem_wb_Write= 1'b0;

            // hazard_control_mux_sel 不重要了
            // (因為整條 pipeline 都不動, ID 的指令也不會再改變)
            hazard_control_mux_sel = 1'b1; // or 1'b0, both are fine
        end else if (hazard_stall) begin
            // === load-use hazard → freeze 前半段(PC/IF_ID) ===
            PCWrite     = 1'b0;   // freeze PC
            if_id_Write = 1'b0;   // freeze IF/ID
            // 讓後半段繼續
            id_ex_Write = 1'b1;
            ex_mem_Write= 1'b1;
            mem_wb_Write= 1'b1;

            // 另外必須把當前 ID 階段的指令控制訊號清成 NOP
            // 用 hazard_control_mux_sel=0 來達成
            hazard_control_mux_sel = 1'b0;
        end else begin
            // === 無任何 stall ===
            PCWrite     = 1'b1;
            if_id_Write = 1'b1;
            id_ex_Write = 1'b1;
            ex_mem_Write= 1'b1;
            mem_wb_Write= 1'b1;

            hazard_control_mux_sel = 1'b1;
        end
    end

endmodule

module power_on_reset(
    input logic clk,
    input logic btn_reset_n,
    output logic rst_n
);

    localparam RESET_CYCLE = 100;
    integer counter = 0;
    always_ff @(posedge clk) begin
        if (!btn_reset_n) begin
            rst_n <= 0;
            counter <= 0;
        end else if (counter == RESET_CYCLE) begin
            rst_n <= 1;
        end else begin
            rst_n <= 0;
            counter <= counter + 1;
        end
    end

endmodule

module riscv_cpu(
    input logic sys_clk,
    input logic btn_reset_n,
//    input logic uart_rx,
    output wire uart_tx
);

    logic uart_rx = 1;
    localparam integer BIT_PERIOD = 104160;

`ifdef XILINX_SIMULATOR
    logic clk = 0;
    always #10 clk = ~clk;
`else
    wire clk = sys_clk;
`endif

    wire rst_n;
    power_on_reset power_on_reset_0(
        .clk(clk),
        .btn_reset_n(btn_reset_n),
        .rst_n(rst_n)
    );

    initial begin
        #1000;
        send_uart(8'h41);
        #(BIT_PERIOD * 2);
        //$finish;
    end

    task send_uart(input [7:0] data);
        integer i;
        begin
            uart_rx = 0;
            #(BIT_PERIOD);

            for (i = 0; i < 8; i++) begin
                uart_rx = data[i];
                #(BIT_PERIOD);
            end

            uart_rx = 1;
            #(BIT_PERIOD);
        end
    endtask

    wire [31:0] pc_current;
    wire [31:0] pc_next;
    wire [31:0] if_inst;

    wire [31:0] id_pc;
    wire [31:0] id_inst;

    wire if_id_Write;
    wire id_ex_Write;
    wire ex_mem_Write;
    wire mem_wb_Write;
    wire PCWrite;

    wire if_Flush;
    wire id_Flush;
    wire pc_branch_sel;
    wire [31:0] pc_branch_target;

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

    wire mux_id_MemWrite;
    wire mux_id_RegWrite;

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
    wire mem_Branch; // 可以刪掉？
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

    wire mem_data_MemRead;
    wire mem_data_MemWrite;
    wire mem_uart_MemRead;
    wire mem_uart_MemWrite;
    wire mem_uart_read_data_valid;
    wire mem_uart_write_done;
    wire [31:0] mem_memory_read_data;
    wire [31:0] mem_uart_read_data;
    wire [31:0] mem_mux_read_data;

    wire [31:0] wb_reg_write_data;

    wire hazard_control_mux_sel;
    wire PCWrite_final;
    assign PCWrite_final = pc_branch_sel ? 1'b1 : PCWrite;

    program_counter pc_module(
        .clk(clk),
        .rst_n(rst_n),
        .PCWrite(PCWrite_final),
        .pc_next(pc_next),
        .pc_current(pc_current)
    );

    control_hazard_detection_unit branch_unit_0(
        .ex_inst(ex_inst),
        .ex_pc(ex_pc),
        .ex_imm32(ex_imm32),
        .ex_mux3to1_alu_a_out(mux3to1_alu_a_out),
        .ex_mux3to1_alu_b_out(mux3to1_alu_b_out),
        .if_Flush(if_Flush),
        .id_Flush(id_Flush),
        .pc_branch_sel(pc_branch_sel),
        .pc_branch_target(pc_branch_target)
    );

    mux2to1 mux2to1_pc(
        .sel(pc_branch_sel),
        .A(pc_current + 32'd4),
        .B(pc_branch_target),
        .mux_out(pc_next)
    );

    instruction_memory inst_mem(
        .pc(pc_current),
        .inst(if_inst)
    );

    stall_unit stall_unit_0(
        .ex_MemRead(ex_MemRead),
        .ex_rd(ex_rd),
        .id_rs1(id_inst[19:15]),
        .id_rs2(id_inst[24:20]),
        .mem_uart_MemRead(mem_uart_MemRead),
        .mem_uart_MemWrite(mem_uart_MemWrite),
        .mem_uart_read_data_valid(mem_uart_read_data_valid),
        .mem_uart_write_done(mem_uart_write_done),
        .hazard_control_mux_sel(hazard_control_mux_sel),
        .PCWrite(PCWrite),
        .if_id_Write(if_id_Write),
        .id_ex_Write(id_ex_Write),
        .ex_mem_Write(ex_mem_Write),
        .mem_wb_Write(mem_wb_Write)
    );

    hazard_mux_2to2 hazard_mux_2to2_0(
        .sel(hazard_control_mux_sel),
        .MemWrite(id_MemWrite),
        .RegWrite(id_RegWrite),
        .mux_MemWrite(mux_id_MemWrite),
        .mux_RegWrite(mux_id_RegWrite)
    );

    if_id_pipeline if_id_pipeline_0(
        .clk(clk),
        .rst_n(rst_n),
        .if_id_Write(if_id_Write),
        .if_Flush(if_Flush),
        .if_pc(pc_current),
        .if_inst(if_inst),
        .id_pc(id_pc),
        .id_inst(id_inst)
    );

    id_ex_pipeline id_ex_pipeline_0(
        .clk(clk),
        .rst_n(rst_n),
        .id_ex_Write(id_ex_Write),
        .id_Flush(id_Flush),

        .id_ALUSrc(id_ALUSrc),
        .id_MemtoReg(id_MemtoReg),
        .id_RegWrite(mux_id_RegWrite),
        .id_MemRead(id_MemRead),
        .id_MemWrite(mux_id_MemWrite),
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
        .ex_mem_Write(ex_mem_Write),
        .ex_MemtoReg(ex_MemtoReg),
        .ex_RegWrite(ex_RegWrite),
        .ex_Branch(ex_Branch),
        .ex_MemRead(ex_MemRead),
        .ex_MemWrite(ex_MemWrite),
        .ex_pc(ex_pc + ex_imm32),
        .ex_inst(ex_inst),
        .ex_Zero(ex_Zero),
        .ex_alu_out(ex_alu_out),
        .ex_read_data2(mux3to1_alu_b_out),
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
        .mem_wb_Write(mem_wb_Write),
        .mem_RegWrite(mem_RegWrite),
        .mem_MemtoReg(mem_MemtoReg),
        .mem_memory_read_data(mem_mux_read_data),
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

    address_decoder address_decoder_0(
        .address(mem_alu_out),
        .mem_MemRead(mem_MemRead),
        .mem_MemWrite(mem_MemWrite),
        .mem_data_MemRead(mem_data_MemRead),
        .mem_data_MemWrite(mem_data_MemWrite),
        .mem_uart_MemRead(mem_uart_MemRead),
        .mem_uart_MemWrite(mem_uart_MemWrite)
    );

    data_memory data_memory_0(
        .clk(clk),
        .address(mem_alu_out),
        .write_data(mem_read_data2),
        .MemRead(mem_data_MemRead),
        .MemWrite(mem_data_MemWrite),
        .read_data(mem_memory_read_data)
    );

    uart uart_0(
        .clk(clk),
        .rst_n(rst_n),
        .MemRead(mem_uart_MemRead),
        .MemWrite(mem_uart_MemWrite),
        .address(mem_alu_out - UART_ADDR_OFFSET),
        .write_data(mem_read_data2),
        .read_data_valid(mem_uart_read_data_valid),
        .read_data(mem_uart_read_data),
        .write_done(mem_uart_write_done),
        .tx(uart_tx),
        .rx(uart_rx)
    );

    mux2to1 mux2to1_mem_uart(
        .sel(mem_data_MemRead),
        .A(mem_uart_read_data),
        .B(mem_memory_read_data),
        .mux_out(mem_mux_read_data)
    );

endmodule
