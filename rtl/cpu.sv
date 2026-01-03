`timescale 1ps / 1ps
// Create Date: 01/20/2025 01:31:56 PM

`include "uart.sv"
// `ifdef XILINX_SIMULATOR
// `include "wiredly.v"
// `include "ddr3_model.sv"
// `endif

parameter UART_ADDR_OFFSET = 32'h0000_0700;
parameter LEDS_ADDR_OFFSET = 32'h0000_0710;

parameter SEL_RAM  = 2'd0;
parameter SEL_UART = 2'd1;
parameter SEL_LEDS = 2'd2;

module alu_control(
    input logic [1:0] aluop,
    input logic isSub,
    input logic inst30,
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
            6'b10_0_100: alu_ctrl = 4'b0100; // xor
            6'b10_0_001: alu_ctrl = 4'b0101; // sll
            6'b10_0_101: alu_ctrl = inst30 ? 4'b0011 : 4'b0111; // sra/srl
            6'b10_0_010: alu_ctrl = 4'b1000; // slt
            6'b10_0_011: alu_ctrl = 4'b1001; // sltu
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
            3: alu_out = $signed(A) >>> B[4:0];
            4: alu_out = A ^ B;
            5: alu_out = A << B[4:0];
            6: alu_out = A - B;
            7: alu_out = A >> B[4:0];
            8: alu_out = ($signed(A) < $signed(B)) ? 1 : 0;
            9: alu_out = ($unsigned(A) < $unsigned(B)) ? 1 : 0;
            default: alu_out = 0;
        endcase
    end

endmodule

module instruction_memory_multicycle(
    input logic clk,
    input logic rst_n,
    input logic MemRead,
    input logic MemWrite,
    input logic [31:0] address,
    input logic [31:0] write_data,
    output logic read_data_valid,
    output logic [31:0] read_data,
    output logic write_done,
    input logic init_calib_complete
);

    typedef enum logic [2:0] {
        IDLE           = 3'd0,  // 空閒狀態
        READ_ADDR      = 3'd1,  // 發送讀地址（Block RAM 接收地址）
        READ_WAIT      = 3'd2,  // 等待 Block RAM 輸出（Block RAM 需要 1 週期延遲）
        READ_DATA      = 3'd3,  // 接收讀數據
        READ_VALID     = 3'd4   // 保持 valid 直到地址變化
    } state_t;

    state_t state;  // 當前狀態
    logic [31:0] last_address;  // 記錄上次讀取的地址
    logic read_data_valid_reg;  // 寄存器版本

    // NOTE (simulation robustness):
    // - We index instruction memory with address[15:2] (word index up to 16K entries).
    // - Keep the backing array large enough so $readmemh() doesn't overflow and
    //   so typical RV32 test images placed at 0x8000_0000.. can execute without
    //   out-of-bounds array accesses in Verilator/Icarus.
    localparam INST_COUNT = 16384;

    logic [31:0] mem [INST_COUNT];

`ifndef IVERILOG
    wire [31:0] douta;
    blk_mem_gen_0 blk_inst_memory_0 (
        .clka(clk),
        .addra(32'({2'b00, address[31:2]})),
        .douta(douta)
    );
`endif

    // 組合邏輯：當地址變化時，立即無效化 read_data_valid
    assign read_data_valid = read_data_valid_reg && (address == last_address);
    assign write_done = 1'b0;  // 這個模組不支持寫入

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            read_data <= 0;
            read_data_valid_reg <= 0;
            last_address <= 32'hFFFFFFFF;  // 無效地址
        end else begin
            case (state)
                IDLE: begin
                    read_data_valid_reg <= 0;
                    if (init_calib_complete && MemRead) begin
                        state <= READ_ADDR;
                    end
                end

                READ_ADDR: begin
                    // 地址已經送到 Block RAM，等待一個週期
                    read_data_valid_reg <= 0;
`ifdef IVERILOG
                    // Icarus: 內存是組合邏輯，可以直接讀取
                    state <= READ_DATA;
`else
                    // Vivado: Block RAM 需要一個週期延遲
                    state <= READ_WAIT;
`endif
                end

                READ_WAIT: begin
                    // 這個狀態只在 Vivado 中使用，等待 Block RAM 輸出
                    read_data_valid_reg <= 0;
                    state <= READ_DATA;
                end

                READ_DATA: begin
`ifdef IVERILOG
                    read_data <= mem[address[15:2]];
`else
                    read_data <= douta;
`endif
                    read_data_valid_reg <= 1;
                    last_address <= address;
                    state <= READ_VALID;  // 進入保持狀態
                end

                READ_VALID: begin
                    // 當地址變化時，重新讀取
                    if (address != last_address) begin
                        read_data_valid_reg <= 0;
                        state <= READ_ADDR;
                    end
                    // 地址不變時，read_data_valid_reg 保持 1
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule

module data_memory_multicycle(
    input logic clk,
    input logic rst_n,
    input logic MemRead,
    input logic MemWrite,
    input logic [2:0] funct3,
    input logic [31:0] address,
    input logic [31:0] write_data,
    output logic read_data_valid,
    output logic [31:0] read_data,
    output logic write_done,
    input logic init_calib_complete
);

    typedef enum logic [3:0] {
        IDLE           = 4'd0,  // 空閒狀態
        WRITE_ADDR     = 4'd1,  // 發送寫地址
        WRITE_DATA     = 4'd2,  // 發送寫數據
        WRITE_RESP     = 4'd3,  // 等待寫響應
        WRITE_DONE     = 4'd4,
        READ_ADDR      = 4'd5,  // 發送讀地址
        READ_DATA      = 4'd6,  // 接收讀數據
        READ_DONE      = 4'd7
    } state_t;

    state_t state;  // 當前狀態

    // NOTE (simulation robustness):
    // - We index data memory with address[15:2] (word index up to 16K entries).
    // - Make the backing array cover the full address[15:2] range to avoid
    //   out-of-bounds accesses during simulation.
    localparam DATA_COUNT = 16384;
    logic [31:0] mem [DATA_COUNT];

`ifndef IVERILOG
    wire [31:0] douta;
    blk_mem_gen_4k blk_mem_gen_4k_0(
        .clka(clk),
        .addra(address[31:2]),
        .dina(write_data),
        .douta(douta),
        .wea(MemWrite)
    );
`endif

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            read_data <= 0;
            read_data_valid <= 0;
            write_done <= 0;
        end else begin
            case (state)
                IDLE: begin
                    read_data_valid <= 0;
                    write_done <= 0;
                    if (init_calib_complete) begin
                        if (MemRead) begin
                            state <= READ_ADDR;
                        end else if (MemWrite) begin
                            state <= WRITE_ADDR;
                        end else begin
                            state <= IDLE;
                        end
                    end
                end

                WRITE_ADDR: begin
                    state <= WRITE_DATA;
                end

                WRITE_DATA: begin
`ifdef IVERILOG
                    if (funct3 == 3'b000) begin // sb
                        mem[address[15:2]][address[1:0]*8 +: 8] <= write_data[7:0];
                    end else if (funct3 == 3'b001) begin // sh
                        mem[address[15:2]][address[1]*16 +: 16] <= write_data[15:0];
                    end else if (funct3 == 3'b010) begin // sw
                        mem[address[15:2]] <= write_data;
                    end
`endif
                    state <= WRITE_RESP;
                end

                WRITE_RESP: begin
                    write_done <= 1;
                    state <= WRITE_DONE;
                end

                WRITE_DONE: begin
                    write_done <= 0;
                    state <= IDLE;
                end

                READ_ADDR: begin
                    state <= READ_DATA;
                end

                READ_DATA: begin
                    // 使用位址位移擷取對應 byte/halfword（小端序）
                    logic [31:0] word;
                    logic [7:0]  byte_sel;
                    logic [15:0] half_sel;
`ifdef IVERILOG
                    word = mem[address[15:2]];
`else
                    word = douta;
`endif
                    byte_sel = word[address[1:0]*8 +: 8];
                    half_sel = address[1] ? word[31:16] : word[15:0];

                    if (funct3 == 3'b000) begin // lb
                        read_data <= {{24{byte_sel[7]}}, byte_sel};
                    end else if (funct3 == 3'b001) begin // lh
                        read_data <= {{16{half_sel[15]}}, half_sel};
                    end else if (funct3 == 3'b010) begin // lw
                        read_data <= word;
                    end else if (funct3 == 3'b100) begin // lbu
                        read_data <= {24'b0, byte_sel};
                    end else if (funct3 == 3'b101) begin // lhu
                        read_data <= {16'b0, half_sel};
                    end else begin
                        read_data <= word;
                    end
                    read_data_valid <= 1;
                    state <= READ_DONE;
                end

                READ_DONE: begin
                    read_data_valid <= 0;
                    state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                end
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
        // Default mapping: treat everything as RAM, except small MMIO windows.
        if ((address >= UART_ADDR_OFFSET) && (address < LEDS_ADDR_OFFSET)) begin
            sel = SEL_UART;
        end else if ((address >= LEDS_ADDR_OFFSET) && (address < (LEDS_ADDR_OFFSET + 32'h10))) begin
            sel = SEL_LEDS;
        end else begin
            sel = SEL_RAM;
        end
    end

    assign memRead_en  = mem_MemRead;
    assign memWrite_en = mem_MemWrite;

endmodule

module register_file(
    input logic clk,
    input logic rst_n,
    input logic [4:0] read_reg1,
    input logic [4:0] read_reg2,
    input logic [4:0] write_reg,
    input logic RegWrite,
    input logic [31:0] write_data,
    output logic [31:0] read_data1,
    output logic [31:0] read_data2
);

    logic [31:0] registers [0:31];
    
    // 初始化寄存器（用於仿真）
    initial begin
        for (int i = 0; i < 32; i++) begin
            registers[i] = 32'h0;
        end
    end
    
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

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 32; i++) begin
                registers[i] <= 32'h0;
            end
        end else if (RegWrite && (write_reg != 5'b0)) begin
            registers[write_reg] <= write_data;
        end
    end

endmodule

typedef struct packed {
    logic        SD;        // [31]    Dirty summary
    logic [7:0]  _reserved1;// [30:23] Reserved (WPRI)
    logic        TSR;       // [22]    Trap SRET
    logic        TW;        // [21]    Timeout Wait
    logic        TVM;       // [20]    Trap Virtual Memory
    logic        MXR;       // [19]    Make eXecutable Readable
    logic        SUM;       // [18]    permit Supervisor User Memory access
    logic        MPRV;      // [17]    Modify PRiVilege
    logic [1:0]  XS;        // [16:15] user eXtension Status
    logic [1:0]  FS;        // [14:13] Floating-point Status
    logic [1:0]  MPP;       // [12:11] Machine Previous Privilege
    logic [1:0]  _reserved0;// [10:9]  Reserved (WPRI)
    logic        SPP;       // [8]     Supervisor Previous Privilege
    logic        MPIE;      // [7]     Machine Previous Interrupt Enable
    logic        UBE;       // [6]     User Big Endian (RV32 only)
    logic        SPIE;      // [5]     Supervisor Previous Interrupt Enable
    logic        _reserved2;// [4]     Reserved
    logic        MIE;       // [3]     Machine Interrupt Enable
    logic        _reserved3;// [2]     Reserved
    logic        SIE;       // [1]     Supervisor Interrupt Enable
    logic        _reserved4;// [0]     Reserved
} mstatus_t;

module csr_file(
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] id_inst,
    input  logic [31:0] id_pc,
    input  logic        CsrWrite,
    input  logic [11:0] CsrWriteImm12,
    input  logic [31:0] csr_write_data,
    input  logic [2:0]  csr_funct3,
    output logic [31:0] csr_read_data,

    input  logic        ex_trap_take,
    input  logic [31:0] ex_trap_pc,
    input  logic [31:0] ex_trap_cause,
    input  logic [31:0] ex_trap_tval,
    input  logic        ex_trap_mret,
    output logic [31:0] csr_mtvec,
    output logic [31:0] csr_mepc,
    output logic [1:0]  csr_priv_mode,
    output logic        is_illegal_csr
);

    // Minimal CSR set required by riscv-tests/spike boot flow.
    // NOTE: For now these are simple 32-bit regs (no WARL enforcement yet).
    mstatus_t    mstatus  = 32'h0000_1800;
    logic [31:0] mstatush = 32'h0000_0000;
    logic [31:0] mtvec    = 32'h0000_0000;
    logic [31:0] mepc     = 32'h0000_0000;
    logic [31:0] mcause   = 32'h0000_0000;
    logic [31:0] mtval    = 32'h0000_0000;
    logic [31:0] mhartid  = 32'h0000_0000;
    logic [31:0] medeleg  = 32'h0000_0000;
    logic [31:0] mideleg  = 32'h0000_0000;
    logic [31:0] mie      = 32'h0000_0000;
    logic [31:0] satp     = 32'h0000_0000;
    logic [31:0] stvec    = 32'h0000_0000;
    logic [31:0] pmpcfg0  = 32'h0000_0000;
    logic [31:0] pmpaddr0 = 32'h0000_0000;
    // mnstatus (0x744) is optional (Smrnmi); Spike may treat it as illegal on rv32i.
    // Keep unimplemented for now to match Spike's illegal-instruction behavior.

    // next-state
    mstatus_t    mstatus_n;
    logic [31:0] mstatush_n;
    logic [31:0] mtvec_n, mepc_n, mcause_n, mtval_n;
    logic [31:0] medeleg_n, mideleg_n, mie_n, satp_n, stvec_n;
    logic [31:0] pmpcfg0_n, pmpaddr0_n;
    logic [1:0]  priv_mode = 2'b11;   // current privilege (M=3, S=1, U=0)
    logic [1:0]  priv_mode_n;

    assign csr_mtvec = mtvec;
    assign csr_mepc  = mepc;
    assign csr_priv_mode = priv_mode;

    // 定義 write mask (WPRI 位元為 0)
    // 1 = 可寫 (R/W), 0 = 唯讀或保留 (Read-only / WPRI)
    // 針對目標：RV32IMA + S-Mode (Linux Ready)
    // localparam logic [31:0] MSTATUS_WRITE_MASK = {
    //     1'b0,       // Bit 31: SD (Status Dirty) - 唯讀，由硬體自動計算
    //     8'b0,       // Bits 30-23: WPRI (Reserved) - 必須為 0
    //     1'b1,       // Bit 22: TSR (Trap SRET)
    //     1'b1,       // Bit 21: TW (Timeout Wait)
    //     1'b1,       // Bit 20: TVM (Trap Virtual Memory)
    //     1'b1,       // Bit 19: MXR (Make Executable Readable)
    //     1'b1,       // Bit 18: SUM (Supervisor User Memory Access)
    //     1'b1,       // Bit 17: MPRV (Modify Privilege)
    //     2'b00,      // Bits 16-15: XS (Extension Status) - 通常唯讀
    //     2'b00,      // Bits 14-13: FS (Floating-point Status) - 目前 RV32I 為 0
    //     2'b11,      // Bits 12-11: MPP (Machine Prev Priv)
    //     2'b00,      // Bits 10-9: WPRI (Reserved)
    //     1'b1,       // Bit 8: SPP (Supervisor Prev Priv)
    //     1'b1,       // Bit 7: MPIE
    //     1'b0,       // Bit 6: WPRI (Reserved / UBE)
    //     1'b1,       // Bit 5: SPIE
    //     1'b0,       // Bit 4: UPIE (User Interrupts) - Linux 通常不用 N 擴充，設 0
    //     1'b1,       // Bit 3: MIE
    //     1'b0,       // Bit 2: WPRI
    //     1'b1,       // Bit 1: SIE
    //     1'b0        // Bit 0: UIE (User Interrupts) - Linux 通常不用 N 擴充，設 0
    // };
    localparam logic [31:0] MSTATUS_WRITE_MASK = 32'h0020_1888; // 為了符合 spike --priv=m

    function automatic mstatus_t mstatus_legalize(
        input mstatus_t old_val,
        input mstatus_t new_val
    );
        mstatus_t result;
        // 保留 WPRI 位元
        result = mstatus_t'((32'(new_val) & MSTATUS_WRITE_MASK) |
                            (32'(old_val) & ~MSTATUS_WRITE_MASK));
        // MPP WARL: 2'b10 是非法值
        // if (result.MPP == 2'b10)
            // result.MPP = 2'b00;
        result.MPP = 2'b11; // FIXME
        // SD 是唯讀，由 FS/XS 推導
        result.SD = (result.FS == 2'b11) || (result.XS == 2'b11);
        return result;
    endfunction

    // ------------------------------
    // CSR 讀取 FIXME (spike --priv=m 會有一些 CSR 會變成 illegal, 之後要再加回來)
    // ------------------------------
    always_comb begin
        is_illegal_csr = 0;
        csr_read_data = 32'h0;
        if (id_inst[6:0] == 7'b1110011 && id_inst[14:12] != 3'b000) begin // CSR 類（排除 ECALL/MRET）
            unique case (id_inst[31:20])
                12'h305: csr_read_data = mtvec;
                12'h341: csr_read_data = mepc;
                12'h342: csr_read_data = mcause;
                12'h343: csr_read_data = mtval;
                12'h300: csr_read_data = 32'(mstatus);
                12'h310: csr_read_data = mstatush;
                12'hf14: csr_read_data = mhartid;
                // 12'h302: csr_read_data = medeleg;
                12'h303: csr_read_data = mideleg;
                12'h304: csr_read_data = mie;
                // 12'h180: csr_read_data = satp;
                // 12'h105: csr_read_data = stvec;
                12'h3a0: csr_read_data = pmpcfg0;
                12'h3b0: csr_read_data = pmpaddr0;
                default: begin
                    is_illegal_csr = 1;
                    csr_read_data = 32'h0;
                end
            endcase
        end
    end

    // ------------------------------
    // Next-state 組合邏輯
    //   1) 先套用 CSR 寫入
    //   2) 再做 trap-entry 規則（覆蓋 mepc/mcause/mtval，並在 mstatus_n 上做位元轉換）
    // ------------------------------
    always_comb begin
        mstatus_n = mstatus;
        mstatush_n= mstatush;
        mtvec_n   = mtvec;
        mepc_n    = mepc;
        mcause_n  = mcause;
        mtval_n   = mtval;
        medeleg_n = medeleg;
        mideleg_n = mideleg;
        mie_n     = mie;
        satp_n    = satp;
        stvec_n   = stvec;
        pmpcfg0_n = pmpcfg0;
        pmpaddr0_n= pmpaddr0;
        priv_mode_n = priv_mode;

        // (1) CSR 寫入（CSRRW/CSRRS 等），先更新 *_n
        if (CsrWrite) begin
            if (csr_funct3 == 3'b001 || csr_funct3 == 3'b101) begin // csrrw / csrrwi
                case (CsrWriteImm12)
                    12'h305: mtvec_n   = {csr_write_data[31:2], 2'b00}; // 僅支援 MODE=Direct，強制對齊
                    12'h341: mepc_n    = {csr_write_data[31:1], 1'b0};  // 對齊 bit0=0
                    12'h342: mcause_n  = csr_write_data;
                    12'h343: mtval_n   = csr_write_data;
                    12'h300: mstatus_n = mstatus_legalize(mstatus_n, csr_write_data);
                    12'h310: mstatush_n= csr_write_data;
                    12'h302: medeleg_n = csr_write_data;
                    12'h303: mideleg_n = csr_write_data;
                    12'h304: mie_n     = csr_write_data;
                    12'h180: satp_n    = csr_write_data;
                    12'h105: stvec_n   = {csr_write_data[31:2], 2'b00}; // direct, aligned
                    12'h3a0: pmpcfg0_n = csr_write_data;
                    12'h3b0: pmpaddr0_n= csr_write_data;
                    default: ; // 其他 CSR 暫不處理
                endcase
            end else if (csr_funct3 == 3'b010 || csr_funct3 == 3'b110) begin // csrrs / csrrsi
                case (CsrWriteImm12)
                    12'h305: mtvec_n   |= {csr_write_data[31:2], 2'b00}; // 僅支援 MODE=Direct，強制對齊
                    12'h341: mepc_n    |= {csr_write_data[31:1], 1'b0};  // 對齊 bit0=0
                    12'h342: mcause_n  |= csr_write_data;
                    12'h343: mtval_n   |= csr_write_data;
                    12'h300: mstatus_n |= csr_write_data;                // FIXME 先不嚴格檢查各位元
                    12'h310: mstatush_n|= csr_write_data;
                    12'h302: medeleg_n |= csr_write_data;
                    12'h303: mideleg_n |= csr_write_data;
                    12'h304: mie_n     |= csr_write_data;
                    12'h180: satp_n    |= csr_write_data;
                    12'h105: stvec_n   |= {csr_write_data[31:2], 2'b00};
                    12'h3a0: pmpcfg0_n |= csr_write_data;
                    12'h3b0: pmpaddr0_n|= csr_write_data;
                    default: ; // 其他 CSR 暫不處理
                endcase
            end else if (csr_funct3 == 3'b011 || csr_funct3 == 3'b111) begin // csrrc / csrrci
                case (CsrWriteImm12)
                    12'h305: mtvec_n   &= ~{csr_write_data[31:2], 2'b00}; // 僅支援 MODE=Direct，強制對齊
                    12'h341: mepc_n    &= ~{csr_write_data[31:1], 1'b0};  // 對齊 bit0=0
                    12'h342: mcause_n  &= ~csr_write_data;
                    12'h343: mtval_n   &= ~csr_write_data;
                    12'h300: mstatus_n &= ~csr_write_data;                // FIXME 先不嚴格檢查各位元
                    12'h310: mstatush_n&= ~csr_write_data;
                    12'h302: medeleg_n &= ~csr_write_data;
                    12'h303: mideleg_n &= ~csr_write_data;
                    12'h304: mie_n     &= ~csr_write_data;
                    12'h180: satp_n    &= ~csr_write_data;
                    12'h105: stvec_n   &= ~{csr_write_data[31:2], 2'b00};
                    12'h3a0: pmpcfg0_n &= ~csr_write_data;
                    12'h3b0: pmpaddr0_n&= ~csr_write_data;
                    default: ; // 其他 CSR 暫不處理
                endcase
            end
        end

        // (2) Trap-entry：覆蓋/轉換，基於「已套用 CSRW 後」的 *_n
        if (ex_trap_take) begin
            mepc_n    = {ex_trap_pc[31:1], 1'b0};
            mcause_n  = ex_trap_cause;
            mtval_n   = ex_trap_tval;

            // mstatus：MPIE <- MIE, MIE <- 0, MPP <- M(2'b11)
            // 注意：這裡用的是 mstatus_n（已反映同拍 CSR 寫入後的值）
            mstatus_n.MPIE   = mstatus_n.MIE;
            mstatus_n.MIE    = 1'b0;
            mstatus_n.MPP    = priv_mode;
            priv_mode_n      = 2'b11;         // enter M-mode
        end else if (ex_trap_mret) begin
            // mret:
            // - return to MPP
            // - MIE <- MPIE; MPIE <- 1; MPP <- U(0)
            priv_mode_n      = mstatus_n.MPP;
            mstatus_n.MIE    = mstatus_n.MPIE;
            mstatus_n.MPIE   = 1'b1;
            mstatus_n.MPP    = 2'b11; // FIXME, 目前為了讓 spike 能跑過
        end
    end

    // ------------------------------
    // 狀態暫存器更新
    // ------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            mstatus   <= 32'h0000_1800;
            mstatush  <= 32'h0000_0000;
            mtvec     <= 32'h0000_0000;
            mepc      <= 32'h0000_0000;
            mcause    <= 32'h0000_0000;
            mtval     <= 32'h0000_0000;
            mhartid   <= 32'h0000_0000;
            medeleg   <= 32'h0000_0000;
            mideleg   <= 32'h0000_0000;
            mie       <= 32'h0000_0000;
            satp      <= 32'h0000_0000;
            stvec     <= 32'h0000_0000;
            pmpcfg0   <= 32'h0000_0000;
            pmpaddr0  <= 32'h0000_0000;
            priv_mode <= 2'b11;
        end else begin
            mstatus <= mstatus_n;
            mstatush<= mstatush_n;
            mtvec   <= mtvec_n;
            mepc    <= mepc_n;
            mcause  <= mcause_n;
            mtval   <= mtval_n;
            medeleg <= medeleg_n;
            mideleg <= mideleg_n;
            mie     <= mie_n;
            satp    <= satp_n;
            stvec   <= stvec_n;
            pmpcfg0 <= pmpcfg0_n;
            pmpaddr0<= pmpaddr0_n;
            priv_mode <= priv_mode_n;
        end
    end

endmodule

module csr_control_unit(
    input logic [31:0] id_inst,
    output logic CsrtoReg,
    output logic CsrWrite,
    output logic [11:0] CsrWriteImm12,
    output logic csr_src_is_zimm,
    output logic [2:0] csr_funct3,
    output logic is_illegal_csr
);

    always_comb begin
        CsrtoReg = 0;
        CsrWrite = 0;
        CsrWriteImm12 = 0;
        csr_src_is_zimm = 0; // 0: select from register's content, 1: rs1 as a value
        csr_funct3 = 0;
        is_illegal_csr = 0;
        if (id_inst[6:0] == 7'b1110011) begin // system/csr
            csr_funct3 = id_inst[14:12];
            // ECALL/MRET 是固定編碼；其餘 funct3==000 視為未支援的 SYSTEM 指令（保持預設不寫 CSR）
            if (id_inst == 32'h0000_0073 || id_inst == 32'h3020_0073) begin // ecall / mret
                CsrtoReg = 0;
                CsrWrite = 0;
            end else if (id_inst[14:12] == 3'b001) begin // csrrw
                CsrtoReg = 1;
                CsrWrite = 1;
                CsrWriteImm12 = id_inst[31:20];
                csr_src_is_zimm = 0;
            end else if (id_inst[14:12] == 3'b010) begin // csrrs
                CsrtoReg = 1;
                // Spec: if rs1==x0, CSRRS is read-only (no CSR write)
                CsrWrite = (id_inst[19:15] != 5'd0);
                CsrWriteImm12 = id_inst[31:20];
                csr_src_is_zimm = 0;
            end else if (id_inst[14:12] == 3'b011) begin // csrrc
                CsrtoReg = 1;
                // Spec: if rs1==x0, CSRRC is read-only (no CSR write)
                CsrWrite = (id_inst[19:15] != 5'd0);
                CsrWriteImm12 = id_inst[31:20];
                csr_src_is_zimm = 0;
            end else if (id_inst[14:12] == 3'b101) begin // csrrwi
                CsrtoReg = 1;
                CsrWrite = 1;
                CsrWriteImm12 = id_inst[31:20];
                csr_src_is_zimm = 1;
            end else if (id_inst[14:12] == 3'b110) begin // csrrsi
                CsrtoReg = 1;
                // Spec: if zimm==0, CSRRSI is read-only (no CSR write)
                CsrWrite = (id_inst[19:15] != 5'd0);
                CsrWriteImm12 = id_inst[31:20];
                csr_src_is_zimm = 1;
            end else if (id_inst[14:12] == 3'b111) begin // csrrci
                CsrtoReg = 1;
                // Spec: if zimm==0, CSRRCI is read-only (no CSR write)
                CsrWrite = (id_inst[19:15] != 5'd0);
                CsrWriteImm12 = id_inst[31:20];
                csr_src_is_zimm = 1;
            end else begin
                is_illegal_csr = 1;
`ifdef IVERILOG
                if ($test$plusargs("CSRDBG")) begin
                    $display("[csr_control_unit] Invalid CSR instruction");
                end
`endif
            end
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
    output logic isValid,
    output logic [4:0] decoded_rs1,
    output logic [4:0] decoded_rs2
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
                decoded_rs1 = inst[19:15];
                decoded_rs2 = inst[24:20];
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
                decoded_rs1 = inst[19:15];
                decoded_rs2 = 0;
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
                decoded_rs1 = inst[19:15];
                decoded_rs2 = 0;
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
                decoded_rs1 = inst[19:15];
                decoded_rs2 = inst[24:20];
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
                decoded_rs1 = inst[19:15];
                decoded_rs2 = inst[24:20];
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
                decoded_rs1 = 0;
                decoded_rs2 = 0;
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
                decoded_rs1 = 0;
                decoded_rs2 = 0;
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
                decoded_rs1 = 0;
                decoded_rs2 = 0;
            end
            7'b1100111: begin // jalr
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
                decoded_rs1 = inst[19:15];
                decoded_rs2 = 0;
            end
            7'b1110011: begin // system/csr
                ALUSrc = 1;
                ALUSrcA_sel = 2'b00;
                MemtoReg = 0;
                RegWrite = 1;
                MemRead = 0;
                MemWrite = 0;
                Branch = 0;
                ALUOp = 2'b00; // use add (像是 lw)
                isSub = 0;
                isValid = 1;
                decoded_rs1 = inst[19:15];
                decoded_rs2 = 0;
                // ECALL/MRET 是固定編碼，避免誤把 CSR[0x000]/CSR[0x302] 存取當成 ecall/mret
                if (inst == 32'h0000_0073 || inst == 32'h3020_0073) begin // ecall / mret
                    RegWrite = 0;
                    decoded_rs1 = 0;
                end
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
                decoded_rs1 = 0;
                decoded_rs2 = 0;
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
            7'b1100111: // jalr
                imm32 = 32'h4;
            7'b1110011: // csr
                imm32 = 32'h0;
            default:
                imm32 = 32'h0;
        endcase
    end

endmodule

module program_counter #(
    // Simulation/SoC integration:
    // - default 0 keeps existing in-repo tests (linked at 0) working
    // - riscv-tests + spike default boot flow starts at 0x0000_1000
    parameter logic [31:0] RESET_PC = 32'h0000_0000
)(
    input logic clk,
    input logic rst_n,
    input logic PCWrite,
    input logic [31:0] pc_next,
    output logic [31:0] pc_current
);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            pc_current <= RESET_PC;
        end else begin
            if (PCWrite) begin
                pc_current <= {pc_next[31:2], 2'b00};
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
    output logic [31:0] id_inst,
    output logic        id_stage_valid
);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            id_pc <= 32'h0;
            id_inst <= 32'h0;
            id_stage_valid <= 1'b0;
        end else if (if_Flush) begin
            id_pc <= 32'h0;
            id_inst <= 32'h00000013; // NOP
            id_stage_valid <= 1'b0;  // flush 插入 bubble：視為無效指令
        end else if (if_id_Write) begin
            id_pc <= if_pc;
            id_inst <= if_inst;
            id_stage_valid <= 1'b1;  // 成功取入一條新指令（不論是否為合法 opcode）
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
    input logic id_stage_valid,

    input logic [31:0] id_pc,
    input logic [31:0] id_inst,
    input logic [31:0] id_read_data1,
    input logic [31:0] id_read_data2,
    input logic [31:0] id_imm32,
    input logic [2:0] id_funct3,
    input logic [4:0] id_rd,
    input logic [4:0] id_decoded_rs1,
    input logic [4:0] id_decoded_rs2,

    input logic id_CsrtoReg,
    input logic id_CsrWrite,
    input logic [11:0] id_CsrWriteImm12,
    input logic [31:0] id_csr_read_data,
    input logic [31:0] id_csr_mtvec,
    input logic [31:0] id_csr_mepc,
    input logic id_csr_src_is_zimm,
    input logic [2:0] id_csr_funct3,
    input logic id_is_illegal_csr,

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
    output logic ex_stage_valid,

    output logic [31:0] ex_pc,
    output logic [31:0] ex_inst,
    output logic [31:0] ex_read_data1,
    output logic [31:0] ex_read_data2,
    output logic [31:0] ex_imm32,
    output logic [2:0] ex_funct3,
    output logic [4:0] ex_rd,
    output logic [4:0] ex_decoded_rs1,
    output logic [4:0] ex_decoded_rs2,

    output logic ex_CsrtoReg,
    output logic ex_CsrWrite,
    output logic [11:0] ex_CsrWriteImm12,
    output logic [31:0] ex_csr_read_data,
    output logic [31:0] ex_csr_mtvec,
    output logic [31:0] ex_csr_mepc,
    output logic ex_csr_src_is_zimm,
    output logic [2:0] ex_csr_funct3,
    output logic ex_is_illegal_csr
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
            ex_stage_valid <= 0;
            ex_decoded_rs1 <= 0;
            ex_decoded_rs2 <= 0;
            ex_pc <= 0;
            ex_inst <= 0;
            ex_read_data1 <= 0;
            ex_read_data2 <= 0;
            ex_imm32 <= 0;
            ex_funct3 <= 0;
            ex_rd <= 0;
            ex_CsrtoReg <= 0;
            ex_CsrWrite <= 0;
            ex_CsrWriteImm12 <= 0;
            ex_csr_read_data <= 0;
            ex_csr_mtvec <= 0;
            ex_csr_mepc <= 0;
            ex_csr_src_is_zimm <= 0;
            ex_csr_funct3 <= 0;
            ex_is_illegal_csr <= 0;
        end else if (id_Flush) begin
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
            ex_stage_valid <= 0;
            ex_decoded_rs1 <= 0;
            ex_decoded_rs2 <= 0;
            ex_pc <= 0;
            ex_inst <= 32'h00000013; // NOP
            ex_read_data1 <= 0;
            ex_read_data2 <= 0;
            ex_imm32 <= 0;
            ex_funct3 <= 0;
            ex_rd <= 0;
            ex_CsrtoReg <= 0;
            ex_CsrWrite <= 0;
            ex_CsrWriteImm12 <= 0;
            ex_csr_read_data <= 0;
            ex_csr_mtvec <= 0;
            ex_csr_mepc <= 0;
            ex_csr_src_is_zimm <= 0;
            ex_csr_funct3 <= 0;
            ex_is_illegal_csr <= 0;
        end else if (id_ex_Write) begin
            ex_ALUSrc <= id_ALUSrc;
            ex_ALUSrcA_sel <= id_ALUSrcA_sel;
            ex_MemtoReg <= id_MemtoReg;
            ex_RegWrite <= id_RegWrite;
            ex_MemRead <= id_MemRead;
            ex_MemWrite <= id_MemWrite;
            ex_Branch <= id_Branch;
            ex_ALUOp <= id_ALUOp;
            ex_isSub <= id_isSub;
            ex_isValid <= id_isValid;
            ex_stage_valid <= id_stage_valid;
            ex_decoded_rs1 <= id_decoded_rs1;
            ex_decoded_rs2 <= id_decoded_rs2;
            ex_pc <= id_pc;
            ex_inst <= id_inst;
            ex_read_data1 <= id_read_data1;
            ex_read_data2 <= id_read_data2;
            ex_imm32 <= id_imm32;
            ex_funct3 <= id_funct3;
            ex_rd <= id_rd;
            ex_CsrtoReg <= id_CsrtoReg;
            ex_CsrWrite <= id_CsrWrite;
            ex_CsrWriteImm12 <= id_CsrWriteImm12;
            ex_csr_read_data <= id_csr_read_data;
            ex_csr_mtvec <= id_csr_mtvec;
            ex_csr_mepc <= id_csr_mepc;
            ex_csr_src_is_zimm <= id_csr_src_is_zimm;
            ex_csr_funct3 <= id_csr_funct3;
            ex_is_illegal_csr <= id_is_illegal_csr;
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
    input logic [2:0] ex_funct3,
    input logic ex_CsrtoReg,
    input logic ex_CsrWrite,
    input logic [11:0] ex_CsrWriteImm12,
    input logic [31:0] ex_csr_read_data,
    input logic [2:0] ex_csr_funct3,
    input logic ex_stage_valid,
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
    output logic [4:0] mem_rd,
    output logic [2:0] mem_funct3,
    output logic mem_CsrtoReg,
    output logic mem_CsrWrite,
    output logic [11:0] mem_CsrWriteImm12,
    output logic [31:0] mem_csr_read_data,
    output logic [2:0] mem_csr_funct3,
    output logic mem_stage_valid
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
            mem_funct3 <= 0;
            mem_CsrtoReg <= 0;
            mem_CsrWrite <= 0;
            mem_CsrWriteImm12 <= 0;
            mem_csr_read_data <= 0;
            mem_csr_funct3 <= 0;
            mem_stage_valid <= 0;
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
            mem_funct3 <= ex_funct3;
            mem_CsrtoReg <= ex_CsrtoReg;
            mem_CsrWrite <= ex_CsrWrite;
            mem_CsrWriteImm12 <= ex_CsrWriteImm12;
            mem_csr_read_data <= ex_csr_read_data;
            mem_csr_funct3 <= ex_csr_funct3;
            mem_stage_valid <= ex_stage_valid;
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
    // Carry store data to WB so we can produce Spike-like logs (mem addr + data)
    // and build signature from retired stores without peeking into RAM arrays.
    input logic [31:0] mem_store_data,
    input logic [4:0] mem_rd,
    input logic mem_CsrtoReg,
    input logic mem_CsrWrite,
    input logic [11:0] mem_CsrWriteImm12,
    input logic [31:0] mem_csr_read_data,
    input logic [2:0] mem_csr_funct3,
    input logic [31:0] mem_pc,
    input logic [31:0] mem_inst,
    input logic mem_stage_valid,
    output logic wb_RegWrite,
    output logic wb_MemtoReg,
    output logic [31:0] wb_memory_read_data,
    output logic [31:0] wb_alu_out,
    output logic [31:0] wb_store_data,
    output logic [4:0] wb_rd,
    output logic wb_CsrtoReg,
    output logic wb_CsrWrite,
    output logic [11:0] wb_CsrWriteImm12,
    output logic [31:0] wb_csr_read_data,
    output logic [2:0] wb_csr_funct3,
    output logic [31:0] wb_pc,
    output logic [31:0] wb_inst,
    output logic wb_stage_valid
);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            wb_RegWrite <= 0;
            wb_MemtoReg <= 0;
            wb_memory_read_data <= 0;
            wb_alu_out <= 0;
            wb_store_data <= 0;
            wb_rd <= 0;
            wb_CsrtoReg <= 0;
            wb_CsrWrite <= 0;
            wb_CsrWriteImm12 <= 0;
            wb_csr_read_data <= 0;
            wb_csr_funct3 <= 0;
            wb_pc <= 0; // TODO: 這裡應該要是 0 還是 8000_0000
            wb_inst <= 0;
            wb_stage_valid <= 0;
        end else if (mem_wb_Write) begin
            wb_RegWrite <= mem_RegWrite;
            wb_MemtoReg <= mem_MemtoReg;
            wb_memory_read_data <= mem_memory_read_data;
            wb_alu_out <= mem_alu_out;
            wb_store_data <= mem_store_data;
            wb_rd <= mem_rd;
            wb_CsrtoReg <= mem_CsrtoReg;
            wb_CsrWrite <= mem_CsrWrite;
            wb_CsrWriteImm12 <= mem_CsrWriteImm12;
            wb_csr_read_data <= mem_csr_read_data;
            wb_csr_funct3 <= mem_csr_funct3;
            wb_pc <= mem_pc;
            wb_inst <= mem_inst;
            wb_stage_valid <= mem_stage_valid;
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
        if (ex_rs1 == 0) begin
            ForwardA = 2'b00;
        end else if (mem_RegWrite && (mem_rd != 0) && (mem_rd == ex_rs1)) begin
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
        if (ex_rs2 == 0) begin
            ForwardB = 2'b00;
        end else if (mem_RegWrite && (mem_rd != 0) && (mem_rd == ex_rs2)) begin
            // MEM->EX
            ForwardB = 2'b10;
        end else if (wb_RegWrite && (wb_rd != 0) && (wb_rd == ex_rs2)) begin
            // WB->EX
            ForwardB = 2'b01;
        end else begin
            // No forward
            ForwardB = 2'b00;
        end

`ifdef IVERILOG
        // Debug print is extremely verbose; enable only when explicitly requested.
        if ($test$plusargs("FWDBG")) begin
            if (ForwardA != 0) $display("[fw unit] ForwardA: %h", ForwardA);
            if (ForwardB != 0) $display("[fw unit] ForwardB: %h", ForwardB);
        end
`endif
    end

endmodule

module hazard_mux_control(
    input logic sel,
    input logic id_MemWrite,
    input logic id_RegWrite,
    input logic id_MemRead,
    input logic id_MemtoReg,
    input logic id_CsrWrite,
    input logic id_CsrtoReg,
    output logic mux_MemWrite,
    output logic mux_RegWrite,
    output logic mux_MemRead,
    output logic mux_MemtoReg,
    output logic mux_CsrWrite,
    output logic mux_CsrtoReg
);

    always_comb begin
        if (sel) begin
            mux_MemWrite = id_MemWrite;
            mux_RegWrite = id_RegWrite;
            mux_MemRead = id_MemRead;
            mux_MemtoReg = id_MemtoReg;
            mux_CsrWrite = id_CsrWrite;
            mux_CsrtoReg = id_CsrtoReg;
        end else begin
            mux_MemWrite = 0;
            mux_RegWrite = 0;
            mux_MemRead = 0;
            mux_MemtoReg = 0;
            mux_CsrWrite = 0;
            mux_CsrtoReg = 0;
        end
    end

endmodule

module control_hazard_detection_unit(
    input logic [31:0] ex_inst,
    input logic [31:0] ex_pc,
    input logic [31:0] ex_imm32,
    input logic [31:0] ex_mux3to1_alu_a_out,
    input logic [31:0] ex_mux3to1_alu_b_out,
    input logic [31:0] ex_csr_mtvec,
    input logic [31:0] ex_csr_mepc,
    input logic  ex_is_illegal_csr,
    input logic [1:0] ex_priv_mode,
    output logic ex_trap_take,
    output logic [31:0] ex_trap_pc,
    output logic [31:0] ex_trap_cause,
    output logic [31:0] ex_trap_tval,
    output logic ex_trap_mret,
    output logic if_Flush,
    output logic id_Flush,
    output logic pc_branch_sel,
    output logic [31:0] pc_branch_target
);

    logic branch_taken = 0;
    logic is_jal = 0;
    logic is_jalr = 0;
    logic is_ecall = 0;
    logic is_mret = 0;

    always_comb begin
        branch_taken      = 1'b0;
        if_Flush          = 1'b0;
        id_Flush          = 1'b0;
        pc_branch_sel     = 1'b0;
        is_jal            = 1'b0;
        is_jalr           = 1'b0;
        is_ecall          = 1'b0;
        is_mret           = 1'b0;
        ex_trap_take      = 1'b0;
        ex_trap_mret      = 1'b0;
        ex_trap_pc        = 0;
        ex_trap_cause     = 0;
        ex_trap_tval      = 0;
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
                    3'b100: begin // blt
                        if ($signed(ex_mux3to1_alu_a_out) < $signed(ex_mux3to1_alu_b_out)) begin
                            branch_taken = 1;
                        end
                    end
                    3'b101: begin // bge
                        if ($signed(ex_mux3to1_alu_a_out) >= $signed(ex_mux3to1_alu_b_out)) begin
                            branch_taken = 1;
                        end
                    end
                    3'b110: begin // bltu
                        if ($unsigned(ex_mux3to1_alu_a_out) < $unsigned(ex_mux3to1_alu_b_out)) begin
                            branch_taken = 1;
                        end
                    end
                    3'b111: begin // bgeu
                        if ($unsigned(ex_mux3to1_alu_a_out) >= $unsigned(ex_mux3to1_alu_b_out)) begin
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
            7'b1100111: begin // jalr
                branch_taken = 1;
                is_jalr = 1;
            end
            7'b1110011: begin // system/csr
                // ECALL/MRET 是固定編碼，避免誤把 CSR[0x000]/CSR[0x302] 存取當成 ecall/mret
                if (ex_inst == 32'h0000_0073) begin // ecall
                    branch_taken = 1;
                    is_ecall = 1;
                end else if (ex_inst == 32'h3020_0073) begin // mret
                    branch_taken = 1;
                    is_mret = 1;
                end
            end
            default: begin
            end
        endcase

        if (ex_is_illegal_csr) begin
            branch_taken = 1;
        end

        if (branch_taken) begin
            pc_branch_sel    = 1'b1;              // pc mux 選 branch
            if (is_jal) begin
                pc_branch_target = ex_pc + {{12{ex_inst[31]}}, ex_inst[19:12], ex_inst[20], ex_inst[30:21], 1'b0};
            end else if (is_jalr) begin
                pc_branch_target = (ex_mux3to1_alu_a_out + {{20{ex_inst[31]}}, ex_inst[31:20]}) & 32'hffff_fffe;
            end else if (is_ecall) begin
                ex_trap_take        = 1'b1;
                ex_trap_pc          = ex_pc;
                // ecall cause depends on current privilege mode
                unique case (ex_priv_mode)
                    2'b00: ex_trap_cause = 32'd8;   // ECALL from U-mode
                    2'b01: ex_trap_cause = 32'd9;   // ECALL from S-mode
                    default: ex_trap_cause = 32'd11; // ECALL from M-mode
                endcase
                ex_trap_tval        = 32'd0;
                pc_branch_target    = ex_csr_mtvec;
`ifdef IVERILOG
                if ($test$plusargs("TRAPDBG")) begin
                    $strobe("[ecall] target pc: %h, ex_inst: %h", pc_branch_target, ex_inst);
                end
`endif
                if (pc_branch_target == 0) begin
                    $finish;
                end
            end else if (ex_is_illegal_csr) begin
                ex_trap_take        = 1'b1;
                ex_trap_pc          = ex_pc;
                ex_trap_cause       = 32'd2; // Mcause code=2
                ex_trap_tval        = 32'd0;
                pc_branch_target    = ex_csr_mtvec;
`ifdef IVERILOG
                if ($test$plusargs("TRAPDBG")) begin
                    $display("[illgal csr] target pc: %h, ex_inst: %h", pc_branch_target, ex_inst);
                end
`endif
                if (pc_branch_target == 0) begin
                    $finish;
                end
            end else if (is_mret) begin
                ex_trap_mret        = 1'b1;
                pc_branch_target    = ex_csr_mepc;
`ifdef IVERILOG
                if ($test$plusargs("TRAPDBG")) begin
                    $display("[mret] target pc: %h, ex_csr_mepc: %h", pc_branch_target, ex_csr_mepc);
                end
`endif
                if (pc_branch_target == 0) begin
                    $finish;
                end
            end else begin
                pc_branch_target = ex_pc + ex_imm32;  // 計算好的目標位址
            end
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

    // CSR Hazard
    input logic  [31:0] id_inst,
    // For system_busy (serialize all 0x73 while in flight)
    input logic  [31:0] ex_inst,
    input logic  [31:0] mem_inst,
    input logic  [31:0] wb_inst,
    input logic         ex_CsrWrite,
    input logic  [11:0] ex_CsrWriteImm12,
    input logic         mem_CsrWrite,
    input logic  [11:0] mem_CsrWriteImm12,
    input logic         wb_CsrWrite,
    input logic  [11:0] wb_CsrWriteImm12,
    input logic         ex_is_illegal_csr,
    input logic         id_stage_valid,
    input logic         ex_stage_valid,
    input logic         mem_stage_valid,
    input logic         wb_stage_valid,

    input  logic       if_pc_MemRead,
    input  logic       if_pc_read_data_valid,

    // -------------------
    // 2) mem_stall : memory/uart stall
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
    logic if_stall;
    logic system_inst_stall;
    logic system_inst_running;
    logic system_busy;
    logic drain_done;
    logic is_system_inst;

    // 注意：stage_valid 才代表「這級真的有有效指令在飛」
    // 0x73 序列化也必須以 stage_valid 為準，否則 bubble/NOP 可能被誤判成 system 指令而卡死。
    assign is_system_inst = id_stage_valid && (id_inst[6:0] == 7'b1110011);

    assign drain_done     = (ex_stage_valid == 0) && (mem_stage_valid == 0) && (wb_stage_valid == 0);
    assign system_busy    =
        (ex_stage_valid  && (ex_inst[6:0]  == 7'b1110011)) ||
        (mem_stage_valid && (mem_inst[6:0] == 7'b1110011)) ||
        (wb_stage_valid  && (wb_inst[6:0]  == 7'b1110011));

    always_comb begin
        system_inst_stall = 1'b0;
        system_inst_running = 1'b0;
        if (is_system_inst) begin
            if (drain_done) begin
                system_inst_stall   = 1'b0;
                system_inst_running = 1'b1;
            end else begin
                system_inst_stall   = 1'b1;
                system_inst_running = 1'b0;
            end
        end else begin
            system_inst_stall       = 1'b0;
            system_inst_running     = 1'b0;
        end
    end
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
        if (mem_data_MemRead  && !mem_data_read_data_valid) begin
            mem_stall = 1'b1;
        end
        if (mem_uart_MemRead  && !mem_uart_read_data_valid) begin
            mem_stall = 1'b1;
        end
        // 需要多週期寫
        if (mem_data_MemWrite && !mem_data_write_done) begin
            mem_stall = 1'b1;
        end
        if (mem_uart_MemWrite && !mem_uart_write_done) begin
            mem_stall = 1'b1;
        end
    end

    always_comb begin
        if_stall = 1'b0;
        if (if_pc_MemRead && !if_pc_read_data_valid) begin
            if_stall = 1'b1;
        end
    end

    //==========================================================
    // (3) 合併結果
    //==========================================================
    // 先判斷 mem_stall (最優先)，如果是 mem_stall 就要整條 pipeline freeze
    // 如果不是 mem_stall，才考慮是否 hazard_stall
    //==========================================================
    always_comb begin
        // IMPORTANT：mem_stall / if_stall 必須最高優先（blocking memory / blocking fetch）
        // 否則序列化邏輯會讓流水線在記憶體尚未完成時「偷跑」，破壞正確性。
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
        end else if (if_stall) begin
            // IF stall - 整個流水線 freeze
            PCWrite     = 1'b0;
            if_id_Write = 1'b0;
            id_ex_Write = 1'b0;
            ex_mem_Write= 1'b0;
            mem_wb_Write= 1'b0;

            hazard_control_mux_sel = 1'b1;
        end else if (system_busy) begin
            // 0x73 busy：EX/MEM/WB 仍有 system 指令在飛 → 阻止年輕指令進入 EX，直到 0x73 完全退休
            // 作法：freeze PC/IFID，並持續往 EX 注入 bubble；同時讓後段繼續前進以便把 0x73 drain 掉。
            PCWrite     = 1'b0;   // freeze PC（但 trap/branch 仍可用 PCWrite_final override）
            if_id_Write = 1'b0;   // freeze IF/ID（保留下一條年輕指令在 ID，不讓它進 EX）
            id_ex_Write = 1'b1;   // allow backend advance
            ex_mem_Write= 1'b1;
            mem_wb_Write= 1'b1;

            hazard_control_mux_sel = 1'b0; // 插入 bubble（讓 EX 成為 NOP）
        end else if (system_inst_stall) begin
            // 0x73 序列化：等待後段清空（drain），同時持續往 EX 注入 bubble 讓後段繼續跑
            PCWrite     = 1'b0;   // freeze PC
            if_id_Write = 1'b0;   // freeze IF/ID（ID 保持這條 0x73）
            id_ex_Write = 1'b1;   // allow backend advance
            ex_mem_Write= 1'b1;
            mem_wb_Write= 1'b1;

            hazard_control_mux_sel = 1'b0; // 插入 bubble（讓 EX 成為 NOP）
        end else if (system_inst_running) begin
            // 0x73 issue 1-cycle：讓 0x73 從 ID 進 EX，同時讓 IF/ID 抓下一條指令
            // PCWrite 必須為 1，維持「PC 領先 ID 一拍」的 pipeline 節奏，否則下一條 0x73 會被重複 issue。
            PCWrite     = 1'b1;
            if_id_Write = 1'b1;
            id_ex_Write = 1'b1;
            ex_mem_Write= 1'b1;
            mem_wb_Write= 1'b1;

            hazard_control_mux_sel = 1'b1; // 不插 bubble，正常送入 EX
        end else if (hazard_stall) begin
            // === load-use / CSR hazard → freeze 前半段(PC/IF_ID)，插入 bubble ===
            PCWrite     = 1'b0;   // freeze PC
            if_id_Write = 1'b0;   // freeze IF/ID
            // 讓後半段繼續
            id_ex_Write = 1'b1;
            ex_mem_Write= 1'b1;
            mem_wb_Write= 1'b1;

            // 插入 bubble：清零控制信號
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

module lsu(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        ex_mem_Write,
    input  logic        mem_MemRead,
    input  logic        mem_MemWrite,
    input  logic        mem_data_write_done,
    input  logic        mem_uart_write_done,
    input  logic        mem_data_read_data_valid,
    input  logic        mem_uart_read_data_valid,
    input  logic [31:0] mem_mux_read_data,
    output logic        mem_MemRead_gated,
    output logic        mem_MemWrite_gated,
    output logic [31:0] mem_read_data_latched,
    output logic [31:0] mem_final_read_data
);

    // --- Architectural Fix for Stalled Memory Ops ---
    logic mem_op_done;

    // Combine done/valid signals
    wire any_mem_done_or_valid;
    assign any_mem_done_or_valid = mem_data_write_done || mem_uart_write_done || mem_data_read_data_valid || mem_uart_read_data_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_op_done <= 1'b0;
            mem_read_data_latched <= 32'h0;
        end else begin
            if (ex_mem_Write) begin // Pipeline advancing (new instruction enters MEM)
                mem_op_done <= 1'b0;
            end else if (any_mem_done_or_valid) begin
                mem_op_done <= 1'b1;
                // Latch data for potential read stall
                if (mem_data_read_data_valid || mem_uart_read_data_valid) begin
                     mem_read_data_latched <= mem_mux_read_data;
                end
            end
        end
    end

    assign mem_MemRead_gated = mem_MemRead && !mem_op_done;
    assign mem_MemWrite_gated = mem_MemWrite && !mem_op_done;

    // Update data path for WB
    assign mem_final_read_data = mem_op_done ? mem_read_data_latched : mem_mux_read_data;

endmodule

module riscv_cpu #(
    // Default keeps existing internal tests (linked at 0) working.
    // For Spike-compatible riscv-tests flow, set to 0x0000_1000 in TB.
    parameter logic [31:0] RESET_PC = 32'h0000_0000
)(
    input  logic clk,
    input  logic btn_reset_n,

    // AXI4-Lite Master Interface
    // --- Address Write ---
    output logic [31:0]  m_axi_awaddr,
    output logic [2:0]   m_axi_awprot,
    output logic         m_axi_awvalid,
    input  logic         m_axi_awready,

    // --- Write Data ---
    output logic [31:0]  m_axi_wdata,
    output logic [3:0]   m_axi_wstrb,
    output logic         m_axi_wvalid,
    input  logic         m_axi_wready,

    // --- Write Response ---
    input  logic [1:0]   m_axi_bresp,
    input  logic         m_axi_bvalid,
    output logic         m_axi_bready,

    // --- Read Address Channel ---
    output logic [31:0]  m_axi_araddr,
    output logic         m_axi_arvalid,
    input  logic         m_axi_arready,

    // --- Read Data ---
    input  logic [31:0]  m_axi_rdata,
    input  logic [1:0]   m_axi_rresp,
    input  logic         m_axi_rvalid,
    output logic         m_axi_rready,

    output logic [7:0] leds
);

    logic uart_rx = 1;
    localparam integer BIT_PERIOD = 104160 * 1000;

// `ifdef XILINX_SIMULATOR
//     logic sys_clk_i = 0;
//     always #10000 sys_clk_i = ~sys_clk_i;
//     //always #10 clk = ~clk;
// `endif

    wire rst_n;
    power_on_reset power_on_reset_0(
        .clk(clk),
        .btn_reset_n(btn_reset_n),
        .rst_n(rst_n)
    );
    // wire rst_n = pll_locked;
    // wire clk;
    // wire clk_200;
    // wire pll_locked;
    // clk_wiz_0 u_clk_wiz_0 (
    //     .clk_out1(clk_200),
    //     .clk_out2(clk),
    //     .resetn(btn_reset_n),
    //     .locked(pll_locked),
    //     .clk_in1(sys_clk_i)
    // );

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
    wire pc_branch_sel;
    wire [31:0] pc_branch_target;

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
    wire id_stage_valid;

    wire id_CsrtoReg;
    wire id_CsrWrite;
    wire [11:0] id_CsrWriteImm12;
    wire [31:0] id_csr_read_data;
    wire [31:0] id_csr_mtvec;
    wire [31:0] id_csr_mepc;
    wire id_csr_src_is_zimm;
    wire [2:0] id_csr_funct3;
    wire id_is_illegal_csr;
    wire id_is_illegal_csr_encoding;
    wire [1:0] id_csr_priv_mode;

    wire mux_id_MemWrite;
    wire mux_id_RegWrite;
    wire mux_id_MemRead;
    wire mux_id_MemtoReg;
    wire mux_id_CsrWrite;
    wire mux_id_CsrtoReg;

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
    wire ex_stage_valid;

    wire [2:0] ex_funct3;
    wire [4:0] ex_rd;
    wire [31:0] ex_pc;
    wire [31:0] ex_inst;

    wire ex_CsrtoReg;
    wire ex_CsrWrite;
    wire [11:0] ex_CsrWriteImm12;
    wire [31:0] ex_csr_read_data;
    wire [31:0] ex_csr_mtvec;
    wire [31:0] ex_csr_mepc;
    wire ex_trap_take;
    wire [31:0] ex_trap_pc;
    wire [31:0] ex_trap_cause;
    wire [31:0] ex_trap_tval;
    wire ex_trap_mret;
    // Pulse trap/mret effects only when EX->MEM is advancing (avoid repeating side-effects on stalls)
    wire ex_trap_take_fire;
    wire ex_trap_mret_fire;
    wire ex_csr_src_is_zimm;
    wire [2:0] ex_csr_funct3;
    wire ex_is_illegal_csr;

    wire [1:0] ForwardA;
    wire [1:0] ForwardB;
    wire [31:0] mux3to1_alu_a_out;
    wire [31:0] mux3to1_alu_b_out;
    wire [31:0] mux3to1_alu_a_operand_out;
    wire [31:0] mux3to1_alu_a_out_forward;

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
    wire [2:0] mem_funct3;
    wire mem_stage_valid;

    wire mem_CsrtoReg;
    wire mem_CsrWrite;
    wire [11:0] mem_CsrWriteImm12;
    wire [31:0] mem_csr_read_data;
    wire [2:0] mem_csr_funct3;

    wire [31:0] mux_alu_out;

    wire [3:0] alu_ctrl;

    wire ex_Zero;
    wire [31:0] ex_alu_out;

    wire [31:0] id_read_data1;
    wire [31:0] id_read_data2;
    wire [31:0] ex_read_data1;
    wire [31:0] ex_read_data2;

    wire [4:0] id_decoded_rs1;
    wire [4:0] id_decoded_rs2;
    wire [4:0] ex_decoded_rs1;
    wire [4:0] ex_decoded_rs2;

    wire wb_RegWrite;
    wire wb_MemtoReg;
    wire [31:0] wb_memory_read_data;
    wire [31:0] wb_alu_out;
    wire [4:0] wb_rd;

    wire wb_CsrtoReg;
    wire wb_CsrWrite;
    wire [11:0] wb_CsrWriteImm12;
    wire [31:0] wb_csr_read_data;
    wire [2:0] wb_csr_funct3;
    wire [31:0] wb_pc;
    wire [31:0] wb_inst;
    wire wb_stage_valid;

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

    // LSU
    wire mem_MemRead_gated;
    wire mem_MemWrite_gated;
    wire [31:0] mem_read_data_latched;
    wire [31:0] mem_final_read_data;

    wire [31:0] wb_reg_write_data;
    wire [31:0] wb_mux_write_data;
    wire [31:0] wb_store_data;

    wire hazard_control_mux_sel;
    wire PCWrite_final;
    assign PCWrite_final = pc_branch_sel ? 1'b1 : PCWrite;
    // 在 hazard_stall 時插入 bubble：以 flush ID/EX 方式把 EX 變成 NOP
    // (因為控制/分支單元是看 ex_inst 解碼，僅清部分控制訊號不足以阻止分支/陷入被觸發)
    wire id_ex_bubble;
    assign id_ex_bubble = !hazard_control_mux_sel; // data hazard bubble (stall_unit 插入)
    wire id_Flush_final;
    // 控制 hazard 的 flush 只能在 ID/EX 允許前進時做。
    // 否則在 if_stall/mem_stall 全線 freeze 時，branch/jal/jalr 會因為 id_Flush 把自己沖成 NOP，
    // 導致「PC 已跳轉但 link 寫回消失」這類錯誤。
    assign id_Flush_final = (id_Flush && id_ex_Write) || id_ex_bubble; // control flush + data-hazard bubble

`ifdef IVERILOG
    // ------------------------------------------------------------
    // Debug: stage_valid/inst trace (for verifying pipeline occupancy)
    // - enable with +DBG
    // - only prints first 120 cycles
    // ------------------------------------------------------------
    int dbg_cycle = 0;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            dbg_cycle <= 0;
        end else begin
            dbg_cycle <= dbg_cycle + 1;
            if ($test$plusargs("DBG") && (dbg_cycle < 120)) begin
                $strobe("[DBG %0d] PC=%08h | ID(V=%0b pc=%08h inst=%08h) EX(V=%0b pc=%08h inst=%08h) MEM(V=%0b pc=%08h inst=%08h) WB(V=%0b pc=%08h inst=%08h) | WE: ifid=%0b idex=%0b exmem=%0b memwb=%0b | FL: if=%0b idex=%0b | pc_br=%0b",
                        dbg_cycle,
                        pc_current,
                        id_stage_valid, id_pc, id_inst,
                        ex_stage_valid, ex_pc, ex_inst,
                        mem_stage_valid, mem_pc, mem_inst,
                        wb_stage_valid, wb_pc, wb_inst,
                        if_id_Write, id_ex_Write, ex_mem_Write, mem_wb_Write,
                        if_Flush, id_Flush_final,
                        pc_branch_sel);
            end
        end
    end
`endif

    program_counter #(.RESET_PC(RESET_PC)) pc_module(
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
        .ex_csr_mtvec(ex_csr_mtvec),
        .ex_csr_mepc(ex_csr_mepc),
        .ex_is_illegal_csr(ex_is_illegal_csr),
        .ex_priv_mode(id_csr_priv_mode),
        .ex_trap_take(ex_trap_take),
        .ex_trap_pc(ex_trap_pc),
        .ex_trap_cause(ex_trap_cause),
        .ex_trap_tval(ex_trap_tval),
        .ex_trap_mret(ex_trap_mret),

        .if_Flush(if_Flush),
        .id_Flush(id_Flush),
        .pc_branch_sel(pc_branch_sel),
        .pc_branch_target(pc_branch_target)
    );

    assign ex_trap_take_fire = ex_trap_take && ex_mem_Write;
    assign ex_trap_mret_fire = ex_trap_mret && ex_mem_Write;

    mux2to1 mux2to1_pc(
        .sel(pc_branch_sel),
        .A(pc_current + 32'd4),
        .B(pc_branch_target),
        .mux_out(pc_next)
    );

    wire if_pc_MemRead;
    wire if_pc_read_data_valid;
    assign if_pc_MemRead = 1'b1;

    instruction_memory_multicycle inst_mem_multicycle_0(
        .clk(clk),
        .rst_n(rst_n),
        .MemRead(1'b1),
        .MemWrite(1'b0),
        .address(pc_current),
        .write_data(),
        .read_data_valid(if_pc_read_data_valid),
        .read_data(if_inst),
        .write_done(),
        .init_calib_complete(1'b1)
    );

    stall_unit stall_unit_0(
        .ex_MemRead(ex_MemRead),
        .ex_rd(ex_rd),
        .id_rs1(id_decoded_rs1),
        .id_rs2(id_decoded_rs2),
        .id_inst(id_inst),
        .ex_inst(ex_inst),
        .mem_inst(mem_inst),
        .wb_inst(wb_inst),
        .ex_CsrWrite(ex_CsrWrite),
        .ex_CsrWriteImm12(ex_CsrWriteImm12),
        .mem_CsrWrite(mem_CsrWrite),
        .mem_CsrWriteImm12(mem_CsrWriteImm12),
        .wb_CsrWrite(wb_CsrWrite),
        .wb_CsrWriteImm12(wb_CsrWriteImm12),
        .if_pc_MemRead(if_pc_MemRead),
        .if_pc_read_data_valid(if_pc_read_data_valid),
        .ex_is_illegal_csr(ex_is_illegal_csr),
        .id_stage_valid(id_stage_valid),
        .ex_stage_valid(ex_stage_valid),
        .mem_stage_valid(mem_stage_valid),
        .wb_stage_valid(wb_stage_valid),
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
        .mem_wb_Write(mem_wb_Write)
    );

    hazard_mux_control hazard_mux_control_0(
        .sel(hazard_control_mux_sel),
        .id_MemWrite(id_MemWrite),
        .id_RegWrite(id_RegWrite),
        .id_MemRead(id_MemRead),
        .id_MemtoReg(id_MemtoReg),
        .id_CsrWrite(id_CsrWrite),
        .id_CsrtoReg(id_CsrtoReg),
        .mux_MemWrite(mux_id_MemWrite),
        .mux_RegWrite(mux_id_RegWrite),
        .mux_MemRead(mux_id_MemRead),
        .mux_MemtoReg(mux_id_MemtoReg),
        .mux_CsrWrite(mux_id_CsrWrite),
        .mux_CsrtoReg(mux_id_CsrtoReg)
    );

    if_id_pipeline if_id_pipeline_0(
        .clk(clk),
        .rst_n(rst_n),
        .if_id_Write(if_id_Write),
        .if_Flush(if_Flush),
        .if_pc(pc_current),
        .if_inst(if_inst),
        .id_pc(id_pc),
        .id_inst(id_inst),
        .id_stage_valid(id_stage_valid)
    );

    id_ex_pipeline id_ex_pipeline_0(
        .clk(clk),
        .rst_n(rst_n),
        .id_ex_Write(id_ex_Write),
        .id_Flush(id_Flush_final),

        .id_ALUSrc(id_ALUSrc),
        .id_ALUSrcA_sel(id_ALUSrcA_sel),
        .id_MemtoReg(mux_id_MemtoReg),
        .id_RegWrite(mux_id_RegWrite),
        .id_MemRead(mux_id_MemRead),
        .id_MemWrite(mux_id_MemWrite),
        .id_Branch(id_Branch),
        .id_ALUOp(id_ALUOp),
        .id_isSub(id_isSub),
        .id_isValid(id_isValid),
        .id_stage_valid(id_stage_valid),

        .id_pc(id_pc),
        .id_inst(id_inst),
        .id_read_data1(id_read_data1),
        .id_read_data2(id_read_data2),
        .id_imm32(id_imm32),
        .id_funct3(id_inst[14:12]),
        .id_rd(id_inst[11:7]),
        .id_decoded_rs1(id_decoded_rs1),
        .id_decoded_rs2(id_decoded_rs2),

        .id_CsrtoReg(mux_id_CsrtoReg),
        .id_CsrWrite(mux_id_CsrWrite),
        .id_CsrWriteImm12(id_CsrWriteImm12),
        .id_csr_read_data(id_csr_read_data),
        .id_csr_mtvec(id_csr_mtvec),
        .id_csr_mepc(id_csr_mepc),
        .id_csr_src_is_zimm(id_csr_src_is_zimm),
        .id_csr_funct3(id_csr_funct3),
        .id_is_illegal_csr(id_is_illegal_csr || id_is_illegal_csr_encoding),

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
        .ex_stage_valid(ex_stage_valid),

        .ex_pc(ex_pc),
        .ex_inst(ex_inst),
        .ex_read_data1(ex_read_data1),
        .ex_read_data2(ex_read_data2),
        .ex_imm32(ex_imm32),
        .ex_funct3(ex_funct3),
        .ex_rd(ex_rd),
        .ex_decoded_rs1(ex_decoded_rs1),
        .ex_decoded_rs2(ex_decoded_rs2),

        .ex_CsrtoReg(ex_CsrtoReg),
        .ex_CsrWrite(ex_CsrWrite),
        .ex_CsrWriteImm12(ex_CsrWriteImm12),
        .ex_csr_read_data(ex_csr_read_data),
        .ex_csr_mtvec(ex_csr_mtvec),
        .ex_csr_mepc(ex_csr_mepc),
        .ex_csr_src_is_zimm(ex_csr_src_is_zimm),
        .ex_csr_funct3(ex_csr_funct3),
        .ex_is_illegal_csr(ex_is_illegal_csr)
    );

    // ------------------------------------------------------------
    // Precise exception requirement:
    // - 當 EX 判定要陷入（ex_trap_take=1）時，該 faulting 指令不得「退休(retire)」
    //   且不得對 GPR/CSR/memory 產生任何寫入副作用。
    // - 這裡做兩件事：
    //   1) gating：把該指令的 write-enable 全部清 0
    //   2) kill stage_valid：確保 WB 不會把它當成退休指令（也方便做 spike-like log）
    // ------------------------------------------------------------
    wire ex_kill_on_trap = ex_trap_take;
    wire ex_RegWrite_eff = ex_RegWrite && !ex_kill_on_trap;
    wire ex_CsrWrite_eff = ex_CsrWrite && !ex_kill_on_trap;
    wire ex_CsrtoReg_eff = ex_CsrtoReg && !ex_kill_on_trap;
    wire ex_MemWrite_eff = ex_MemWrite && !ex_kill_on_trap;
    wire ex_MemRead_eff  = ex_MemRead  && !ex_kill_on_trap;
    wire ex_MemtoReg_eff = ex_MemtoReg && !ex_kill_on_trap;
    wire ex_stage_valid_eff = ex_stage_valid && !ex_kill_on_trap;

    ex_mem_pipeline ex_mem_pipeline0(
        .clk(clk),
        .rst_n(rst_n),
        .ex_mem_Write(ex_mem_Write),
        .ex_MemtoReg(ex_MemtoReg_eff),
        .ex_RegWrite(ex_RegWrite_eff),
        .ex_Branch(ex_Branch),
        .ex_MemRead(ex_MemRead_eff),
        .ex_MemWrite(ex_MemWrite_eff),
        .ex_pc(ex_pc),
        .ex_inst(ex_inst),
        .ex_Zero(ex_Zero),
        .ex_alu_out(ex_alu_out),
        .ex_read_data2(mux3to1_alu_b_out),
        .ex_rd(ex_rd),
        .ex_funct3(ex_funct3),
        .ex_CsrtoReg(ex_CsrtoReg_eff),
        .ex_CsrWrite(ex_CsrWrite_eff),
        .ex_CsrWriteImm12(ex_CsrWriteImm12),
        .ex_csr_read_data(ex_csr_read_data),
        .ex_csr_funct3(ex_csr_funct3),
        .ex_stage_valid(ex_stage_valid_eff),
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
        .mem_rd(mem_rd),
        .mem_funct3(mem_funct3),
        .mem_CsrtoReg(mem_CsrtoReg),
        .mem_CsrWrite(mem_CsrWrite),
        .mem_CsrWriteImm12(mem_CsrWriteImm12),
        .mem_csr_read_data(mem_csr_read_data),
        .mem_csr_funct3(mem_csr_funct3),
        .mem_stage_valid(mem_stage_valid)
    );

    mem_wb_pipeline mem_wb_pipeline_0(
        .clk(clk),
        .rst_n(rst_n),
        .mem_wb_Write(mem_wb_Write),
        .mem_RegWrite(mem_RegWrite),
        .mem_MemtoReg(mem_MemtoReg),
        .mem_memory_read_data(mem_final_read_data),
        .mem_alu_out(mem_alu_out),
        .mem_store_data(mem_read_data2),
        .mem_rd(mem_rd),
        .mem_CsrtoReg(mem_CsrtoReg),
        .mem_CsrWrite(mem_CsrWrite),
        .mem_CsrWriteImm12(mem_CsrWriteImm12),
        .mem_csr_read_data(mem_csr_read_data),
        .mem_csr_funct3(mem_csr_funct3),
        .mem_pc(mem_pc),
        .mem_inst(mem_inst),
        .mem_stage_valid(mem_stage_valid),
        .wb_RegWrite(wb_RegWrite),
        .wb_MemtoReg(wb_MemtoReg),
        .wb_memory_read_data(wb_memory_read_data),
        .wb_alu_out(wb_alu_out),
        .wb_store_data(wb_store_data),
        .wb_rd(wb_rd),
        .wb_CsrtoReg(wb_CsrtoReg),
        .wb_CsrWrite(wb_CsrWrite),
        .wb_CsrWriteImm12(wb_CsrWriteImm12),
        .wb_csr_read_data(wb_csr_read_data),
        .wb_csr_funct3(wb_csr_funct3),
        .wb_pc(wb_pc),
        .wb_inst(wb_inst),
        .wb_stage_valid(wb_stage_valid)
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
        .isValid(id_isValid),
        .decoded_rs1(id_decoded_rs1),
        .decoded_rs2(id_decoded_rs2)
    );

    csr_control_unit csr_control_unit_0(
        .id_inst(id_inst),
        .CsrtoReg(id_CsrtoReg),
        .CsrWrite(id_CsrWrite),
        .CsrWriteImm12(id_CsrWriteImm12),
        .csr_src_is_zimm(id_csr_src_is_zimm),
        .csr_funct3(id_csr_funct3),
        .is_illegal_csr(id_is_illegal_csr_encoding)
    );

    forwarding_unit forwarding_unit_0(
        .mem_RegWrite(mem_RegWrite),
        .wb_RegWrite(wb_RegWrite),
        .mem_rd(mem_rd),
        .wb_rd(wb_rd),
        .ex_rs1(ex_decoded_rs1),
        .ex_rs2(ex_decoded_rs2),
        .ForwardA(ForwardA),
        .ForwardB(ForwardB)
    );

    alu_control alu_control_0(
        .aluop(ex_ALUOp),
        .isSub(ex_isSub),
        .inst30(ex_inst[30]),
        .funct3(ex_funct3),
        .alu_ctrl(alu_ctrl)
    );

    // MEM 階段的最終寫回數據（考慮 CSR）
    wire [31:0] mem_mux_write_data;
    assign mem_mux_write_data = mem_CsrtoReg ? mem_csr_read_data : mem_alu_out;

    mux3to1 mux3to1_alu_a(
        .sel(ForwardA),
        .A(ex_read_data1),
        .B(wb_mux_write_data),      // 修復：使用最終寫回數據（包含 CSR）
        .C(mem_mux_write_data),     // 修復：使用最終寫回數據（包含 CSR）
        .mux_out(mux3to1_alu_a_out_forward)
    );

    mux3to1 mux3to1_alu_b(
        .sel(ForwardB),
        .A(ex_read_data2),
        .B(wb_mux_write_data),      // 修復：使用最終寫回數據（包含 CSR）
        .C(mem_mux_write_data),     // 修復：使用最終寫回數據（包含 CSR）
        .mux_out(mux3to1_alu_b_out)
    );

    mux2to1 mux2to1_alu_a_csr_zimm(
        .sel(ex_csr_src_is_zimm),
        .A(mux3to1_alu_a_out_forward),
        .B(ex_decoded_rs1),
        .mux_out(mux3to1_alu_a_out)
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

    mux2to1 mux2to1_wb_reg_write_data(
        .sel(wb_CsrtoReg),
        .A(wb_reg_write_data),
        .B(wb_csr_read_data),
        .mux_out(wb_mux_write_data)
    );

    register_file reg_file_0(
        .clk(clk),
        .rst_n(rst_n),
        .read_reg1(id_inst[19:15]),
        .read_reg2(id_inst[24:20]),
        .write_reg(wb_rd),
        .RegWrite(wb_RegWrite),
        .write_data(wb_mux_write_data),
        .read_data1(id_read_data1),
        .read_data2(id_read_data2)
    );

    csr_file csr_file_0(
        .clk(clk),
        .rst_n(rst_n),
        .id_inst(id_inst),
        .id_pc(id_pc),
        .CsrWrite(wb_CsrWrite),
        .CsrWriteImm12(wb_CsrWriteImm12),
        .csr_write_data(wb_reg_write_data),
        .csr_funct3(wb_csr_funct3),
        .csr_read_data(id_csr_read_data),
        .ex_trap_take(ex_trap_take_fire),
        .ex_trap_pc(ex_trap_pc),
        .ex_trap_cause(ex_trap_cause),
        .ex_trap_tval(ex_trap_tval),
        .ex_trap_mret(ex_trap_mret_fire),
        .csr_mtvec(id_csr_mtvec),
        .csr_mepc(id_csr_mepc),
        .csr_priv_mode(id_csr_priv_mode),
        .is_illegal_csr(id_is_illegal_csr)
    );

    mux2to1 mux2to1_memory(
        .sel(wb_MemtoReg),
        .A(wb_alu_out),
        .B(wb_memory_read_data),
        .mux_out(wb_reg_write_data)
    );

    lsu lsu_0(
        .clk(clk),
        .rst_n(rst_n),
        .ex_mem_Write(ex_mem_Write),
        .mem_MemRead(mem_MemRead),
        .mem_MemWrite(mem_MemWrite),
        .mem_data_write_done(mem_data_write_done),
        .mem_uart_write_done(mem_uart_write_done),
        .mem_data_read_data_valid(mem_data_read_data_valid),
        .mem_uart_read_data_valid(mem_uart_read_data_valid),
        .mem_mux_read_data(mem_mux_read_data),
        .mem_MemRead_gated(mem_MemRead_gated),
        .mem_MemWrite_gated(mem_MemWrite_gated),
        .mem_read_data_latched(mem_read_data_latched),
        .mem_final_read_data(mem_final_read_data)
    );

    address_decoder address_decoder_0(
        .address(mem_alu_out),
        .mem_MemRead(mem_MemRead_gated),
        .mem_MemWrite(mem_MemWrite_gated),
        .sel(address_sel),
        .memRead_en(memRead_en),
        .memWrite_en(memWrite_en)
    );

    data_memory_multicycle data_memory_multicycle_0(
        .clk(clk),
        .rst_n(rst_n),
        .MemRead(mem_data_MemRead),
        .MemWrite(mem_data_MemWrite),
        .funct3(mem_funct3),
        .address(mem_alu_out),
        .write_data(mem_read_data2),
        .read_data_valid(mem_data_read_data_valid),
        .read_data(mem_memory_read_data),
        .write_done(mem_data_write_done),
        .init_calib_complete(1'b1)
    );

    assign mem_uart_MemRead = memRead_en && address_sel == SEL_UART;
    assign mem_uart_MemWrite = memWrite_en && address_sel == SEL_UART;

    // 換成 axi_uartlite_ctrl 不用減掉 UART_ADDR_OFFSET
    axi_uartlite_ctrl uartlite_ctrl_0(
        .clk(clk),
        .rst_n(rst_n),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awprot(m_axi_awprot),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready),
        .read_enable(mem_uart_MemRead),
        .read_address(mem_alu_out),
        .read_data_valid(mem_uart_read_data_valid),
        .read_data_out(mem_uart_read_data),
        .write_enable(mem_uart_MemWrite),
        .write_address(mem_alu_out),
        .write_data(mem_read_data2),
        .write_done(mem_uart_write_done)
    );

    // uart uart_0(
    //     .clk(clk),
    //     .rst_n(rst_n),
    //     .MemRead(mem_uart_MemRead),
    //     .MemWrite(mem_uart_MemWrite),
    //     .address(mem_alu_out - UART_ADDR_OFFSET),
    //     .write_data(mem_read_data2),
    //     .read_data_valid(mem_uart_read_data_valid),
    //     .read_data(mem_uart_read_data),
    //     .write_done(mem_uart_write_done),
    //     .tx(uart_tx),
    //     .rx(uart_rx)
    // );

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

/*
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
*/

endmodule
