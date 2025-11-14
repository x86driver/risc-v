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


工作日誌
==========

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

MAX_COMMITS = 1024, 如果之後有更大的測試程式, 這裡要記得改

08/24
==============

下一個可以做的指令：
jalr

可以做的事:
資料存取要 4-byte 對齊

08/29
==============

slli, srli, srai 的 imm[5:11] 應該要檢查是否為合法指令

```verilog
                    if (funct3 == 3'b000) begin // lb
                        read_data <= {{24{mem[address[31:2]][address[1:0]*8+7]}}, mem[address[31:2]][address[1:0]*8+:8]};
                    end else if (funct3 == 3'b001) begin // lh
                        read_data <= {{16{mem[address[31:2]][15]}}, mem[address[31:2]][15:0]};
                    end else if (funct3 == 3'b010) begin // lw
                        read_data <= mem[address[31:2]];
                    end else if (funct3 == 3'b100) begin // lbu
                        read_data <= {{24{1'b0}}, mem[address[31:2]][7:0]};
                    end else if (funct3 == 3'b101) begin // lhu
                        read_data <= {{16{1'b0}}, mem[address[31:2]][15:0]};
                    end else begin
                        read_data <= mem[address[31:2]];
                    end
```

試試看直接輸出 read_data <= mem[1]; 沒效

這樣也ok
    lw   x2, 1(x1)
    lw   x2, 5(x1)
    lw   x2, 9(x1)

別求一步到位

09/16
==============

1. 在模組間的 wire 一定要記得宣告, 否則就算 compile 能過, 他預設只會給你 1 bit 的大小

09/21
==============

ecall 的支援方式：

WB 才做 pc 的決策 並且要覆蓋 pc_branch_sel
Flush 要把 EX, MEM 也 Flush

修改: control_hazard_detection_unit
加入 wb_inst, wb_pc, ex_Flush, mem_Flush

pc_target_branch 直接在模組內判斷

在 control_unit 是否需要拉額外的控制線到 WB?
例如 csr_read, csr_write

或是拉 wb_inst, 然後做一個 csr module, 直接在裡面處理所有 csr 相關指令？
control_unit 只需要 is_Valid = 1;

可是如果要讀 csr 的值出來 然後寫入 reg 要怎麼做？這樣會跟 wb_RegWrite 衝突
mux2to1 mux2to1_memory 可能可以在這裡改成 mux3to1? 其中一路是從 csr 來的？

csr 相關的指令**都有**:
* RegWrite = 1;
* 寫入 csr
* 讀取 csr

ID: 根據 12-bit 讀出 csr (id_read_csr) 並傳給 pipeline, 並且 csr_RegWrite = 1
EX: control_hazard_detection_unit 判斷如果是 ecall 就要根據 ex_read_csr 跳轉
stall_unit 應該不用判斷: load-use hazard
forwarding_unit 要判斷: 只需要一路, 如果上條指令寫入某個 csr, 現在這條指令讀取 csr, 則做 WB->EX
MEM:
WB: mux2to1_memory 加上 csr_RegWrite, 將 wb_read_csr 寫回

```verilog
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
```

09/29
==============

1. 可以寫入 mtvec 了
2. 讀取舊值寫回 reg 也 ok
3. 接下來要做的:

- [x] ecall 00000073 (所以 rd = 0)
- [ ] forwarding (可以先用 nop 測試)

10/12
==============

1. 因為 ecall 執行的時候, x1 已經在 WB 了, 所以測不到 x1 在 MEM 階段的 forwarding

00000097  // auipc	x1,0x0
01808093  // addi	x1,x1,24 # 1c <ex0>
30509173  // csrrw	x2,mtvec,x1
00000073  // ecall

如果改成這樣, 是否可以測 x1 在 MEM 階段的 forwarding?

00000097  // auipc	x1,0x0
01808093  // addi	x1,x1,24 # 1c <ex0>
????????  // addi   x2,x2,FF # 把 WB 的訊號線改成別的內容
30509173  // csrrw	x2,mtvec,x1
00000073  // ecall


2. 接下來要做的:
- [ ] 支援 csrrwi
- [x] csr_control_unit 要多一個訊號, xxx_sel 用來選擇資料是從 reg 讀出來還是把 rs1 當作「值」
- [x] 實作 ex_csr_src_is_zimm 選擇訊號 (可能是 ex_decoded_rs1 和 forwarding 之後的值) 要在 EX 階段選擇
- [x] 把 csr_src_is_zimm 加入流水線
- [x] input: 找出 forwarding 之後的值在哪裡 (mux3to1_alu_a_out)
- [x] output: 找出 forwarding 原本應該餵給誰, (mux3to1 mux3to1_alu_a_operand) 用一條新的訊號取代 (經過 ex_csr_src_is_zimm 選擇後的)
- [x] 改名 csr_src_is_zimm
- [x] cleanup mux2to1_debug

11/13
==============

3. 目前的問題:
- [x] csrrwi x2, mtvec, 0x1c # 這行執行後 還是需要 nop 才能讓 ecall 拿到正確的 mtvec
- [x] 找到問題, 因為 csr_forwarding_unit 實作少了 mem_csr_read_data 所以沒有正確 forward

4. csrrw 有其他問題:
csrrw x2, mtvec, x1 之後:
mem_CsrWrite: 1, mem_csr_read_data: deadbeef, wb_CsrWrite: 0, wb_reg_write_data: 0000001c
因為 x2 在 mem 時會被寫入 deadbeef
但 ecall 應該要讀取 x1 (即將寫入 mtvec 的值, 而不是 forwarding x2 的值)
.mem_csr_read_data(mem_alu_out), 這樣寫才對 因為 mem_alu_out 是 rs1 的值
(就跟 sw 指令的 rs1 是一樣的, csrrw 的 rs1)

5. 下一步加上測試:
- [ ] 連續兩個指令都寫入 csr (第一個指令要寫入錯誤的地址, 第二個寫入正確的, 用來測試 mem forwarding)
- [ ] 把 WB 的訊號線改成別的內容 (詳見上述) 測試 mem forwarding
- [ ] csrrw ecall 中間插一條無關的指令 測試 wb forwarding
- [ ] 測試沒有 forwarding 的情況


11/14
==============

1. 之後要做的
- [ ] 30200073  // mret
- [ ] 目前 forwarding 只有考慮 mtvec
