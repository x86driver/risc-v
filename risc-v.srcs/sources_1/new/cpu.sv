`timescale 1ps / 1ps
// Create Date: 01/20/2025 01:31:56 PM

`ifdef IVERILOG
`include "uart_stub_iverilog.sv"
`else
`include "uart.sv"
`endif
`ifdef XILINX_SIMULATOR
`include "wiredly.v"
`include "ddr3_model.sv"
`endif

parameter UART_ADDR_OFFSET = 32'h0000_0700;
parameter LEDS_ADDR_OFFSET = 32'h0000_0710;

parameter SEL_RAM  = 2'd0;
parameter SEL_UART = 2'd1;
parameter SEL_LEDS = 2'd2;

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
            6'b10_0_000: alu_ctrl = 4'b0010; // add
            6'b10_1_000: alu_ctrl = 4'b0110; // sub
            6'b10_0_111: alu_ctrl = 4'b0000; // and
            6'b10_0_110: alu_ctrl = 4'b0001; // or
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

module data_memory_multicycle(
    input  logic clk,
    input  logic rst_n,

    // IF side
    input  logic        if_pc_MemRead,
    input  logic [31:0] if_pc_address,
    output logic        if_pc_read_data_valid,
    output logic [31:0] if_inst,

    // Data side (MEM stage)
    input  logic        mem_data_MemRead,
    input  logic [31:0] mem_data_address,
    output logic        mem_data_read_data_valid,
    output logic [31:0] mem_data_rdata,

    // Data write
    input  logic        MemWrite,
    input  logic [31:0] write_address,
    input  logic [31:0] write_data,
    output logic        write_done,

    // init / busy
    input  logic        init_calib_complete,
    output logic        if_busy,
    output logic        data_busy
);

    typedef enum logic [3:0] {
        IDLE       = 4'd0,
        WRITE_ADDR = 4'd1,
        WRITE_DATA = 4'd2,
        WRITE_RESP = 4'd3,
        WRITE_DONE = 4'd4,
        READ_ADDR  = 4'd5,
        READ_DATA  = 4'd6,
        READ_DONE  = 4'd7
    } state_t;

    state_t state;

    // 單埠模擬 RAM（用來同時當 i/d，讓 lw 讀到自身指令值）
    // 改為可讀入外部 HEX（每行一個 32-bit 指令，十六進位，不含 0x）
    parameter MEM_WORDS = 1024;

    /* hazard 測試 / 或由外部 HEX 載入 */
    logic [31:0] mem [0:MEM_WORDS-1];
    initial begin : init_memory
        string hexfile;
        if ($value$plusargs("HEX=%s", hexfile)) begin
            $display("[mem] Loading program from %0s", hexfile);
            $readmemh(hexfile, mem);
        end else begin
            // 預設指令
            // hazard test
            /*
            mem[0] = 32'h00a00093; // addi   x1, x0, 10  # x1 = 0xa
            mem[1] = 32'h00500113; // addi   x2, x0, 5   # x2 = 0x5
            mem[2] = 32'h002081b3; // add    x3, x1, x2  # x3 = 0xf
            mem[3] = 32'h40218233; // sub    x4, x3, x2  # x4 = 0xa
            mem[4] = 32'h00408263; // beq    x1, x4, _NEXT
            mem[5] = 32'h003202b3; // _NEXT: add    x5, x4, x3  # x5 = 0x19
            mem[6] = 32'h00800313; // addi   x6, x0, 8   # x6 = 8
            mem[7] = 32'h00432383; // lw     x7, 4(x6)   # x7 = 0x40218233
            mem[8] = 32'h00730433; // add    x8, x6, x7  # x8 = 0x4021823b
            */
            // lw test
