`timescale 1ps / 1ps
// 簡化版 AXI UART Lite Slave
// 僅用於 simulation，只處理 TX（寫入時直接印出字元）

module axi_uartlite_simple (
    input  logic        s_axi_aclk,
    input  logic        s_axi_aresetn,

    // AXI4-Lite Slave Interface
    // --- Write Address ---
    input  logic [3:0]  s_axi_awaddr,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,

    // --- Write Data ---
    input  logic [31:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,

    // --- Write Response ---
    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,

    // --- Read Address ---
    input  logic [3:0]  s_axi_araddr,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,

    // --- Read Data ---
    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,

    // UART signals (unused in simple version)
    output logic        tx,
    input  logic        rx,
    output logic        interrupt
);

    // AXI UART Lite 寄存器地址定義
    localparam ADDR_RX_FIFO  = 4'h0;  // RX FIFO (read)
    localparam ADDR_TX_FIFO  = 4'h4;  // TX FIFO (write)
    localparam ADDR_STATUS   = 4'h8;  // Status Register (read)
    localparam ADDR_CONTROL  = 4'hC;  // Control Register (read/write)

    // Status Register bits
    // Bit 0: RX FIFO Valid Data (always 0 - no RX support)
    // Bit 1: RX FIFO Full (always 0)
    // Bit 2: TX FIFO Empty (always 1 - always ready)
    // Bit 3: TX FIFO Full (always 0 - never full)
    localparam STATUS_REG = 32'h0000_0004;  // TX FIFO Empty = 1

    // 寫入狀態機
    typedef enum logic [1:0] {
        W_IDLE,
        W_DATA,
        W_RESP
    } write_state_t;

    write_state_t w_state = W_IDLE;

    // 讀取狀態機
    typedef enum logic [1:0] {
        R_IDLE,
        R_DATA
    } read_state_t;

    read_state_t r_state = R_IDLE;

    // 暫存寫入地址
    logic [3:0] awaddr_reg;

    // 未使用的輸出
    assign tx = 1'b1;        // TX idle high
    assign interrupt = 1'b0; // 不產生中斷

    //=========================================
    // 寫入通道處理
    //=========================================
    always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            w_state <= W_IDLE;
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
            awaddr_reg    <= 4'h0;
        end else begin
            case (w_state)
                W_IDLE: begin
                    s_axi_bvalid <= 1'b0;
                    // 等待寫入地址和資料同時有效
                    if (s_axi_awvalid && s_axi_wvalid) begin
                        s_axi_awready <= 1'b1;
                        s_axi_wready  <= 1'b1;
                        awaddr_reg    <= s_axi_awaddr;
                        w_state       <= W_DATA;
                    end else if (s_axi_awvalid) begin
                        // 只有地址有效，先接受地址
                        s_axi_awready <= 1'b1;
                        awaddr_reg    <= s_axi_awaddr;
                        w_state       <= W_DATA;
                    end else begin
                        s_axi_awready <= 1'b0;
                        s_axi_wready  <= 1'b0;
                    end
                end

                W_DATA: begin
                    s_axi_awready <= 1'b0;
                    
                    if (s_axi_wvalid) begin
                        s_axi_wready <= 1'b1;
                        
                        // 如果寫入 TX FIFO，印出字元
                        if (awaddr_reg == ADDR_TX_FIFO) begin
                            $write("%c", s_axi_wdata[7:0]);
                        end
                        
                        w_state <= W_RESP;
                    end else begin
                        s_axi_wready <= 1'b0;
                    end
                end

                W_RESP: begin
                    s_axi_awready <= 1'b0;
                    s_axi_wready  <= 1'b0;
                    s_axi_bresp   <= 2'b00;  // OKAY

                    // 正確的 AXI 握手：先設置 bvalid，當 bvalid && bready 時完成
                    if (!s_axi_bvalid) begin
                        // 剛進入 W_RESP，設置 bvalid
                        s_axi_bvalid <= 1'b1;
                    end else if (s_axi_bready) begin
                        // bvalid 已經是 1 且 bready 也是 1，握手完成
                        s_axi_bvalid <= 1'b0;
                        w_state      <= W_IDLE;
                    end
                end

                default: begin
                    w_state <= W_IDLE;
                end
            endcase
        end
    end

    //=========================================
    // 讀取通道處理
    //=========================================
    logic [3:0] araddr_reg;

    always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            r_state <= R_IDLE;
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= 32'h0;
            s_axi_rresp   <= 2'b00;
            araddr_reg    <= 4'h0;
        end else begin
            case (r_state)
                R_IDLE: begin
                    s_axi_rvalid <= 1'b0;
                    if (s_axi_arvalid) begin
                        s_axi_arready <= 1'b1;
                        araddr_reg    <= s_axi_araddr;
                        r_state       <= R_DATA;
                    end else begin
                        s_axi_arready <= 1'b0;
                    end
                end

                R_DATA: begin
                    s_axi_arready <= 1'b0;
                    s_axi_rvalid  <= 1'b1;
                    s_axi_rresp   <= 2'b00;  // OKAY

                    // 根據地址返回對應資料
                    case (araddr_reg)
                        ADDR_RX_FIFO: s_axi_rdata <= 32'h0;        // 沒有 RX 資料
                        ADDR_TX_FIFO: s_axi_rdata <= 32'h0;        // TX FIFO 不可讀
                        ADDR_STATUS:  s_axi_rdata <= STATUS_REG;   // Status: TX Empty
                        ADDR_CONTROL: s_axi_rdata <= 32'h0;        // Control register
                        default:      s_axi_rdata <= 32'h0;
                    endcase

                    if (s_axi_rready) begin
                        s_axi_rvalid <= 1'b0;
                        r_state      <= R_IDLE;
                    end
                end

                default: begin
                    r_state <= R_IDLE;
                end
            endcase
        end
    end

endmodule
