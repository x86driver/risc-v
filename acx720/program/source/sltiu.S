_start:

    # 測試1: 基本正數比較（5 < 10 -> 1）
    addi x1, x0, 5               # x1 = 5
    sltiu x2, x1, 10             # x2 = 1

    # 測試2: 負數 vs 正數（-5 < 2 -> 0，因為無號比較 0xFFFFFFFB > 2）
    addi x3, x0, -5              # x3 = -5 (0xFFFFFFFB)
    sltiu x4, x3, 2              # x4 = 0

    # 測試3: 正數 vs 負立即數（7 < -3(0xFFFFFFFD) -> 1）
    addi x5, x0, 7               # x5 = 7
    sltiu x6, x5, -3             # x6 = 1

    # 測試4: 相等（9 < 9 -> 0）
    addi x7, x0, 9               # x7 = 9
    sltiu x8, x7, 9              # x8 = 0

    # 測試5: 零與零（0 < 0 -> 0）
    addi x9, x0, 0               # x9 = 0
    sltiu x10, x9, 0             # x10 = 0

    # 測試6: 零與 -1（0 < 0xFFFFFFFF -> 1）
    addi x11, x0, 0              # x11 = 0
    sltiu x12, x11, -1           # x12 = 1

    # 測試7: 零與正數（0 < 1 -> 1）
    addi x13, x0, 0              # x13 = 0
    sltiu x14, x13, 1            # x14 = 1

    # 測試8: INT_MIN 與 0（0x80000000 < 0 -> 0，無號）
    lui  x15, 0x80000            # x15 = 0x80000000 (INT_MIN)
    sltiu x16, x15, 0            # x16 = 0

    # 構造 INT_MAX 並測邊界立即數
    addi x17, x15, -1            # x17 = 0x7FFFFFFF (INT_MAX)
    sltiu x18, x17, -2048        # 0x7FFFFFFF < 0xFFFFF800 -> 1
    sltiu x19, x15, -2048        # 0x80000000 < 0xFFFFF800 -> 1
    sltiu x20, x17, 2047         # 0x7FFFFFFF < 2047 -> 0

    # 測試9: -1 與邊界 2047/-2048（區分 slti 與 sltiu）
    addi x21, x0, -1             # x21 = 0xFFFFFFFF
    sltiu x22, x21, 2047         # 0xFFFFFFFF < 2047 -> 0
    sltiu x23, x21, -2048        # 0xFFFFFFFF < 0xFFFFF800 -> 0

    # 測試10: 立即數符號擴展（-1366）
    addi x24, x0, 0x555          # x24 = 1365
    sltiu x25, x24, -1366        # 1365 < 0xFFFFFAAA -> 1
    addi x26, x0, -1366          # x26 = -1366 (0xFFFFFAAA)
    sltiu x27, x26, -1366        # -1366 < -1366 -> 0
    addi x28, x0, -1367          # x28 = -1367 (0xFFFFFAA9)
    sltiu x29, x28, -1366        # -1367 < -1366 -> 1（無號：0xFFFFFAA9 < 0xFFFFFAAA）

    # 測試11: RD==RS1 hazard 連續寫入
    addi x30, x0, -1             # x30 = 0xFFFFFFFF
    sltiu x30, x30, 0            # x30 = 0
    sltiu x30, x30, -1           # x30 = 1
    sltiu x30, x30, 1            # x30 = 0

    # 測試12: 寫 x0（不應產生提交事件）
    sltiu x0, x17, 0

    # 測試13: 負立即數門檻附近：rs1=0xFFFFF900 與 -2048(0xFFFFF800)
    lui  x31, 0xFFFFF            # x31 = 0xFFFFF000
    addi x31, x31, 0x700         # x31 = 0xFFFFF700
    addi x31, x31, 0x200         # x31 = 0xFFFFF900
    sltiu x2,  x31, -2048        # 0xFFFFF900 < 0xFFFFF800 -> 0

end:
    jal x0, end