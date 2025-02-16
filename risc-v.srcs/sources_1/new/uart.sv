`timescale 1ns / 1ps
// Create Date: 02/15/2025 01:47:54 AM

module axi_uartlite_ctrl(
    input  logic         clk,
    input  logic         rst_n,

    // AXI4-Lite Master Interface
    // --- Address Write ---
    output logic [3:0]   m_axi_awaddr,
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

    // --- Read Data ---
    output logic [3:0]   m_axi_araddr,
    output logic         m_axi_arvalid,
    input  logic         m_axi_arready,
    input  logic [31:0]  m_axi_rdata,
    input  logic [1:0]   m_axi_rresp,
    input  logic         m_axi_rvalid,
    output logic         m_axi_rready,

    input  logic         read_enable,
    input  logic [31:0]  read_address,
    output logic         read_data_valid,
    output logic [31:0]  read_data_out,
    input  logic         write_enable,
    input  logic [31:0]  write_address,
    input  logic [31:0]  write_data,
    output logic         write_done
);

    // 狀態定義
    typedef enum logic [2:0] {
        IDLE       = 3'd0,
        WRITE_IDLE = 3'd1,
        WAIT_B     = 3'd2,
        WRITE_DONE = 3'd3,
        READ_IDLE  = 3'd4,
        AR_SEND    = 3'd5,
        WAIT_RDATA = 3'd6,
        READ_DONE  = 3'd7
    } state_t;

    state_t curr_state = IDLE, next_state = IDLE;

    logic read_data_valid_reg = 0;
    logic write_done_reg = 1;
    logic [31:0] read_data_reg = 0;
    assign read_data_valid = read_data_valid_reg;
    assign read_data_out = read_data_reg;
    assign write_done = write_done_reg;

    //-------------------------------------
    // 狀態暫存器
    //-------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            curr_state <= IDLE;
        end else begin
            curr_state <= next_state;
        end
    end

    //-------------------------------------
    // 狀態轉移條件
    //-------------------------------------
    always_comb begin
        next_state = curr_state;
        case (curr_state)
            IDLE: begin
                if (read_enable) begin
                    next_state = READ_IDLE;
                end else if (write_enable) begin
                    next_state = WRITE_IDLE;
                end else begin
                    next_state = IDLE;
                end
            end
            WRITE_IDLE: begin
                // 等待寫地址 (AW) 和寫資料 (W) 同時被 slave 接受
                if (m_axi_awready && m_axi_wready) begin
                    next_state = WAIT_B;
                end
            end

            WAIT_B: begin
                // 等待寫回應 (BVALID)
                if (m_axi_bvalid) begin
                    next_state = WRITE_DONE;
                end
            end

            WRITE_DONE: begin
                // 完成後就不再動作
                next_state = IDLE;
            end

            READ_IDLE: begin
                if (read_enable) begin
                    next_state = AR_SEND;
                end
            end

            AR_SEND: begin
                if (m_axi_arready) begin
                    next_state = WAIT_RDATA;
                end
            end

            WAIT_RDATA: begin
                if (m_axi_rvalid) begin
                    next_state = READ_DONE;
                end
            end

            READ_DONE: begin
                next_state = IDLE;
            end
        endcase
    end

    //-------------------------------------
    // 輸出控制與暫存器操作
    //-------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_awvalid <= 1'b0;
            m_axi_awaddr  <= 4'h0;
            m_axi_awprot  <= 3'b000;

            m_axi_wvalid  <= 1'b0;
            m_axi_wdata   <= 32'h0;
            m_axi_wstrb   <= 4'hF;

            m_axi_bready  <= 1'b0;

            m_axi_araddr  <= 0;
            m_axi_arvalid <= 0;
            m_axi_rready  <= 0;

            read_data_reg <= 0;
            write_done_reg <= 1;
        end
        else begin
            case (curr_state)
                IDLE: begin
                    if (write_enable) begin
                        write_done_reg <= 1'b0;
                    end else begin
                        write_done_reg <= 1'b1;
                    end
                end

                // 初始狀態，準備好 AWVALID / WVALID
                // 要寫的地址(0x4) 和資料(0x55) 在這裡設定
                WRITE_IDLE: begin
                    // Assert AWVALID / WVALID
                    m_axi_awvalid <= 1'b1;
                    m_axi_awaddr  <= write_address[3:0];   // UartLite TX FIFO register offset
                    m_axi_awprot  <= 3'b000;  // 一般寫操作，保留為 000

                    m_axi_wvalid  <= 1'b1;
                    m_axi_wdata   <= write_data;  // 資料放在最低 8 bits
                    m_axi_wstrb   <= 4'hF;    // 全部 byte lane 都可寫

                    m_axi_bready  <= 1'b0;    // 目前先不用回應
                end

                // 寫地址、資料都 handshake 完成後，等待 BVALID
                WAIT_B: begin
                    // AW 與 W 已經送出，不再有效
                    m_axi_awvalid <= 1'b0;
                    m_axi_wvalid  <= 1'b0;
                    // 準備接收回應
                    m_axi_bready  <= 1'b1;
                end

                // 寫操作完成
                WRITE_DONE: begin
                    // 不再需要 bready，或你也可以一直拉高
                    m_axi_bready <= 1'b0;
                    write_done_reg <= 1'b1;
                end

                READ_IDLE: begin
                    read_data_valid_reg <= 1'b0;
                    m_axi_araddr <= read_address[3:0];
                    m_axi_arvalid <= 1'b0;
                    m_axi_rready <= 1'b0;
                end

                AR_SEND: begin
                    read_data_valid_reg <= 1'b0;
                    m_axi_arvalid <= 1'b1;
                    m_axi_rready <= 1'b0;
                end

                WAIT_RDATA: begin
                    read_data_valid_reg <= 1'b0;
                    m_axi_arvalid <= 1'b0;
                    m_axi_rready <= 1'b1;

                    if (m_axi_rvalid) begin
                        read_data_valid_reg <= 1'b1;
                        read_data_reg <= m_axi_rdata;
                    end
                end

                READ_DONE: begin
                    read_data_valid_reg <= 1'b0;
                    m_axi_arvalid <= 1'b0;
                    m_axi_rready <= 1'b0;
                end
            endcase
        end
    end

endmodule

module uart(
    input logic clk,
    input logic rst_n,
    input logic MemRead,
    input logic MemWrite,
    input logic [31:0] address,
    input logic [31:0] write_data,
    output logic read_data_valid,
    output logic [31:0] read_data,
    output logic write_done,
    output wire tx
);

    wire [3:0]   axi_awaddr;
    wire         axi_awvalid;
    wire         axi_awready;

    // --- Write Data ---
    wire [31:0]  axi_wdata;
    wire [3:0]   axi_wstrb;
    wire         axi_wvalid;
    wire         axi_wready;

    // --- Write Response ---
    wire [1:0]   axi_bresp;
    wire         axi_bvalid;
    wire         axi_bready;

    // --- Read ---
    wire [3:0]   axi_araddr;
    wire         axi_arvalid;
    wire         axi_arready;
    wire [31:0]  axi_rdata;
    wire [1:0]   axi_rresp;
    wire         axi_rvalid;
    wire         axi_rready;

    axi_uartlite_0 uartlite_0(
        .s_axi_aclk(clk),
        .s_axi_aresetn(rst_n),
        .s_axi_awaddr(axi_awaddr),
        .s_axi_awvalid(axi_awvalid),
        .s_axi_awready(axi_awready),
        .s_axi_wdata(axi_wdata),
        .s_axi_wstrb(axi_wstrb),
        .s_axi_wvalid(axi_wvalid),
        .s_axi_wready(axi_wready),
        .s_axi_bresp(axi_bresp),
        .s_axi_bvalid(axi_bvalid),
        .s_axi_bready(axi_bready),
        .s_axi_araddr(axi_araddr),
        .s_axi_arvalid(axi_arvalid),
        .s_axi_arready(axi_arready),
        .s_axi_rdata(axi_rdata),
        .s_axi_rresp(axi_rresp),
        .s_axi_rvalid(axi_rvalid),
        .s_axi_rready(axi_rready),
        .tx(tx),
        .rx(1'b1)
    );

    axi_uartlite_ctrl uartlite_ctrl_0(
        .clk(clk),
        .rst_n(rst_n),
        .m_axi_awaddr(axi_awaddr),
        .m_axi_awvalid(axi_awvalid),
        .m_axi_awready(axi_awready),
        .m_axi_wdata(axi_wdata),
        .m_axi_wstrb(axi_wstrb),
        .m_axi_wvalid(axi_wvalid),
        .m_axi_wready(axi_wready),
        .m_axi_bresp(axi_bresp),
        .m_axi_bvalid(axi_bvalid),
        .m_axi_bready(axi_bready),
        .m_axi_araddr(axi_araddr),
        .m_axi_arvalid(axi_arvalid),
        .m_axi_arready(axi_arready),
        .m_axi_rdata(axi_rdata),
        .m_axi_rresp(axi_rresp),
        .m_axi_rvalid(axi_rvalid),
        .m_axi_rready(axi_rready),
        .read_enable(MemRead),
        .read_address(address),
        .read_data_valid(read_data_valid),
        .read_data_out(read_data),
        .write_enable(MemWrite),
        .write_address(address),
        .write_data(write_data),
        .write_done(write_done)
    );

endmodule
