
## 待辦清單

### 通用/流程
- [ ] 還要跑原本 DDR3 的讀寫測試（因為改了 address_decoder 的邏輯）
- [ ] UART 可能也要跑（回歸測試）
- [x] 修改 bootrom 的給值方式 跑一次 uart-hello (把 hex 加入專案)

### 記憶體/位址/匯流排
- [x] 讀寫 RAM 的位址需要對齊 128 bits 嗎？（好像是）
- [x] wraddr, araddr 要修正
- [ ] 把 UART/LED 搬到更高的 address
- [ ] 在板子上測試 DDR3/UART/LED
- [ ]（板上）LED 模擬看起來正確，放到板子上試試
- [ ] 把 `ddr3_ram.sv` 的 clk 拿掉，直接傳 clk_50 進去
- [ ] instruction memory 要換成 DDR3
- [x] 連續跑一些指令測試，若沒問題就把 instruction memory 結合 data memory
- [ ]（arbiter 相關）if_stall 和 mem_stall 應該同時只能有一個為 1？需要釐清/修正
- [ ]（arbiter 相關）乾脆不管 if_stall 或 mem_stall 都停掉整個流水線（評估並實作/驗證）
- [ ]（arbiter 相關）多測試一些指令（確認不會因搶記憶體卡死）
- [x]（回退策略）可能要回退到「兩塊記憶體」版本，並把測試程式搬進去
- [ ]（回退策略）只保留 `mux_id_MemRead` 相關，其它先不需要（或直接 copy old-risc-v 那份）
- [x] unified 加回去 `readmemh`
- [x] 資料存取要 4-byte 對齊
- [ ] 目前跑 0x80000000 都是把前面位址截斷

### 指令支援/控制 hazard
- [x] AUIPC：實作指令
- [x] AUIPC：搬移 PC（包含 instruction memory）
- [x] 實作 JAL 指令
- [x] 下一個可以做的指令：JALR
- [ ] 要研究 `pc_branch_sel == 1` 時，若不理 stall 而直接讓 PC 跳走會發生什麼事（control hazard 行為確認）
- [ ] SLLI/SRLI/SRAI 的 imm[5:11] 應該要檢查是否為合法指令（illegal instruction 偵測）
- [x] 實作 mret（`30200073`）
- [x] 要實做 precise exception
- [ ] 做一個專門的 module 來偵測 illegal instruction，再餵給 control_hazard_detection_unit（例如 shamt 測試）

### CSR / Exception / 中斷
- [ ] illegal-csr：mstatus 需要檢查有一些 bit 不能直接寫入
- [x] csr_file 要用 rst_n 初始化
- [ ] 評估 CSR 相關架構：control_unit 拉額外控制線到 WB（如 csr_read/csr_write）或改成獨立 csr module
- [ ] 再挑幾個 riscv-tests 用 Makefile 自動轉檔跑
- [x] 和 spike 做比較
- [x] `+DUMP_EXP` 加上 pc, csr, branch
- [ ] `MAX_COMMITS = 1024`：之後若測試程式更大，記得調大限制
- [ ] `csrrs`, `csrrc` 沒有正確初始化 `mstatus`

### UART
- [ ] 寫一個新的 tb 來模擬 UART 輸出
- [ ] 讓 UART 輸出倒數秒數（先從 1 開始往上數也可）
- [x] 考慮 `ex_csr_mtvec` 是否可移除？ (不行 因為 pc_branch_target 會用到)
- [x] 研究為什麼寫一個字元到 UART 會出現四個 write_done（`uart_stub_iverilog.sv` 卻沒有）

### 測試
- [x] `rv32mi-p-lw-misaligned`
- [ ] verilator 加上 -Wall -Werror-WIDTH
- [x] 讓 xsim 也可以跑 `program/source/*_elf.S`
- [ ] xsim 加上測試: 同一週期 imem, dmem 同時讀寫
- [x] lw/sw 系列的 xsim 都跑不過, 先寫一個簡單的 lw 試試看 (因為目前 imem/dmem 是分開的)

### 已完成
- [x] ecall `00000073`（rd=0）
- [x] forwarding（可以先用 nop 測試）
- [x] 支援 `csrrwi`
- [x] `csr_control_unit` 增加訊號（xxx_sel）：選資料來源是 reg 讀出或把 rs1 當作「值」
- [x] 實作 `ex_csr_src_is_zimm` 選擇訊號（在 EX 階段選）
- [x] 把 `csr_src_is_zimm` 加入流水線
- [x] input：找出 forwarding 之後的值在哪裡（`mux3to1_alu_a_out`）
- [x] output：找出 forwarding 原本應該餵給誰（用新訊號取代 `mux3to1_alu_a_operand`，經過 `ex_csr_src_is_zimm` 選擇後）
- [x] 改名 `csr_src_is_zimm`
- [x] cleanup `mux2to1_debug`
- [x] 安裝 spike
- [x] Vivado 加上指令 BRAM
- [x] data_multicycle 改用 BRAM
- [x] git commit 並刪掉不必要的中介檔
- [x] 直接寫一個 UART 顯示 A-Z
- [x] 試試 synthesis 和 `make test-summary` 能不能共存
- [x] 把 CSR forwarding 移除


### 不做的東西
- [ ] forwarding：目前只考慮 mtvec (暫時不做 csr forwarding)
- [ ] fw unit：釐清/修正「csrr x4, mepc 後接 addi 會被蓋回 4」問題（forwarding 看 x4 或需要 stall）
- [ ] （測試）連續兩個指令都寫 CSR：第一個寫錯誤地址、第二個寫正確，用來測 mem forwarding
- [ ] （測試）把 WB 的訊號線改成別的內容，測 mem forwarding
- [ ] （測試）`csrrw` 和 `ecall` 中間插一條無關指令，測 wb forwarding
- [ ] （測試）測「沒有 forwarding」的情況
