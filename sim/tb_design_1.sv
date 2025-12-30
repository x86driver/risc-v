// Create Date: 12/28/2025 03:15:20 PM

`timescale 1ns / 1ps

module tb_design_1;

    // ==========================================
    // 1. 宣告訊號 (連接到你的 Wrapper)
    // ==========================================
    logic sysclk_p;
    logic sysclk_n;
    logic reset;
    logic rs232_uart_rxd;  // 這是給 FPGA 的輸入 (模擬電腦送字元給 FPGA)
    wire  rs232_uart_txd;  // 這是 FPGA 的輸出 (FPGA 送字元出來)

    // 定義時脈週期: 125MHz = 8ns
    localparam CLK_PERIOD = 8.0;
    
    // 定義 UART Baud Rate (假設你設 115200)
    localparam BAUD_RATE = 115200;
    localparam BIT_PERIOD_NS = 1000000000.0 / BAUD_RATE; // 每個 bit 的奈秒數

    // ==========================================
    // 2. 實例化 (Instantiate) 你的 Wrapper
    // ==========================================
    design_1_wrapper dut (
        .sysclk_125_clk_p(sysclk_p),
        .sysclk_125_clk_n(sysclk_n),
        .reset(reset),
        .rs232_uart_rxd(rs232_uart_rxd),
        .rs232_uart_txd(rs232_uart_txd)
    );

    // ==========================================
    // 3. 產生差分時脈 (Differential Clock)
    // ==========================================
    initial begin
        sysclk_p = 0;
        sysclk_n = 1; // 差分訊號必須相反
        forever begin
            #(CLK_PERIOD / 2.0); // 等待半個週期 (4ns)
            sysclk_p = ~sysclk_p;
            sysclk_n = ~sysclk_n;
        end
    end

    // ==========================================
    // 4. 主要測試流程 (Initial Block)
    // ==========================================
    initial begin
        // --- 初始化狀態 ---
        reset = 1;          // 按下 Reset (假設 Active High)
        rs232_uart_rxd = 1; // UART Idle 狀態必須是 High (1)
        
        // --- 等待 100ns 後釋放 Reset ---
        #100;
        reset = 0;          // 放開 Reset，系統開始跑
        $display("System Reset Released...");

        // --- 可以在這裡觀察波形 ---
        // 如果你的 CPU 有接好並跑 code，它可能會開始動作
        
        // --- (選用) 模擬電腦送一個字元 'A' 給 FPGA ---
        #2000; // 等系統穩定
        send_uart_byte(8'h41); // 送出 'A' (Hex 41)

        // --- 讓模擬跑一陣子 ---
        #50000;
        //$finish; // 結束模擬
    end

    // ==========================================
    // 5. 輔助 Task: 模擬 UART 傳送一個 Byte
    // ==========================================
    task send_uart_byte(input [7:0] data);
        integer i;
        begin
            $display("Sending UART Byte: %h", data);
            
            // Start Bit (Low)
            rs232_uart_rxd = 0;
            #(BIT_PERIOD_NS);
            
            // Data Bits (LSB First)
            for (i = 0; i < 8; i = i + 1) begin
                rs232_uart_rxd = data[i];
                #(BIT_PERIOD_NS);
            end
            
            // Stop Bit (High)
            rs232_uart_rxd = 1;
            #(BIT_PERIOD_NS);
        end
    endtask

endmodule
