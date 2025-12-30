`timescale 1ps / 1ps
// Create Date: 02/15/2025 01:47:54 AM

`ifdef IVERILOG
`include "axi_uartlite_simple.sv"
`endif

module axi_uartlite_ctrl(
    input  logic         clk,
    input  logic         rst_n,

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

    // --- Read Data ---
    output logic [31:0]  m_axi_araddr,
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

    // =========================================================================
    // 狀態機定義
    // =========================================================================
    typedef enum logic [2:0] {
        IDLE        = 3'd0,
        // 寫入相關狀態
        WRITE_ADDR  = 3'd1,  // 發送寫入地址和數據
        WRITE_RESP  = 3'd2,  // 等待寫入回應
        WRITE_DONE  = 3'd3,  // 寫入完成，產生 write_done 脈衝
        // 讀取相關狀態
        READ_ADDR   = 3'd4,  // 發送讀取地址
        READ_DATA   = 3'd5,  // 等待讀取數據
        READ_DONE   = 3'd6   // 讀取完成，產生 read_data_valid 脈衝
    } state_t;

    state_t state;

    // =========================================================================
    // 內部暫存器
    // =========================================================================
    logic [31:0] addr_reg;       // 暫存地址 (byte address)
    logic [31:0] wdata_reg;      // 暫存寫入數據
    logic [31:0] rdata_reg;      // 暫存讀取數據
    logic        aw_done;        // 寫地址已被接受
    logic        w_done;         // 寫數據已被接受

    // =========================================================================
    // AXI 保護信號 (固定值)
    // =========================================================================
    assign m_axi_awprot = 3'b000;  // Unprivileged, secure, data access
    assign m_axi_wstrb  = 4'b1111; // 全部 byte 有效

    // =========================================================================
    // 主狀態機 (單一 always_ff 塊，確保時序一致)
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            addr_reg  <= 4'h0;
            wdata_reg <= 32'h0;
            rdata_reg <= 32'h0;
            aw_done   <= 1'b0;
            w_done    <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    aw_done <= 1'b0;
                    w_done  <= 1'b0;
                    if (write_enable) begin
                        // 鎖存寫入地址和數據，然後開始傳輸
                        addr_reg  <= write_address;
                        wdata_reg <= write_data;
                        state     <= WRITE_ADDR;
                        //$display("[UART %0t] IDLE->WRITE_ADDR: addr=%h data=%h", $time, write_address[3:0], write_data);
                    end else if (read_enable) begin
                        // 鎖存讀取地址，然後開始傳輸
                        addr_reg <= read_address;
                        state    <= READ_ADDR;
                        //$display("[UART %0t] IDLE->READ_ADDR: addr=%h", $time, read_address[3:0]);
                    end
                end

                // =============================================================
                // 寫入流程
                // =============================================================
                WRITE_ADDR: begin
                    // 追蹤寫地址是否已被接受
                    if (m_axi_awvalid && m_axi_awready) begin
                        aw_done <= 1'b1;
                        //$display("[UART %0t] WRITE_ADDR: aw handshake done", $time);
                    end
                    // 追蹤寫數據是否已被接受
                    if (m_axi_wvalid && m_axi_wready) begin
                        w_done <= 1'b1;
                        //$display("[UART %0t] WRITE_ADDR: w handshake done, wdata=%h", $time, wdata_reg);
                    end
                    // 當兩者都完成後，進入等待回應狀態
                    if ((aw_done || (m_axi_awvalid && m_axi_awready)) &&
                        (w_done  || (m_axi_wvalid  && m_axi_wready))) begin
                        state <= WRITE_RESP;
                        //$display("[UART %0t] WRITE_ADDR->WRITE_RESP", $time);
                    end
                end

                WRITE_RESP: begin
                    // 等待寫回應
                    if (m_axi_bvalid) begin
                        state <= WRITE_DONE;
                        //$display("[UART %0t] WRITE_RESP->WRITE_DONE: bvalid=1", $time);
                    end
                end

                WRITE_DONE: begin
                    // 產生 write_done 脈衝後回到 IDLE
                    // 這個狀態確保 write_done 持續一個完整週期
                    state   <= IDLE;
                    aw_done <= 1'b0;
                    w_done  <= 1'b0;
                    //$display("[UART %0t] WRITE_DONE->IDLE: write_done pulse!", $time);
                end

                // =============================================================
                // 讀取流程
                // =============================================================
                READ_ADDR: begin
                    // 等待讀地址被接受
                    if (m_axi_arvalid && m_axi_arready) begin
                        state <= READ_DATA;
                    end
                end

                READ_DATA: begin
                    // 等待讀數據返回
                    if (m_axi_rvalid) begin
                        rdata_reg <= m_axi_rdata;
                        state     <= READ_DONE;
                    end
                end

                READ_DONE: begin
                    // 產生 read_data_valid 脈衝後回到 IDLE
                    state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end


    // =========================================================================
    // AXI 寫地址通道輸出
    // =========================================================================
    assign m_axi_awaddr  = addr_reg;
    assign m_axi_awvalid = (state == WRITE_ADDR) && !aw_done;

    // =========================================================================
    // AXI 寫數據通道輸出
    // =========================================================================
    assign m_axi_wdata  = wdata_reg;
    assign m_axi_wvalid = (state == WRITE_ADDR) && !w_done;

    // =========================================================================
    // AXI 寫回應通道輸出
    // =========================================================================
    assign m_axi_bready = (state == WRITE_RESP);

    // =========================================================================
    // AXI 讀地址通道輸出
    // =========================================================================
    assign m_axi_araddr  = addr_reg;
    assign m_axi_arvalid = (state == READ_ADDR);

    // =========================================================================
    // AXI 讀數據通道輸出
    // =========================================================================
    assign m_axi_rready = (state == READ_DATA);

    // =========================================================================
    // CPU 接口輸出
    // =========================================================================
    // 寫入完成信號 - 在 WRITE_DONE 狀態產生一個週期的脈衝
    assign write_done = (state == WRITE_DONE);

    // 讀取完成信號 - 在 READ_DONE 狀態產生一個週期的脈衝
    assign read_data_valid = (state == READ_DONE);
    assign read_data_out   = rdata_reg;

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
    output wire tx,
    input logic rx
);

    wire [31:0]  axi_awaddr;
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
    wire [31:0]  axi_araddr;
    wire         axi_arvalid;
    wire         axi_arready;
    wire [31:0]  axi_rdata;
    wire [1:0]   axi_rresp;
    wire         axi_rvalid;
    wire         axi_rready;

    wire uart_interrupt;

/*
`ifdef IVERILOG
    `define UART_MODULE_TYPE axi_uartlite_simple
`else
    `define UART_MODULE_TYPE axi_uartlite_0
`endif

    `UART_MODULE_TYPE uartlite_0(
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
        .rx(rx),
        .interrupt(uart_interrupt)
    );
*/

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
