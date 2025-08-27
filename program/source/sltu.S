_start:
    addi x1, x0, -1          # x1 = 0xFFFFFFFF (unsigned large)
    addi x2, x0, 1           # x2 = 0x00000001
    sltu x3, x1, x2          # 0xFFFFFFFF < 0x00000001 -> 0

    # 反向比較（小 vs 大，無號）
    sltu x4, x2, x1          # 0x00000001 < 0xFFFFFFFF -> 1

    # 相等比較
    addi x5, x0, 5
    sltu x6, x5, x5          # 5 < 5 -> 0

    # 與 0 比較（無號）
    sltu x7, x0, x2          # 0 < 1 -> 1
    sltu x8, x2, x0          # 1 < 0 -> 0
    sltu x9, x0, x0          # 0 < 0 -> 0

    # 將負數視為大數的無號比較
    addi x10, x0, -2         # x10 = 0xFFFFFFFE
    sltu x11, x10, x1        # 0xFFFFFFFE < 0xFFFFFFFF -> 1
    sltu x12, x1,  x10       # 0xFFFFFFFF < 0xFFFFFFFE -> 0

    # 邊界值：INT_MIN 與 INT_MAX 的無號關係
    lui  x13, 0x80000        # x13 = 0x80000000 (INT_MIN)
    addi x14, x13, -1        # x14 = 0x7FFFFFFF (INT_MAX)
    sltu x16, x13, x14       # 0x80000000 < 0x7FFFFFFF -> 0
    sltu x17, x14, x13       # 0x7FFFFFFF < 0x80000000 -> 1
    sltu x18, x13, x1        # 0x80000000 < 0xFFFFFFFF -> 1
    sltu x19, x14, x1        # 0x7FFFFFFF < 0xFFFFFFFF -> 1
    sltu x20, x1,  x14       # 0xFFFFFFFF < 0x7FFFFFFF -> 0
    sltu x21, x13, x13       # equal -> 0
    sltu x22, x14, x14       # equal -> 0

    # 寫回 x0（不應產生 commit）
    sltu x0,  x1,  x2

    # 前饋/資料相依測試（多次寫回、連續依賴）
    sltu x23, x1,  x2        # 0
    sltu x24, x23, x2        # 0 < 1 -> 1
    sltu x25, x24, x23       # 1 < 0 -> 0
    sltu x26, x1,  x2        # 0
    sltu x26, x26, x1        # 0 < 0xFFFFFFFF -> 1

    # 更多邊界：INT_MIN 與 0、-1 與 0（無號）
    sltu x27, x13, x0        # 0x80000000 < 0x00000000 -> 0
    sltu x28, x1,  x0        # 0xFFFFFFFF < 0x00000000 -> 0

end:
    jal x0, end
