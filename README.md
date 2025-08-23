要做的:
- [x] 讀寫 ram 的位址需要對齊 128 bits 嗎？ (好像是)
- [x] wraddr, araddr 要修正

現在讀寫 leds 模擬看起來正確 要放在板子上試試
還要跑原本 ddr3 的讀寫測試 因為改了 address_decoder 的邏輯
uart 可能也要跑

用這種方式產生的 可以得到正確的 auipc 位址
```bash
riscv64-linux-gnu-gcc -march=rv32i -mabi=ilp32 -nostdlib -fno-pic -g -o lw.o lw.S
```

objdump 這樣下才可以得到 jalr
```bash
riscv64-linux-gnu-objdump -D -M no-aliases a | less
```

auipc 要做的:
- [x] 實作指令
- [ ] 搬移 PC (包含 instruction memory)

0ecaffc43ce1bb6ee854de56fe76a1e3e042152a
測試是正確: 分開測試EX/MEM hazard、MEM/WB hazard 與 load-use hazar


uart 目前測試是 write_done 只會有一拍 看起來是正確的

接下來要做的:
- [ ] 把 uart/led 搬到更高的 address
- [ ] 在板子上測試 ddr3/uart/led
- [ ] 實作 jal 指令
- [ ] 把 ddr3_ram.sv 的 clk 拿掉, 直接傳 clk_50 進去

- [ ] instruction memory 要換成 ddr3

現在的問題:
1. READ_ADDR 可能"剛好"讀到 mem_alu_out (但此時其實是 IF 正在讀)
2. wb_RegWrite 永遠是 0, 流水線卡住
3. pc_current 只讀到一次指令, 之後一直都是 4
4. 一直反覆出現 mem read, 位址是 0x8

arbiter:
1. 現在分兩塊記憶體, 目前只有第一個 lw 能執行
2. 即使下一條是 addi 的指令也沒有被執行
3. if_stall 和 mem_stall 應該同時只能有一個為 1, 否則?
4. 乾脆不管是 if_stall 或 mem_stall 都停掉整個流水線
5. 反正後面就算先做, 也快不了多少, 而且先做的話還會碰到若後面也要做 memory read 會跟 instruction read 搶
6. 多測試一些指令, 若沒問題就可以把 instruction memory 結合 data memory 了
7. 連續五個 lw 也是正確的

原本分兩塊記憶體能動, 可能只是 1769500 ns 那邊, 雖然 if_pc_read_data_valid == 1, if_stall == 0,
但流水線都沒有動, 所以這時候應該要寫入 

03/30
現在把 arbiter 整合進 data memory multicycle, 但會遇到：
mem_stall = 0, 但 if_stall = 1 結果流水線就停住
但為什麼分成兩塊記憶體就沒事？
目前分成兩塊 要再複製一個 data_memory_multicycle 因為目前已經把 arbiter 整合進去了
要做一個把 arbiter 拿掉的版本 才能測試兩塊記憶體
其實分成兩塊也是錯的, 因為會一直跑到 if_stall == 0 && mem_stall == 0 才會繼續

3/31
可能的問題：
mem_stall == 0 && if_stall == 1 該如何處理？現在看起來流水線都不會動了

04/06
加上 mux_id_MemRead 就解決了 因為流水線會重複讀取記憶體是因為沒有清空 MemRead
導致 MemRead 永遠都是 1
接下來可以測其他指令
write_done 好像都收不到 = 1

04/08
要研究 pc_branch_sel == 1, 這時若不理 stall 而直接讓 pc 跳走, 會發生什麼事？
跟 chatgpt 的聊天連結: PC Branch Hazard Fix

04/09
uart rx with interrupt 可以正確執行

04/10
hazard 測試 ok

08/17
可能要回退到兩塊記憶體的地方, 然後把測試程式搬進去
old-risc-v 目前可參考這份 
然後只保留 mux_id_MemRead 相關的 其他不需要
可以問 AI 我這樣改 mux_id_MemRead 對嗎？
好像先不用了, 直接 copy old-risc-v 那份

08/21
已經把所有舊檔案都 copy 回來了
接下來試試從 1 加到 10
要加回去 readmemh

