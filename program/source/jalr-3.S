# JAL/JALR corner-case 精簡測試
# - JALR rd = rs1（同名暫存器 hazard：預期應寫回 link）
# - 亦能觀察 AUIPC 基準點偏移（預期 PC）
# - JALR rd 應該要對齊到 4 的倍數

_start:
    # 極簡：直接進入 G 案例
    auipc x1, 0            # 期望 x1 = 0x00000000
    addi  x1, x1, 12      # 期望 x1 = 0x0000000c
    jalr  x1, x1, 0       # 期望 x1 = 0x0000000c（link）；跳到 G_target（0x0000000c）

G_target:
    addi  x2, x0, 2        # 期望 x2 = 2

    auipc x3, 0
    addi  x3, x3, 19
    jalr  x0, x3, 0
    addi  x5, x0, 5        # bug detect, 不應該執行到這裡

H_target:
    addi  x4, x0, 4

end:
    jal   x0, end            # 無限迴圈結束測試


