_start:

    # 測試1: 基本正數比較（5 < 10 -> 1）
    addi x1, x0, 5               # x1 = 5
    slti x2, x1, 10              # x2 = 1

    # 測試2: 負數 vs 正數（-5 < 2 -> 1）
    addi x3, x0, -5              # x3 = -5
    slti x4, x3, 2               # x4 = 1

    # 測試3: 正數 vs 負數（7 < -3 -> 0）
    addi x5, x0, 7               # x5 = 7
    slti x6, x5, -3              # x6 = 0

    # 測試4: 相等（9 < 9 -> 0）
    addi x7, x0, 9               # x7 = 9
    slti x8, x7, 9               # x8 = 0

    # 測試5: 零與零（0 < 0 -> 0）
    addi x9, x0, 0               # x9 = 0
    slti x10, x9, 0              # x10 = 0

    # 測試6: 零與負數（0 < -1 -> 0）
    addi x11, x0, 0              # x11 = 0
    slti x12, x11, -1            # x12 = 0

    # 測試7: 零與正數（0 < 1 -> 1）
    addi x13, x0, 0              # x13 = 0
    slti x14, x13, 1             # x14 = 1

    # 測試8: INT_MIN 與 0（INT_MIN < 0 -> 1）
    lui  x15, 0x80000            # x15 = 0x80000000 (INT_MIN)
    slti x16, x15, 0             # x16 = 1

    # 構造 INT_MAX 並測邊界立即數
    addi x17, x15, -1            # x17 = 0x7FFFFFFF (INT_MAX)
    slti x18, x17, -2048         # INT_MAX < -2048 -> 0
    slti x19, x15, -2048         # INT_MIN < -2048 -> 1
    slti x20, x17, 2047          # INT_MAX < 2047 -> 0

    # 測試9: -1 與邊界 2047/-2048
    addi x21, x0, -1             # x21 = -1
    slti x22, x21, 2047          # -1 < 2047 -> 1
    slti x23, x21, -2048         # -1 < -2048 -> 0

    # 測試10: 立即數符號擴展（-1366）
    addi x24, x0, 0x555          # x24 = 1365
    slti x25, x24, -1366         # 1365 < -1366 -> 0
    addi x26, x0, -1366          # x26 = -1366
    slti x27, x26, -1366         # -1366 < -1366 -> 0
    addi x28, x0, -1367          # x28 = -1367
    slti x29, x28, -1366         # -1367 < -1366 -> 1

    # 測試11: RD==RS1 hazard 連續寫入
    addi x30, x0, -1             # x30 = -1
    slti x30, x30, 0             # x30 = 1
    slti x30, x30, -1            # x30 = 0
    slti x30, x30, 1             # x30 = 1

    # 測試12: 寫 x0（不應產生提交事件）
    slti x0, x17, 0

end:
    jal x0, end