08/23
為什麼其他跳轉指令不需要特別處理
1. BNE/BEQ 條件分支指令
RegWrite = 0 - 不寫回任何暫存器
Branch = 1 - 會觸發分支檢測
無衝突：即使被 flush 也沒關係，因為它們不需要寫回
2. AUIPC 指令
RegWrite = 1 - 需要寫回暫存器
Branch = 0 - 不會觸發分支檢測和 flush
無衝突：不會 flush 自己
3. JAL 指令（問題所在）
RegWrite = 1 - 需要寫回暫存器（返回地址）
Branch = 1 - 會觸發分支檢測和 flush
衝突：會 flush 自己的 RegWrite 信號！
4. 其他可能的跳轉指令（如 JALR）
如果將來實現 JALR 指令，它也會有同樣的問題，因為：
RegWrite = 1 - 需要寫回返回地址
Branch = 1 - 需要跳轉
所以我們的修復方案實際上是通用的：任何需要寫回暫存器的跳轉指令都不應該在同一週期 flush 自己。


```systemverilog
module memory_arbiter(
    input  logic clk,
    input  logic rst_n,

    input  logic if_pc_MemRead,
    input  logic [31:0] if_pc_address,
    output logic if_pc_read_data_valid,
    output logic [31:0] if_inst,

    input  logic mem_data_MemRead,
    input  logic [31:0] mem_data_address,
    output logic mem_data_read_data_valid,
    output logic [31:0] mem_data_rdata,

    output logic arbiter_MemRead,
    output logic [31:0] arbiter_address,
    input  logic arbiter_read_valid,
    input  logic [31:0] arbiter_rdata,

    output logic arbiter_if_pc_MemRead,
    output logic arbiter_mem_data_MemRead
);

    typedef enum logic [1:0] {
        IDLE = 2'd0,
        IF_READ = 2'd1,
        MEM_READ = 2'd2
    } state_t;

    state_t state = IDLE;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            arbiter_MemRead <= 0;
            arbiter_address <= 32'hxxxx_xxxx;
            if_pc_read_data_valid <= 0;
            mem_data_read_data_valid <= 0;
            arbiter_if_pc_MemRead <= 1;
            arbiter_mem_data_MemRead <= 0;
        end else begin
            arbiter_MemRead <= 0;
            if_pc_read_data_valid <= 0;
            mem_data_read_data_valid <= 0;
            if_inst <= if_inst;
            mem_data_rdata <= mem_data_rdata;
            arbiter_if_pc_MemRead <= 1;
            arbiter_mem_data_MemRead <= 0;

            case (state)
                IDLE: begin
                    if (mem_data_MemRead) begin
                        arbiter_MemRead <= 1;
                        arbiter_address <= mem_data_address;
                        arbiter_mem_data_MemRead <= 1;
                        state <= MEM_READ;
                    end else if (if_pc_MemRead) begin
                        arbiter_MemRead <= 1;
                        arbiter_address <= if_pc_address;
                        arbiter_if_pc_MemRead <= 1;
                        state <= IF_READ;
                    end
                end

                IF_READ: begin
                    if (arbiter_read_valid) begin
                        if_pc_read_data_valid <= 1;
                        if_inst <= arbiter_rdata;
                        arbiter_if_pc_MemRead <= 0;
                        state <= IDLE;
                    end else begin
                        arbiter_MemRead <= 1;
                        arbiter_address <= if_pc_address;
                        arbiter_if_pc_MemRead <= 1;
                    end
                end

                MEM_READ: begin
                    if (arbiter_read_valid) begin
                        mem_data_read_data_valid <= 1;
                        mem_data_rdata <= arbiter_rdata;
                        arbiter_mem_data_MemRead <= 0;
                        state <= IDLE;
                    end else begin
                        arbiter_MemRead <= 1;
                        arbiter_address <= mem_data_address;
                        arbiter_mem_data_MemRead <= 1;
                    end
                end
            endcase
        end
    end

endmodule

module data_memory_singlecycle(
    input logic clk,
    input logic rst_n,

    input  logic if_pc_MemRead,
    input  logic [31:0] if_pc_address,
    output logic if_pc_read_data_valid,
    output logic [31:0] if_inst,

    input  logic mem_data_MemRead,
    input  logic [31:0] mem_data_address,
    output logic mem_data_read_data_valid,
    output logic [31:0] mem_data_rdata,

    input logic MemWrite,
    input logic [31:0] write_address,
    input logic [31:0] write_data,
    output logic write_done,
    input logic init_calib_complete
);

    localparam INST_COUNT = 6;
    logic [31:0] mem [INST_COUNT] = {
        32'h0000_2083, // lw	x1,0(x0) # 0 <_start>
        32'h0040_2103, // lw	x2,4(x0) # 4 <_start+0x4>
        32'h0080_2183, // lw	x3,8(x0) # 8 <_start+0x8>
        32'h00c0_2203, // lw	x4,12(x0) # c <_start+0xc>
        32'h0100_2283, // lw	x5,16(x0) # 10 <_start+0x10>
        32'h0092_8313  // addi  x6,x5,9
    };

    always_comb begin
        if (mem_data_MemRead) begin
            if (mem_data_address < 4*INST_COUNT) begin
                mem_data_rdata = mem[mem_data_address[31:2]];
            end else begin
                mem_data_rdata = 32'h0;
            end
            mem_data_read_data_valid = 1;
            if_pc_read_data_valid = 0;
        end else if (if_pc_MemRead) begin
            if (if_pc_address < 4*INST_COUNT) begin
                if_inst = mem[if_pc_address[31:2]];
            end else begin
                if_inst = 32'h0;
            end
            mem_data_read_data_valid = 0;
            if_pc_read_data_valid = 1;
        end else begin
            mem_data_rdata = 32'h0;
            if_inst = 32'h0;
            mem_data_read_data_valid = 0;
            if_pc_read_data_valid = 0;
        end
    end

    // write 暫時先不處理

endmodule


/*
    wire arbiter_MemRead;
    wire [31:0] arbiter_address;
    wire arbiter_read_valid;
    wire [31:0] arbiter_rdata;

    // 給 stall_unit 看的
    wire arbiter_if_pc_MemRead;
    wire arbiter_mem_data_MemRead;

    memory_arbiter memory_arbiter_0(
        .clk(clk),
        .rst_n(rst_n),

        .if_pc_MemRead(1'b1),
        .if_pc_address(pc_current),
        .if_pc_read_data_valid(if_pc_read_data_valid),
        .if_inst(if_inst),

        .mem_data_MemRead(mem_data_MemRead),
        .mem_data_address(mem_alu_out),
        .mem_data_read_data_valid(mem_data_read_data_valid),
        .mem_data_rdata(mem_memory_read_data),

        .arbiter_MemRead(arbiter_MemRead),
        .arbiter_address(arbiter_address),
        .arbiter_read_valid(arbiter_read_valid),
        .arbiter_rdata(arbiter_rdata),

        .arbiter_if_pc_MemRead(arbiter_if_pc_MemRead),
        .arbiter_mem_data_MemRead(arbiter_mem_data_MemRead)
);
*/

/*
    data_memory_singlecycle data_memory_singlecycle0(
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

        .MemWrite(),
        .write_address(),
        .write_data(),
        .write_done(),
        .init_calib_complete(1'b1)
    );
*/

```

產生新測例的 golden 提交序列（若要）：
vvp ./simv +HEX=program/<name>_prog.hex +CASE=<name> +DUMP_EXP=program/<name>.exp

run 8us

```bash
docker run -it -v ~/pro/riscv:/pro/riscv ubuntu:24.04
apt update
apt install gcc-riscv64-linux-gnu less
cd /pro/riscv
riscv64-linux-gnu-gcc -march=rv32i -mabi=ilp32 -g -c -o lw.32 lw.S
riscv64-linux-gnu-objdump -M numeric -S lw.32|less
```

vivado:
~/pro/fpga/xilinx-docker$ ./run.sh
cd /xilinx/
. tools/Xilinx/Vivado/2024.2/settings64.sh
./run.sh