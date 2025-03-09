`timescale 1ns / 1ps
// Create Date: 03/07/2025 01:22:51 PM

module axi4_master_ctrl #(
    parameter ID_WIDTH = 4,
    parameter ADDR_WIDTH = 28,
    parameter DATA_WIDTH = 128
)(
    // 時鐘和重置信號
    input wire clk,
    input wire rst_n,
    input wire init_calib_complete,

    // 寫地址通道 (AW)
    output reg [ID_WIDTH-1:0] s_axi_awid,
    output reg [ADDR_WIDTH-1:0] s_axi_awaddr,
    output reg [7:0] s_axi_awlen,
    output reg [2:0] s_axi_awsize,
    output reg [1:0] s_axi_awburst,
    output reg s_axi_awlock,
    output reg [3:0] s_axi_awcache,
    output reg [2:0] s_axi_awprot,
    output reg [3:0] s_axi_awqos,
    output reg [3:0] s_axi_awregion,
    output reg s_axi_awvalid,
    input wire s_axi_awready,
    
    // 寫數據通道 (W)
    output reg [DATA_WIDTH-1:0] s_axi_wdata,
    output reg [(DATA_WIDTH/8)-1:0] s_axi_wstrb,
    output reg s_axi_wlast,
    output reg s_axi_wvalid,
    input wire s_axi_wready,
    
    // 寫響應通道 (B)
    input wire [ID_WIDTH-1:0] s_axi_bid,
    input wire [1:0] s_axi_bresp,
    input wire s_axi_bvalid,
    output reg s_axi_bready,
    
    // 讀地址通道 (AR)
    output reg [ID_WIDTH-1:0] s_axi_arid,
    output reg [ADDR_WIDTH-1:0] s_axi_araddr,
    output reg [7:0] s_axi_arlen,
    output reg [2:0] s_axi_arsize,
    output reg [1:0] s_axi_arburst,
    output reg s_axi_arlock,
    output reg [3:0] s_axi_arcache,
    output reg [2:0] s_axi_arprot,
    output reg [3:0] s_axi_arqos,
    output reg [3:0] s_axi_arregion,
    output reg s_axi_arvalid,
    input wire s_axi_arready,
    
    // 讀數據通道 (R)
    input wire [ID_WIDTH-1:0] s_axi_rid,
    input wire [DATA_WIDTH-1:0] s_axi_rdata,
    input wire [1:0] s_axi_rresp,
    input wire s_axi_rlast,
    input wire s_axi_rvalid,
    output reg s_axi_rready,

    input  logic         read_enable,
    input  logic [31:0]  read_address,
    output logic         read_data_valid,
    output logic [31:0]  read_data_out,
    input  logic         write_enable,
    input  logic [31:0]  write_address,
    input  logic [31:0]  write_data,
    output logic         write_done
);

    // AXI 響應碼
    localparam RESP_OKAY = 2'b00;    // 正常完成

    // 狀態機定義
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

    // 狀態機實現
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 重置所有信號
            state <= IDLE;
            read_data_out <= 0;
            read_data_valid <= 0;
            write_done <= 0;

            // 重置 AXI 介面信號
            s_axi_awid <= 0;
            s_axi_awaddr <= 0;
            s_axi_awlen <= 0;
            s_axi_awsize <= 0;
            s_axi_awburst <= 0;
            s_axi_awlock <= 0;
            s_axi_awcache <= 0;
            s_axi_awprot <= 0;
            s_axi_awqos <= 0;
            s_axi_awregion <= 0;
            s_axi_awvalid <= 0;
            
            s_axi_wdata <= 0;
            s_axi_wstrb <= 0;
            s_axi_wlast <= 0;
            s_axi_wvalid <= 0;
            
            s_axi_bready <= 0;
            
            s_axi_arid <= 0;
            s_axi_araddr <= 0;
            s_axi_arlen <= 0;
            s_axi_arsize <= 0;
            s_axi_arburst <= 0;
            s_axi_arlock <= 0;
            s_axi_arcache <= 0;
            s_axi_arprot <= 0;
            s_axi_arqos <= 0;
            s_axi_arregion <= 0;
            s_axi_arvalid <= 0;
            
            s_axi_rready <= 0;
        end else begin
            case (state)
                IDLE: begin
                    read_data_valid <= 0;
                    write_done <= 0;
                    if (init_calib_complete) begin
                        if (read_enable) begin
                            state <= READ_ADDR;
                        end else if (write_enable) begin
                            state <= WRITE_ADDR;
                        end else begin
                            state <= IDLE;
                        end
                    end
                end
                
                WRITE_ADDR: begin
                    // 設置寫地址通道信號
                    s_axi_awid <= 0;
                    s_axi_awaddr <= write_address;   // 地址 TODO: 要記得這是 28bits
                    s_axi_awlen <= 0;                // 單次傳輸
                    s_axi_awsize <= 3'b100;          // 16 字節 (128 位)
                    s_axi_awburst <= 2'b01;          // INCR 類型
                    s_axi_awlock <= 0;
                    s_axi_awcache <= 0;
                    s_axi_awprot <= 0;
                    s_axi_awqos <= 0;
                    s_axi_awregion <= 0;
                    s_axi_awvalid <= 1;              // 有效地址
                    
                    // 等待握手完成
                    if (s_axi_awready && s_axi_awvalid) begin
                        s_axi_awvalid <= 0;          // 釋放 valid 信號
                        state <= WRITE_DATA;
                    end
                end
                
                WRITE_DATA: begin
                    // 設置寫數據通道信號
                    case (write_address[3:0])
                        4'd0:  begin
                            s_axi_wdata <= {96'b0, write_data};
                            s_axi_wstrb <= 'h000F;
                        end
                        4'd4:  begin
                            s_axi_wdata <= {64'b0, write_data, 32'b0};
                            s_axi_wstrb <= 'h00F0;
                        end
                        4'd8:  begin
                            s_axi_wdata <= {32'b0, write_data, 64'b0};
                            s_axi_wstrb <= 'h0F00;
                        end
                        4'd12: begin
                            s_axi_wdata <= {write_data, 96'b0};
                            s_axi_wstrb <= 'hF000;
                        end
                    endcase
                    s_axi_wlast <= 1;                // 最後一個數據
                    s_axi_wvalid <= 1;               // 有效數據
                    
                    // 等待握手完成
                    if (s_axi_wready && s_axi_wvalid) begin
                        s_axi_wvalid <= 0;           // 釋放 valid 信號
                        s_axi_wlast <= 0;            // 清除 last 信號
                        state <= WRITE_RESP;
                    end
                end
                
                WRITE_RESP: begin
                    // 設置寫響應通道信號
                    s_axi_bready <= 1;               // 準備接收響應
                    
                    // 等待握手完成並檢查響應
                    if (s_axi_bvalid && s_axi_bready) begin
                        if (s_axi_bresp == RESP_OKAY) begin
                            write_done <= 1;
                        end
                        s_axi_bready <= 0;           // 釋放 ready 信號
                        state <= WRITE_DONE;          // 進入 IDLE
                    end
                end

                WRITE_DONE: begin
                    write_done <= 0;
                    state <= IDLE;
                end

                READ_ADDR: begin
                    // 設置讀地址通道信號
                    s_axi_arid <= 0;
                    s_axi_araddr <= read_address;         // 地址 TODO: 要記得這是 28bits
                    s_axi_arlen <= 0;                // 單次傳輸
                    s_axi_arsize <= 3'b100;          // 16 字節 (128 位)
                    s_axi_arburst <= 2'b01;          // INCR 類型
                    s_axi_arlock <= 0;
                    s_axi_arcache <= 0;
                    s_axi_arprot <= 0;
                    s_axi_arqos <= 0;
                    s_axi_arregion <= 0;
                    s_axi_arvalid <= 1;              // 有效地址
                    write_done <= 0;

                    // 等待握手完成
                    if (s_axi_arready && s_axi_arvalid) begin
                        s_axi_arvalid <= 0;          // 釋放 valid 信號
                        state <= READ_DATA;
                    end
                end
                
                READ_DATA: begin
                    // 設置讀數據通道信號
                    s_axi_rready <= 1;               // 準備接收數據
                    
                    // 等待握手完成並檢查響應
                    if (s_axi_rvalid && s_axi_rready) begin
                        if (s_axi_rresp == RESP_OKAY) begin
                            case (read_address[3:0])
                                4'd0: read_data_out <= s_axi_rdata[31:0];
                                4'd4: read_data_out <= s_axi_rdata[63:32];
                                4'd8: read_data_out <= s_axi_rdata[95:64];
                                4'd12: read_data_out <= s_axi_rdata[127:96];
                                default: read_data_out <= 32'h0;
                            endcase
                            read_data_out <= s_axi_rdata >> {read_address[3:0], 3'b000};
                            read_data_valid <= 1;
                        end
                        
                        if (s_axi_rlast) begin
                            s_axi_rready <= 0;          // 釋放 ready 信號
                            state <= READ_DONE;
                        end
                    end
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