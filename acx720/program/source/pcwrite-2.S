_start:
    # 高壓力控制/停等交錯測試（pcwrite-2）
    # 通用設定
    addi x10, x0, 256         # base = 0x100（資料區）

    # -------------------------------
    # Case A: lw -> addi -> jalr x0 目標位址源自記憶體（需 hazard/前遞）
    # -------------------------------
    lui  x6, %hi(T1)
    sw   x6, 0(x10)           # 先寫入目標位址的 hi 20 bits
    lw   x5, 0(x10)           # 取出 hi，與 addi %lo 組合成完整目標
    addi x5, x5, %lo(T1)
    jalr x0, x5, 0            # 以記憶體值做為跳轉目標
    addi x3, x0, -1           # 錯路徑（不應提交）
T1:
    addi x1, x0, 101          # 提交：x1 = 101 (0x65)

    # -------------------------------
    # Case B: lw-use hazard + beq 立即使用（taken）
    # -------------------------------
    addi x2, x0, 0x123
    sw   x2, 4(x10)
    lw   x6, 4(x10)
    beq  x6, x2, B_ok
    addi x3, x0, -2           # 錯路徑（不應提交）
B_ok:
    addi x4, x0, 68           # 提交：x4 = 68 (0x44)

    # -------------------------------
    # Case C: jal 寫回鏈結暫存器 + flush 錯路徑
    # -------------------------------
    jal  x7, C_after
    addi x3, x0, -3           # 錯路徑（不應提交）
C_after:
    addi x7, x7, 1            # 提交：x7 會先寫入 PC+4，再加 1

    # -------------------------------
    # Case D: 分支條件由前面結果組合而成並立即比較（前遞/或經過 WB）
    # x1=101, x4=68 → x20=169；與 x24=169 比較，taken
    # -------------------------------
    add  x20, x1, x4
    addi x24, x0, 169
    beq  x20, x24, D_ok
    addi x3, x0, -4           # 錯路徑（不應提交）
D_ok:
    addi x22, x0, 22          # 提交：x22 = 22

    # -------------------------------
    # Case E: mem_stall 與 not-taken 後緊接 taken，觀察 flush/freeze 協同
    # -------------------------------
    sw   x2, 8(x10)
    beq  x1, x3, E_wrong      # not taken
    addi x21, x0, 21          # 提交：x21 = 21
    beq  x0, x0, E_ok         # taken
E_wrong:
    addi x3, x0, -5           # 錯路徑（不應提交）
E_ok:
    addi x23, x0, 23          # 提交：x23 = 23

end:
    jal x0, end