/*
            mem[0] = 32'h0000_2083; // lw x1,0(x0)
            mem[1] = 32'h0040_2103; // lw x2,4(x0)
            mem[2] = 32'h0080_2183; // lw x3,8(x0)
            mem[3] = 32'h00c0_2203; // lw x4,12(x0)
            mem[4] = 32'h0100_2283; // lw x5,16(x0)
            mem[5] = 32'h0092_8313; // addi x6,x5,9
*/
            mem[0] = 32'h0000_0133; // _start: add x2, x0, x0
            mem[1] = 32'h00a0_0093; // addi x1, x0, 10
            mem[2] = 32'h0011_0133; // .L1: add x2, x2, x1
            mem[3] = 32'hff08_0093; // addi x1, x1, -1
            mem[4] = 32'hfe00_9ce3; // bne x1, x0, .L1
            mem[5] = 32'h0020_2223; // sw x2, 4(x0)
            mem[6] = 32'h0040_2183; // lw x3, 4(x0)

            // jal test
            /*
            mem[0] = 32'h0090_0093; // addi	x1,x0,9
            mem[1] = 32'h0010_8093; // addi	x1,x1,1
            mem[2] = 32'hffdf_f16f; // jal	x2,4 <incr>
            mem[3] = 32'h00f0_0193; // addi	x3,x0,15
            */
        end
    end

    // 仲裁/握手
    logic        serving_if;       // 1: IF, 0: DATA
    logic        last_was_mem;
    logic [31:0] if_addr_q, data_addr_q;

    // 延遲
    integer counter;

    // 只受理一次當前 MEM 讀請求；在 READ_DONE(data) 解除
    logic mem_req_issued;

    // 把 want_if / want_mem 提前宣告（修正語法錯誤）
    logic want_if, want_mem;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                    <= IDLE;
            counter                  <= 0;
            if_pc_read_data_valid    <= 1'b0;
            mem_data_read_data_valid <= 1'b0;
            if_busy                  <= 1'b0;
            data_busy                <= 1'b0;
            serving_if               <= 1'b0;
            last_was_mem             <= 1'b0;
            write_done               <= 1'b0;
            mem_req_issued           <= 1'b0;
        end else begin
            // 脈衝預設清 0
            if_pc_read_data_valid    <= 1'b0;
            mem_data_read_data_valid <= 1'b0;
            write_done               <= 1'b0;

            case (state)
                IDLE: begin
                    if_busy   <= 1'b0;
                    data_busy <= 1'b0;

                    if (init_calib_complete) begin
                        // 需求判定（修正：宣告已提前，這裡只賦值）
                        want_if  = if_pc_MemRead;                 // 取指永遠想要
                        want_mem = mem_data_MemRead && !mem_req_issued; // 同一筆只受理一次

                        // 公平仲裁：若兩者皆想要，交替服務（避免連續 DATA 造成重發同一筆讀）
                        if (want_if && (!want_mem || last_was_mem)) begin
                            // 服務 IF
                            serving_if <= 1'b1;
                            if_addr_q  <= if_pc_address;
                            if_busy    <= 1'b1;
                            state      <= READ_ADDR;
                        end else if (want_mem) begin
                            // 服務 DATA
                            serving_if      <= 1'b0;
                            data_addr_q     <= mem_data_address;
                            data_busy       <= 1'b1;
                            state           <= READ_ADDR;
                            mem_req_issued  <= 1'b1; // 已受理當前 MEM 讀
                        end
                    end
                end

                // 寫路徑（保留）
                WRITE_ADDR:  state <= WRITE_DATA;
                WRITE_DATA:  begin
                    mem[write_address[31:2]] <= write_data;
                    state <= WRITE_RESP;
                end
                WRITE_RESP:  begin
                    write_done <= 1'b1;
                    state      <= WRITE_DONE;
                end
                WRITE_DONE:  begin
                    state      <= IDLE;
                end

                // 讀路徑
                READ_ADDR: begin
                    state <= READ_DATA;
                end

                READ_DATA: begin
                    if (counter < 2) begin
                        counter <= counter + 1;
                    end else begin
                        counter <= 0;
                        if (serving_if) begin
                            if (if_addr_q[31:2] < MEM_WORDS)
                                if_inst <= mem[if_addr_q[31:2]];
                            else
                                if_inst <= 32'h0;
                            // IF 取指：資料與 valid 同拍
                            if_pc_read_data_valid <= 1'b1;
                        end else begin
                            // Data 路：先完成資料，valid 下一拍在 READ_DONE 才送出，避免與 WB 同拍取到舊資料
                            if (data_addr_q[31:2] < MEM_WORDS)
                                mem_data_rdata <= mem[data_addr_q[31:2]];
                            else
                                mem_data_rdata <= 32'h0;
                            // mem_data_read_data_valid 在 READ_DONE 產生
                        end
                        state <= READ_DONE;
                    end
                end

                READ_DONE: begin
                    if_busy      <= 1'b0;
                    // 保持 data_busy 到本拍結束，確保 mem_data_read_data_valid 與 WB 對齊同一指令
                    data_busy    <= 1'b1;
                    last_was_mem <= ~serving_if;
                    state        <= IDLE;

                    // **關鍵修正**：只要這次服務的是 DATA，就在完成時
                    // 釋放 mem_req_issued，讓下一筆（可能仍是 lw）能被受理
                    if (!serving_if) begin
                        // Data 有效脈衝延後到 READ_DONE 這拍
                        mem_data_read_data_valid <= 1'b1;
                        mem_req_issued <= 1'b0;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule

