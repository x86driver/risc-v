`timescale 1ns / 1ps
// Create Date: 02/01/2025 02:40:05 AM

module uart_tx(
    input logic clk,
    input logic rst_n,
    input logic start,
    input logic [7:0] data,
    input logic baud_clk,
    output logic tx,
    output logic tx_busy
);

    localparam IDLE  = 2'b00;
    localparam START = 2'b01;
    localparam SEND  = 2'b10;
    localparam STOP  = 2'b11;

    reg [7:0] tx_send_buffer = data;
    reg [1:0] state = IDLE, nstate = IDLE;
    reg [3:0] counter = 0;
    logic start_send = 0;

    assign tx_busy = (state != IDLE);

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            counter <= 0;
            start_send <= 0;
            tx_send_buffer <= 8'h00;
        end else begin
            state <= nstate;

            if (start) begin
                start_send <= 1;
                tx_send_buffer <= data;
            end

            if (nstate == START) begin
                if (state == IDLE) begin
                    tx_send_buffer <= data;
                end
            end

            if (state == SEND && baud_clk) begin
                counter <= counter + 1;
            end else if (state == IDLE) begin
                counter <= 0;
            end else if (state == STOP) begin
                start_send <= 0;
            end
        end
    end

    always @(*) begin
        nstate = state;

        case (state)
            IDLE: begin
                if (baud_clk && start_send)
                    nstate = START;
            end
            START: begin
                if (baud_clk)
                    nstate = SEND;
            end
            SEND: begin
                if (baud_clk && counter == 7)
                    nstate = STOP;
            end
            STOP: begin
                if (baud_clk)
                    nstate = IDLE;
            end
            default: begin
                nstate = IDLE;
            end
        endcase
    end

    always @(*) begin
        tx = 1'b1;

        case (state)
            IDLE: begin
                tx = 1'b1;
            end
            START: begin
                tx = 1'b0;
            end
            SEND: begin
                tx = tx_send_buffer[counter];
            end
            STOP: begin
                tx = 1'b1;
            end
            default: begin
                tx = 1'b1;
            end
        endcase
    end

endmodule

module uart_baud_gen #(
    parameter CLK_FREQ  = 50000000,  // 系統時脈頻率 (Hz)
    parameter BAUD_RATE = 9600       // 目標鮑率 (bps)
)(
    input  wire clk,      // 系統時脈輸入
    input  wire rst_n,      // 同步低有效重置
    output wire baud_tick // 每個位元時間點輸出 1 個 clock cycle 寬度的脈衝
);

    // 計算除頻值，先用整數除法即可
    localparam integer DIV = CLK_FREQ / BAUD_RATE;

    // 若需要更精細的調整，可再加上四捨五入或使用分數除頻等機制
    // localparam integer DIV = (CLK_FREQ + (BAUD_RATE/2)) / BAUD_RATE;  // 四捨五入

    // 需要的位寬可依實際除頻值大小配置
    reg [$clog2(DIV)-1:0] counter_reg = 0;

    reg baud_tick_reg = 0;

    always @(posedge clk) begin
        if (!rst_n) begin
            counter_reg   <= 0;
            baud_tick_reg <= 0;
        end else begin
            // 計數器遞增
            if (counter_reg == (DIV - 1)) begin
                counter_reg   <= 0;
                baud_tick_reg <= 1'b1;
            end else begin
                counter_reg   <= counter_reg + 1'b1;
                baud_tick_reg <= 1'b0;
            end
        end
    end

    assign baud_tick = baud_tick_reg;

endmodule

module uart(
    input logic clk,
    input logic rst_n,
    input logic wen,
    input logic [1:0] addr,
    input logic [31:0] wdata,
    output logic tx_pin
);

    logic [7:0] tx_data = 8'h00;
    logic tx_start = 0;
    wire tx_busy;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            tx_data  <= 8'h00;
            tx_start <= 1'b0;
        end else begin
            tx_data  <= tx_data;
            tx_start <= 1'b0; // 預設每個 cycle 關閉
            // 如果地址是 0，且有 write enable，就把 wdata[7:0] 寫進去
            if (wen && addr == 2'd0 && !tx_busy) begin
                tx_data  <= wdata[7:0];
                tx_start <= 1'b1; // 觸發一次傳送
            end
        end
    end

    logic baud_clk;
    uart_baud_gen uart_baud_gen_0(
        .clk(clk),
        .rst_n(rst_n),
        .baud_tick(baud_clk)
    );

    uart_tx uart_tx_0(
        .clk(clk),
        .rst_n(rst_n),
        .start(tx_start),
        .data(tx_data),
        .baud_clk(baud_clk),
        .tx(tx_pin),
        .tx_busy(tx_busy)
    );

endmodule
