_start:
    addi x1, x0, -1          # -1
    addi x2, x0, 1           # 1
    slt  x3, x1, x2          # -1 < 1 -> 1

    # 反向比較（正 vs 負）
    slt  x4, x2, x1          # 1 < -1 -> 0

    # 相等比較
    addi x5, x0, 5
    slt  x6, x5, x5          # 5 < 5 -> 0

    # 與 0 比較
    slt  x7, x0, x2          # 0 < 1 -> 1
    slt  x8, x2, x0          # 1 < 0 -> 0
    slt  x9, x0, x0          # 0 < 0 -> 0

    # 負數彼此比較
    addi x10, x0, -2         # -2
    slt  x11, x10, x1        # -2 < -1 -> 1
    slt  x12, x1,  x10       # -1 < -2 -> 0

    # 邊界值：INT_MIN 與 INT_MAX
    lui  x13, 0x80000        # 0x80000000 (INT_MIN)
    addi x14, x13, -1        # 0x7FFFFFFF (INT_MAX)
    slt  x16, x13, x14       # INT_MIN < INT_MAX -> 1
    slt  x17, x14, x13       # INT_MAX < INT_MIN -> 0
    slt  x18, x13, x1        # INT_MIN < -1 -> 1
    slt  x19, x14, x1        # INT_MAX < -1 -> 0
    slt  x20, x1,  x14       # -1 < INT_MAX -> 1
    slt  x21, x13, x13       # equal -> 0
    slt  x22, x14, x14       # equal -> 0

    # 寫回 x0（不應產生 commit）
    slt  x0,  x1,  x2

    # 前饋/資料相依測試
    slt  x23, x1,  x2        # 1
    slt  x24, x23, x2        # 1 < 1 -> 0
    slt  x25, x24, x23       # 0 < 1 -> 1
    slt  x26, x1,  x2        # 1
    slt  x26, x26, x1        # 1 < -1 -> 0

    # 更多邊界：INT_MIN 與 0、-1 與 0
    slt  x27, x13, x0        # INT_MIN < 0 -> 1
    slt  x28, x1,  x0        # -1 < 0 -> 1

end:
    jal x0, end