module address_decoder(
    input logic [31:0] address,
    input logic mem_MemRead,
    input logic mem_MemWrite,
    output logic [1:0] sel,
    output logic memRead_en,
    output logic memWrite_en
);

    always_comb begin
        if (address < UART_ADDR_OFFSET) begin
            sel = SEL_RAM;
        end else if (address < LEDS_ADDR_OFFSET) begin
            sel = SEL_UART;
        end else begin
            sel = SEL_LEDS;
        end
    end

    assign memRead_en  = mem_MemRead;
    assign memWrite_en = mem_MemWrite;

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
    output logic [1:0] ALUSrcA_sel,
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
                ALUSrcA_sel = 2'b00;
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
                ALUSrcA_sel = 2'b00;
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
                ALUSrcA_sel = 2'b00;
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
                ALUSrcA_sel = 2'b00;
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
                ALUSrcA_sel = 2'b00;
                MemtoReg = 0;
                RegWrite = 0;
                MemRead = 0;
                MemWrite = 0;
                Branch = 1;
                ALUOp = 2'b01;
                isSub = 1;
                isValid = 1;
            end
            7'b0110111: begin // lui
                ALUSrc = 1;
                ALUSrcA_sel = 2'b10;
                MemtoReg = 0;
                RegWrite = 1;
                MemRead = 0;
                MemWrite = 0;
                Branch = 0;
                ALUOp = 2'b00; // use add
                isSub = 0;
                isValid = 1;
            end
            7'b0010111: begin // auipc
                ALUSrc = 1;
                ALUSrcA_sel = 2'b01;
                MemtoReg = 0;
                RegWrite = 1;
                MemRead = 0;
                MemWrite = 0;
                Branch = 0;
                ALUOp = 2'b00; // use add
                isSub = 0;
                isValid = 1;
            end
            7'b1101111: begin // jal
                ALUSrc = 1;
                ALUSrcA_sel = 2'b01;
                MemtoReg = 0;
                RegWrite = 1;
                MemRead = 0;
                MemWrite = 0;
                Branch = 1;
                ALUOp = 2'b00; // use add
                isSub = 0;
                isValid = 1;
            end
            default: begin
                ALUSrc = 0;
                ALUSrcA_sel = 2'b00;
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
            7'b0110111, // lui
            7'b0010111: // auipc
                imm32 = {inst[31:12], 12'b0};
            7'b1101111: // jal
                imm32 = 32'h4;
            default:
                imm32 = 32'h0;
        endcase
    end

endmodule

module program_counter(
    input logic clk,
    input logic rst_n,
    input logic PCWrite,
    input logic pc_branch_sel,
    input logic [31:0] pc_branch_target,
    output logic [31:0] pc_current
);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            pc_current <= 0;
        end else begin
            if (PCWrite) begin
                if (pc_branch_sel) begin
                    pc_current <= pc_branch_target;
                end else begin
                    pc_current <= pc_current + 32'd4;
                end
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
    input logic [1:0] id_ALUSrcA_sel,
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
    output logic [1:0] ex_ALUSrcA_sel,
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
            ex_ALUSrcA_sel <= 0;
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
        end else if (id_ex_Write) begin
            if (id_Flush) begin
            // 把「將要進 EX」的那條變成 NOP
            ex_ALUSrc   <= 0;
            ex_ALUSrcA_sel <= 0;
            ex_MemtoReg <= 0;
            ex_RegWrite <= 0;
            ex_MemRead  <= 0;
            ex_MemWrite <= 0;
            ex_Branch   <= 0;
            ex_ALUOp    <= 0;
            ex_isSub    <= 0;
            ex_isValid  <= 0;
            ex_pc       <= 32'b0;
            ex_inst     <= 32'h00000013; // NOP
            ex_read_data1 <= 0;
            ex_read_data2 <= 0;
            ex_imm32    <= 0;
            ex_funct3   <= 0;
            ex_rd       <= 0;
            end else begin
            // 正常寫入
            ex_ALUSrc   <= id_ALUSrc;
            ex_ALUSrcA_sel <= id_ALUSrcA_sel;
            ex_MemtoReg <= id_MemtoReg;
            ex_RegWrite <= id_RegWrite;
            ex_MemRead  <= id_MemRead;
            ex_MemWrite <= id_MemWrite;
            ex_Branch   <= id_Branch;
            ex_ALUOp    <= id_ALUOp;
            ex_isSub    <= id_isSub;
            ex_isValid  <= id_isValid;

            ex_pc       <= id_pc;
            ex_inst     <= id_inst;
            ex_read_data1 <= id_read_data1;
            ex_read_data2 <= id_read_data2;
            ex_imm32    <= id_imm32;
            ex_funct3   <= id_funct3;
            ex_rd       <= id_rd;
            end
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
            // 對於 JAL：把 ex_pc + 4 放在 ALU out，以便寫回 link 值
            if (ex_inst[6:0] == 7'b1101111) begin
                mem_alu_out <= ex_pc + 32'd4;
            end else begin
                mem_alu_out <= ex_alu_out;
            end
            mem_read_data2 <= ex_read_data2;
            // JAL 的目的暫存器為 inst[11:7]
            mem_rd <= (ex_inst[6:0] == 7'b1101111) ? ex_inst[11:7] : ex_rd;

            if (ex_inst[6:0] == 7'b1101111) begin
                $display("DBG[JAL ex->mem] ex_pc=%08x ex_rd=%0d ex_RegWrite=%0d | mem_alu_out=%08x mem_rd=%0d",
                         ex_pc, ex_rd, ex_RegWrite, mem_alu_out, mem_rd);
            end
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
    input logic MemRead,
    output logic mux_MemWrite,
    output logic mux_RegWrite,
    output logic mux_MemRead
);

    always_comb begin
        if (sel) begin
            mux_MemWrite = MemWrite;
            mux_RegWrite = RegWrite;
            mux_MemRead = MemRead;
        end else begin
            mux_MemWrite = 1'b0;
            mux_RegWrite = 1'b0;
            mux_MemRead = 1'b0;
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
    logic is_jal = 0;

    always_comb begin
        branch_taken      = 1'b0;
        if_Flush          = 1'b0;
        id_Flush          = 1'b0;
        pc_branch_sel     = 1'b0;
        is_jal            = 1'b0;
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
            7'b1101111: begin // jal
                branch_taken = 1;
                is_jal = 1;
            end
            default: begin
            end
        endcase

        if (branch_taken) begin
            pc_branch_sel    = 1'b1;              // pc mux 選 branch
            if (is_jal) begin
                pc_branch_target = ex_pc + {{12{ex_inst[31]}}, ex_inst[19:12], ex_inst[20], ex_inst[30:21], 1'b0};
            end else begin
                pc_branch_target = ex_pc + ex_imm32;  // 計算好的目標位址
            end
            if_Flush         = 1'b1;              // flush IF 取指
            id_Flush         = 1'b1;              // flush ID 解碼
        end
    end

endmodule

module stall_unit(
    // clock / reset
    input  logic       clk,
    input  logic       rst_n,

    // -------------------
    // 1) load-use hazard
    // -------------------
    input  logic       ex_MemRead,   // EX 有 lw
    input  logic [4:0] ex_rd,        // 該 lw 寫回的目的暫存器
    input  logic [4:0] id_rs1,       // ID 階段讀取暫存器1
    input  logic [4:0] id_rs2,       // ID 階段讀取暫存器2

    // IF 取指握手
    input  logic       if_pc_MemRead,          // 保留相容（未使用）
    input  logic       if_pc_read_data_valid,  // 指令回傳脈衝

    // -------------------
    // 2) 記憶體 busy 訊號（單埠仲裁）
    // -------------------
    input  logic       if_busy,      // 記憶體目前在服務 IF 取指
    input  logic       data_busy,    // 記憶體目前在服務 Data (lw/sw)

    // -------------------
    // 3) 舊的 data/uart 介面（相容，未使用）
    // -------------------
    input  logic       mem_data_MemRead,
    input  logic       mem_data_MemWrite,
    input  logic       mem_data_read_data_valid,
    input  logic       mem_data_write_done,
    input  logic       mem_uart_MemRead,
    input  logic       mem_uart_MemWrite,
    input  logic       mem_uart_read_data_valid,
    input  logic       mem_uart_write_done,

    // -------------------
    // 4) redirect 狀態（上層 latch 的 redir_valid）
    // -------------------
    input  logic       redir_valid,

    // -------------------
    // 輸出：各級 write enable 與控制訊號 mux
    // -------------------
    output logic       hazard_control_mux_sel, // 0: 把 ID 的控制清成 NOP
    output logic       PCWrite,
    output logic       if_id_Write,
    output logic       id_ex_Write,
    output logic       ex_mem_Write,
    output logic       mem_wb_Write
);

    //==============================
    // (1) load-use hazard 偵測
    //==============================
    logic hazard_stall;
    always_comb begin
        hazard_stall = 1'b0;
        if (ex_MemRead && (ex_rd != 5'd0)) begin
            if ((ex_rd == id_rs1) || (ex_rd == id_rs2)) begin
                hazard_stall = 1'b1;
            end
        end
    end

    //==============================
    // (2) redirect 後丟棄一次舊 IF 回傳
    //  redirect 與 if_busy 同時存在 → 之後第一個 IF valid 要丟
    //==============================
    logic drop_if_once;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            drop_if_once <= 1'b0;
        end else begin
            // 產生一次性的 drop
            if (redir_valid && if_busy)
                drop_if_once <= 1'b1;

            // 真的回來一個 valid 就把 drop 清掉
            if (if_pc_read_data_valid)
                drop_if_once <= 1'b0;
        end
    end

    // 這拍是否「接受」IF 的回傳（寫入 IF/ID & 推進 PC）
    logic take_if_valid;
    always_comb begin
        take_if_valid = if_pc_read_data_valid && !drop_if_once;
    end

    //==============================
    // (3) 合併決策
    // 優先序：data_busy(全凍) > load-use > redirect 立即換PC > 正常
    //==============================
    always_comb begin
        // 預設全部關
        PCWrite               = 1'b0;
        if_id_Write           = 1'b0;
        id_ex_Write           = 1'b0;
        ex_mem_Write          = 1'b0;
        mem_wb_Write          = 1'b0;
        hazard_control_mux_sel= 1'b1; // 預設保持控制

        if (data_busy) begin
            // === 全線 freeze ===
            // 前段全部凍結，只在資料回來當拍允許 WB 寫入（確保 lw 仍能在正確時序提交）
            mem_wb_Write          = mem_data_read_data_valid;

        end else if (hazard_stall) begin
            // === load-use hazard：前半段 freeze + 在 EX 插 NOP 控制 ===
            id_ex_Write           = 1'b1; // 後段繼續流動
            ex_mem_Write          = 1'b1;
            mem_wb_Write          = 1'b1;
            hazard_control_mux_sel= 1'b0; // 把 ID 控制清成 NOP 送入 EX

        end else begin
            // === 正常流動（含 redirect 情況） ===
            id_ex_Write  = 1'b1;
            ex_mem_Write = 1'b1;

            // 對於 Load，只有在資料有效拍才更新 WB；其他指令持續寫入
            if (mem_data_MemRead) begin
                mem_wb_Write = mem_data_read_data_valid;
            end else begin
                mem_wb_Write = 1'b1;
            end

            if (redir_valid) begin
                // 有 redirect → 立刻換 PC；本拍不寫 IF/ID
                PCWrite     = 1'b1;
                if_id_Write = 1'b0;
            end else begin
                // 無 redirect：跟著 IF 回傳節奏前進
                PCWrite     = take_if_valid;
                if_id_Write = take_if_valid;
            end
        end
    end

endmodule

module power_on_reset(
    input logic clk,
    input logic btn_reset_n,
    output logic rst_n
);

    localparam RESET_CYCLE = 10;
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

module leds_ctrl(
    input logic clk,
    input logic rst_n,
    input logic MemRead,
    input logic MemWrite,
    input logic [31:0] write_data,
    output logic [31:0] read_data,
    output logic [7:0] leds
);

    logic [7:0] leds_reg = 8'h0;

    always_comb begin
        read_data = 32'h0;
        if (MemRead) begin
            read_data = {24'b0, leds_reg};
        end else begin
            read_data = 32'h0;
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            leds_reg <= 8'h0;
        end else if (MemWrite) begin
            leds_reg <= write_data[7:0];
        end
    end

    assign leds = leds_reg;

endmodule

module riscv_cpu(
`ifndef XILINX_SIMULATOR
    input sys_clk_i,
`endif
    input logic btn_reset_n,
`ifndef XILINX_SIMULATOR
    inout [15:0]    ddr3_dq,
    inout [1:0]     ddr3_dqs_n,
    inout [1:0]     ddr3_dqs_p,
    output [13:0]   ddr3_addr,
    output [2:0]    ddr3_ba,
    output          ddr3_ras_n,
    output          ddr3_cas_n,
    output          ddr3_we_n,
    output          ddr3_reset_n,
    output [0:0]    ddr3_ck_p,
    output [0:0]    ddr3_ck_n,
    output [0:0]    ddr3_cke,
    output [0:0]    ddr3_cs_n,
    output [1:0]    ddr3_dm,
    output [0:0]    ddr3_odt,
`endif
//    input logic uart_rx,
    output wire uart_tx,
    output logic [7:0] leds
);

    logic uart_rx = 1;
    localparam integer BIT_PERIOD = 104160 * 1000;

`ifdef XILINX_SIMULATOR
    logic sys_clk_i = 0;
    always #10000 sys_clk_i = ~sys_clk_i;
    //always #10 clk = ~clk;
`endif

    wire rst_n = pll_locked;
    wire clk;
    wire clk_200;
    wire pll_locked;
    clk_wiz_0 u_clk_wiz_0 (
        .clk_out1(clk_200),
        .clk_out2(clk),
        .resetn(btn_reset_n),
        .locked(pll_locked),
        .clk_in1(sys_clk_i)
    );

    initial begin
        @(posedge rst_n);
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

    wire [31:0] id_imm32;
    wire [31:0] ex_imm32;

    wire id_ALUSrc;
    wire [1:0] id_ALUSrcA_sel;
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
    wire mux_id_MemRead;

    wire ex_ALUSrc;
    wire [1:0] ex_ALUSrcA_sel;
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
    wire [31:0] mux3to1_alu_a_operand_out;

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

    wire [1:0] address_sel;
    wire memRead_en;
    wire memWrite_en;
    wire mem_data_MemRead;
    wire mem_data_MemWrite;
    wire mem_data_read_data_valid;
    wire mem_data_write_done;
    wire mem_uart_MemRead;
    wire mem_uart_MemWrite;
    wire mem_uart_read_data_valid;
    wire mem_uart_write_done;
    wire mem_leds_MemRead;
    wire mem_leds_MemWrite;
    wire [31:0] mem_memory_read_data;
    wire [31:0] mem_uart_read_data;
    wire [31:0] mem_leds_read_data;
    wire [31:0] mem_mux_read_data;

    wire [31:0] wb_reg_write_data;

    wire [4:0] id_rd;

    assign id_rd = id_inst[11:7];

    wire hazard_control_mux_sel;

    wire        pc_branch_sel_raw;
    wire [31:0] pc_branch_target_raw;

    logic        redir_valid;
    logic [31:0] redir_target;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            redir_valid  <= 1'b0;
            redir_target <= 32'b0;
        end else begin
            // EX 決策到就先記下來
            if (pc_branch_sel_raw) begin
                redir_valid  <= 1'b1;
                redir_target <= pc_branch_target_raw;
            end
            // 真正寫了 PC（PCWrite=1）就把 latch 清掉
            if (redir_valid && PCWrite) begin
                redir_valid <= 1'b0;
            end
        end
    end

    wire        pc_branch_sel     = redir_valid;
    wire [31:0] pc_branch_target  = redir_target;

    program_counter pc_module(
        .clk(clk),
        .rst_n(rst_n),
        .PCWrite(PCWrite),
        .pc_branch_sel(pc_branch_sel),
        .pc_branch_target(pc_branch_target),
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
        .pc_branch_sel(pc_branch_sel_raw),
        .pc_branch_target(pc_branch_target_raw)
    );

    wire if_pc_MemRead;
    wire if_pc_read_data_valid;
    assign if_pc_MemRead = 1'b1;

    wire if_busy, data_busy;

    stall_unit stall_unit_0(
        .clk(clk),
        .rst_n(rst_n),
        .redir_valid(redir_valid),
        .ex_MemRead(ex_MemRead),
        .ex_rd(ex_rd),
        .id_rs1(id_inst[19:15]),
        .id_rs2(id_inst[24:20]),
        .if_pc_MemRead(if_pc_MemRead),
        .if_pc_read_data_valid(if_pc_read_data_valid),
        .mem_data_MemRead(mem_data_MemRead),
        .mem_data_MemWrite(mem_data_MemWrite),
        .mem_data_read_data_valid(mem_data_read_data_valid),
        .mem_data_write_done(mem_data_write_done),
        .mem_uart_MemRead(mem_uart_MemRead),
        .mem_uart_MemWrite(mem_uart_MemWrite),
        .mem_uart_read_data_valid(mem_uart_read_data_valid),
        .mem_uart_write_done(mem_uart_write_done),
        .hazard_control_mux_sel(hazard_control_mux_sel),
        .PCWrite(PCWrite),
        .if_id_Write(if_id_Write),
        .id_ex_Write(id_ex_Write),
        .ex_mem_Write(ex_mem_Write),
        .mem_wb_Write(mem_wb_Write),
        .if_busy(if_busy),
        .data_busy(data_busy)
    );

    hazard_mux_2to2 hazard_mux_2to2_0(
        .sel(hazard_control_mux_sel),
        .MemWrite(id_MemWrite),
        .RegWrite(id_RegWrite),
        .MemRead(id_MemRead),
        .mux_MemWrite(mux_id_MemWrite),
        .mux_RegWrite(mux_id_RegWrite),
        .mux_MemRead(mux_id_MemRead)
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
        .id_ALUSrcA_sel(id_ALUSrcA_sel),
        .id_MemtoReg(id_MemtoReg),
        .id_RegWrite(mux_id_RegWrite),
        .id_MemRead(mux_id_MemRead),
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
        .id_rd(id_rd),

        .ex_ALUSrc(ex_ALUSrc),
        .ex_ALUSrcA_sel(ex_ALUSrcA_sel),
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
        .ex_pc(ex_pc),
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
        .ALUSrcA_sel(id_ALUSrcA_sel),
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

    mux3to1 mux3to1_alu_a_operand(
        .sel(ex_ALUSrcA_sel),
        .A(mux3to1_alu_a_out),
        .B(ex_pc),
        .C(32'h0),
        .mux_out(mux3to1_alu_a_operand_out)
    );

    mux2to1 mux2to1_alu(
        .sel(ex_ALUSrc),
        .A(mux3to1_alu_b_out),
        .B(ex_imm32),
        .mux_out(mux_alu_out)
    );

    alu alu_0(
        .alu_ctrl(alu_ctrl),
        .A(mux3to1_alu_a_operand_out),
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
        .sel(address_sel),
        .memRead_en(memRead_en),
        .memWrite_en(memWrite_en)
    );

    data_memory_multicycle data_memory_multicycle_0(
        .clk(clk),
        .rst_n(rst_n),
        .if_pc_MemRead(if_pc_MemRead),
        .if_pc_address(pc_current),
        .if_pc_read_data_valid(if_pc_read_data_valid),
        .if_inst(if_inst),

        .mem_data_MemRead(mem_data_MemRead),
        .mem_data_address(mem_alu_out),
        .mem_data_read_data_valid(mem_data_read_data_valid),
        .mem_data_rdata(mem_memory_read_data),

        .MemWrite(mem_data_MemWrite),
        .write_address(mem_alu_out),
        .write_data(mem_read_data2),
        .write_done(mem_data_write_done),
        .init_calib_complete(1'b1),
        .if_busy(if_busy),
        .data_busy(data_busy)
    );

    assign mem_uart_MemRead = memRead_en && address_sel == SEL_UART;
    assign mem_uart_MemWrite = memWrite_en && address_sel == SEL_UART;
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

    assign mem_leds_MemRead = memRead_en && address_sel == SEL_LEDS;
    assign mem_leds_MemWrite = memWrite_en && address_sel == SEL_LEDS;
    leds_ctrl leds_ctrl_0(
        .clk(clk),
        .rst_n(rst_n),
        .MemRead(mem_leds_MemRead),
        .MemWrite(mem_leds_MemWrite),
        .write_data(mem_read_data2),
        .read_data(mem_leds_read_data),
        .leds(leds)
    );

    mux3to1 mux3to1_mem_address(
        .sel(address_sel),
        .A(mem_memory_read_data),
        .B(mem_uart_read_data),
        .C(mem_leds_read_data),
        .mux_out(mem_mux_read_data)
    );


    // DDR3
    parameter DQ_WIDTH              = 16;
    parameter DQS_WIDTH             = 2;
    parameter ROW_WIDTH             = 14;
    parameter CS_WIDTH              = 1;
    parameter DM_WIDTH              = 2;
    parameter ODT_WIDTH             = 1;
    localparam MEMORY_WIDTH            = 16;
    localparam NUM_COMP                = DQ_WIDTH/MEMORY_WIDTH;
    localparam RESET_PERIOD            = 200000; //in pSec

    wire                               init_calib_complete;

`ifdef XILINX_SIMULATOR
    wire                               ddr3_reset_n;
    wire [DQ_WIDTH-1:0]                ddr3_dq_fpga;
    wire [DQS_WIDTH-1:0]               ddr3_dqs_p_fpga;
    wire [DQS_WIDTH-1:0]               ddr3_dqs_n_fpga;
    wire [ROW_WIDTH-1:0]               ddr3_addr_fpga;
    wire [3-1:0]                       ddr3_ba_fpga;
    wire                               ddr3_ras_n_fpga;
    wire                               ddr3_cas_n_fpga;
    wire                               ddr3_we_n_fpga;
    wire [1-1:0]                       ddr3_cke_fpga;
    wire [1-1:0]                       ddr3_ck_p_fpga;
    wire [1-1:0]                       ddr3_ck_n_fpga;

    wire [(CS_WIDTH*1)-1:0]            ddr3_cs_n_fpga;

    wire [DM_WIDTH-1:0]                ddr3_dm_fpga;

    wire [ODT_WIDTH-1:0]               ddr3_odt_fpga;

    reg [(CS_WIDTH*1)-1:0]             ddr3_cs_n_sdram_tmp;

    reg [DM_WIDTH-1:0]                 ddr3_dm_sdram_tmp;

    reg [ODT_WIDTH-1:0]                ddr3_odt_sdram_tmp;

    wire [DQ_WIDTH-1:0]                ddr3_dq_sdram;
    reg [ROW_WIDTH-1:0]                ddr3_addr_sdram [0:1];
    reg [3-1:0]                        ddr3_ba_sdram [0:1];
    reg                                ddr3_ras_n_sdram;
    reg                                ddr3_cas_n_sdram;
    reg                                ddr3_we_n_sdram;
    wire [(CS_WIDTH*1)-1:0]            ddr3_cs_n_sdram;
    wire [ODT_WIDTH-1:0]               ddr3_odt_sdram;
    reg [1-1:0]                        ddr3_cke_sdram;
    wire [DM_WIDTH-1:0]                ddr3_dm_sdram;
    wire [DQS_WIDTH-1:0]               ddr3_dqs_p_sdram;
    wire [DQS_WIDTH-1:0]               ddr3_dqs_n_sdram;
    reg [1-1:0]                        ddr3_ck_p_sdram;
    reg [1-1:0]                        ddr3_ck_n_sdram;
`endif

    assign mem_data_MemRead = memRead_en && address_sel == SEL_RAM;
    assign mem_data_MemWrite = memWrite_en && address_sel == SEL_RAM;
/*
    ddr3_ram ddr3_ram_0(
        .clk_50(clk),
        .clk_200(clk_200),
        .pll_locked(pll_locked),
        .rst_n(rst_n),
        .MemRead(mem_data_MemRead),
        .MemWrite(mem_data_MemWrite),
        .address(mem_alu_out),
        .write_data(mem_read_data2),
        .read_data_valid(mem_data_read_data_valid),
        .read_data(mem_memory_read_data),
        .write_done(mem_data_write_done),
        .init_calib_complete(init_calib_complete),

`ifdef XILINX_SIMULATOR
        .ddr3_dq(ddr3_dq_fpga),
        .ddr3_dqs_n(ddr3_dqs_n_fpga),
        .ddr3_dqs_p(ddr3_dqs_p_fpga),
        .ddr3_addr(ddr3_addr_fpga),
        .ddr3_ba(ddr3_ba_fpga),
        .ddr3_ras_n(ddr3_ras_n_fpga),
        .ddr3_cas_n(ddr3_cas_n_fpga),
        .ddr3_we_n(ddr3_we_n_fpga),
        .ddr3_reset_n(ddr3_reset_n),
        .ddr3_ck_p(ddr3_ck_p_fpga),
        .ddr3_ck_n(ddr3_ck_n_fpga),
        .ddr3_cke(ddr3_cke_fpga),
        .ddr3_cs_n(ddr3_cs_n_fpga),
        .ddr3_dm(ddr3_dm_fpga),
        .ddr3_odt(ddr3_odt_fpga)
`else
        .ddr3_dq(ddr3_dq),
        .ddr3_dqs_n(ddr3_dqs_n),
        .ddr3_dqs_p(ddr3_dqs_p),
        .ddr3_addr(ddr3_addr),
        .ddr3_ba(ddr3_ba),
        .ddr3_ras_n(ddr3_ras_n),
        .ddr3_cas_n(ddr3_cas_n),
        .ddr3_we_n(ddr3_we_n),
        .ddr3_reset_n(ddr3_reset_n),
        .ddr3_ck_p(ddr3_ck_p),
        .ddr3_ck_n(ddr3_ck_n),
        .ddr3_cke(ddr3_cke),
        .ddr3_cs_n(ddr3_cs_n),
        .ddr3_dm(ddr3_dm),
        .ddr3_odt(ddr3_odt)
`endif
    );
*/

`ifdef XILINX_SIMULATOR
    always @( * ) begin
        ddr3_ck_p_sdram      <=  ddr3_ck_p_fpga;
        ddr3_ck_n_sdram      <=  ddr3_ck_n_fpga;
        ddr3_addr_sdram[0]   <=  ddr3_addr_fpga;
        ddr3_addr_sdram[1]   <=  ddr3_addr_fpga;
        ddr3_ba_sdram[0]     <=  ddr3_ba_fpga;
        ddr3_ba_sdram[1]     <=  ddr3_ba_fpga;
        ddr3_ras_n_sdram     <=  ddr3_ras_n_fpga;
        ddr3_cas_n_sdram     <=  ddr3_cas_n_fpga;
        ddr3_we_n_sdram      <=  ddr3_we_n_fpga;
        ddr3_cke_sdram       <=  ddr3_cke_fpga;
    end

    always @( * )
        ddr3_cs_n_sdram_tmp   <=  ddr3_cs_n_fpga;
    assign ddr3_cs_n_sdram =  ddr3_cs_n_sdram_tmp;

    always @( * )
        ddr3_dm_sdram_tmp <=  ddr3_dm_fpga;//DM signal generation
    assign ddr3_dm_sdram = ddr3_dm_sdram_tmp;

    always @( * )
        ddr3_odt_sdram_tmp  <=  ddr3_odt_fpga;
    assign ddr3_odt_sdram =  ddr3_odt_sdram_tmp;

    genvar dqwd;
    generate
        for (dqwd = 1;dqwd < DQ_WIDTH;dqwd = dqwd+1) begin : dq_delay
        WireDelay
        u_delay_dq
        (
            .A             (ddr3_dq_fpga[dqwd]),
            .B             (ddr3_dq_sdram[dqwd]),
            .reset         (rst_n),
            .phy_init_done (init_calib_complete)
        );
        end
        WireDelay
        u_delay_dq_0
        (
            .A             (ddr3_dq_fpga[0]),
            .B             (ddr3_dq_sdram[0]),
            .reset         (rst_n),
            .phy_init_done (init_calib_complete)
        );
    endgenerate

    genvar dqswd;
    generate
        for (dqswd = 0;dqswd < DQS_WIDTH;dqswd = dqswd+1) begin : dqs_delay
        WireDelay
        u_delay_dqs_p
        (
            .A             (ddr3_dqs_p_fpga[dqswd]),
            .B             (ddr3_dqs_p_sdram[dqswd]),
            .reset         (rst_n),
            .phy_init_done (init_calib_complete)
        );

        WireDelay
        u_delay_dqs_n
        (
            .A             (ddr3_dqs_n_fpga[dqswd]),
            .B             (ddr3_dqs_n_sdram[dqswd]),
            .reset         (rst_n),
            .phy_init_done (init_calib_complete)
        );
        end
    endgenerate

    genvar r,i;
    generate
        for (r = 0; r < CS_WIDTH; r = r + 1) begin: mem_rnk
        if (DQ_WIDTH/16) begin: mem
            for (i = 0; i < NUM_COMP; i = i + 1) begin: gen_mem
            ddr3_model u_comp_ddr3
                (
                .rst_n   (ddr3_reset_n),
                .ck      (ddr3_ck_p_sdram),
                .ck_n    (ddr3_ck_n_sdram),
                .cke     (ddr3_cke_sdram[r]),
                .cs_n    (ddr3_cs_n_sdram[r]),
                .ras_n   (ddr3_ras_n_sdram),
                .cas_n   (ddr3_cas_n_sdram),
                .we_n    (ddr3_we_n_sdram),
                .dm_tdqs (ddr3_dm_sdram[(2*(i+1)-1):(2*i)]),
                .ba      (ddr3_ba_sdram[r]),
                .addr    (ddr3_addr_sdram[r]),
                .dq      (ddr3_dq_sdram[16*(i+1)-1:16*(i)]),
                .dqs     (ddr3_dqs_p_sdram[(2*(i+1)-1):(2*i)]),
                .dqs_n   (ddr3_dqs_n_sdram[(2*(i+1)-1):(2*i)]),
                .tdqs_n  (),
                .odt     (ddr3_odt_sdram[r])
                );
            end
        end
        if (DQ_WIDTH%16) begin: gen_mem_extrabits
            ddr3_model u_comp_ddr3
            (
            .rst_n   (ddr3_reset_n),
            .ck      (ddr3_ck_p_sdram),
            .ck_n    (ddr3_ck_n_sdram),
            .cke     (ddr3_cke_sdram[r]),
            .cs_n    (ddr3_cs_n_sdram[r]),
            .ras_n   (ddr3_ras_n_sdram),
            .cas_n   (ddr3_cas_n_sdram),
            .we_n    (ddr3_we_n_sdram),
            .dm_tdqs ({ddr3_dm_sdram[DM_WIDTH-1],ddr3_dm_sdram[DM_WIDTH-1]}),
            .ba      (ddr3_ba_sdram[r]),
            .addr    (ddr3_addr_sdram[r]),
            .dq      ({ddr3_dq_sdram[DQ_WIDTH-1:(DQ_WIDTH-8)],
                        ddr3_dq_sdram[DQ_WIDTH-1:(DQ_WIDTH-8)]}),
            .dqs     ({ddr3_dqs_p_sdram[DQS_WIDTH-1],
                        ddr3_dqs_p_sdram[DQS_WIDTH-1]}),
            .dqs_n   ({ddr3_dqs_n_sdram[DQS_WIDTH-1],
                        ddr3_dqs_n_sdram[DQS_WIDTH-1]}),
            .tdqs_n  (),
            .odt     (ddr3_odt_sdram[r])
            );
        end
        end
    endgenerate
`endif

endmodule
