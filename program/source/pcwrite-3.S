_start:
    # pcwrite-3: PCWrite/flush/stall 交錯 corner-case 測試
    # 目標：盡量覆蓋「PCWrite_final override stall」、「hazard_stall bubble 必須是 NOP」等情境。

    # 通用設定
    addi x31, x0, 0            # pass counter
    addi x10, x0, 256          # base = 0x100
    addi x12, x0, 1            # data = 1
    sw   x12, 0(x10)           # [0x100] = 1

    # ------------------------------------------------------------
    # Case 1: lw -> beq (load-use hazard)
    # 正確：beq 使用載入後的 x4=1，不應 taken。
    # 若 bubble 沒真的變 NOP，beq 可能提早在 EX 用舊 x4=0 而誤 taken。
    # ------------------------------------------------------------
    addi x4, x0, 0
    lw   x4, 0(x10)
    beq  x4, x0, C1_fail
    addi x31, x31, 1           # PASS1
    jal  x0, C1_end
C1_fail:
    addi x3, x0, -1            # FAIL marker (should never commit)
C1_end:

    # ------------------------------------------------------------
    # Case 2: mem_stall (lw in MEM) 併發「無條件 beq taken」
    # 讓 branch 在 EX 時，older lw 正在 MEM 造成 mem_stall；
    # 檢查 PCWrite_final override stall 時，仍能正確跳到目標且不走錯路徑。
    # ------------------------------------------------------------
    lw   x5, 0(x10)            # x5 <- 1 (mem_stall)
    beq  x0, x0, C2_tgt        # unconditional taken
    addi x3, x0, -2            # wrong path (should never commit)
C2_tgt:
    addi x31, x31, 1           # PASS2

    # ------------------------------------------------------------
    # Case 3: mem_stall (lw in MEM) 併發 jal (rd!=0)
    # jal 在 EX 期間遇到 older lw 的 mem_stall，PCWrite_final 會 override stall。
    # 需同時確認：
    # - 錯路徑不提交
    # - jal link (x7) 仍會正確寫回（之後再 +1）
    # ------------------------------------------------------------
    lw   x6, 0(x10)
    jal  x7, C3_tgt
    addi x3, x0, -3            # wrong path (should never commit)
C3_tgt:
    addi x7, x7, 1             # use link
    addi x31, x31, 1           # PASS3

    # ------------------------------------------------------------
    # Case 4: mem_stall (sw in MEM) 併發 jalr (rd!=0)
    # 模擬 store multi-cycle stall 時，jalr 在 EX 做 redirect。
    # ------------------------------------------------------------
    sw   x12, 4(x10)
    lui  x8, %hi(C4_tgt)
    addi x8, x8, %lo(C4_tgt)
    jalr x9, x8, 0             # write link to x9
    addi x3, x0, -4            # wrong path (should never commit)
C4_tgt:
    addi x9, x9, 1             # use link
    addi x31, x31, 1           # PASS4

    # ------------------------------------------------------------
    # Case 5: 目標位址由 data memory 提供：sw(label) -> lw -> jalr x0
    # 覆蓋：store stall + load stall + load-use hazard + jalr redirect。
    # ------------------------------------------------------------
    lui  x11, %hi(C5_tgt)
    addi x11, x11, %lo(C5_tgt)
    sw   x11, 8(x10)
    lw   x13, 8(x10)
    jalr x0, x13, 0
    addi x3, x0, -5            # wrong path (should never commit)
C5_tgt:
    addi x31, x31, 1           # PASS5

    # ------------------------------------------------------------
    # Case 6: back-to-back redirect，放大 if_stall 與 flush/PCWrite 交錯機率
    # ------------------------------------------------------------
    beq  x0, x0, C6_l1
    addi x3, x0, -6            # wrong path
C6_l1:
    jal  x0, C6_l2
    addi x3, x0, -7            # wrong path
C6_l2:
    addi x31, x31, 1           # PASS6

    # 最終：把 pass counter 搬到 x5，方便觀察（x5 應為 6）
    addi x5, x31, 0

end:
    jal x0, end
