_start:
    # 測試1: 基本 slli
    addi x1, x0, 1               # x1 = 1
    slli x2, x1, 2               # x2 = 4

    # 測試2: shamt = 0 應保持原值
    lui  x3, 0x12345             # x3 = 0x12345000
    addi x3, x3, 0x678           # x3 = 0x12345678
    slli x4, x3, 0               # x4 = 0x12345678

    # 測試3: shamt = 31 邊界（最低位搬到最高位）
    addi x5, x0, 1               # x5 = 1
    slli x6, x5, 31              # x6 = 0x80000000

    # 測試4: shamt = 31 與多位元來源
    addi x7, x0, 3               # x7 = 3
    slli x8, x7, 31              # x8 = 0x80000000

    # 測試5: 源為 0（任意 shamt 皆為 0）
    addi x9, x0, 0               # x9 = 0
    slli x10, x9, 17             # x10 = 0

    # 測試6: 大型 pattern 左移 8 位
    lui  x11, 0x00ff0            # x11 = 0x00ff0000
    addi x11, x11, 0x0ff         # x11 = 0x00ff00ff
    slli x12, x11, 8             # x12 = 0xff00ff00

    # 測試7: RD==RS1 自身累積（WAW + 前遞）
    addi x13, x0, 1              # x13 = 1
    slli x13, x13, 3             # x13 = 8

    # 測試8: 連續相依（前遞）
    addi x14, x0, 1              # x14 = 1
    slli x15, x14, 4             # x15 = 16
    slli x16, x15, 2             # x16 = 64

    # 測試9: 寫 x0（不應有提交事件）
    slli x0, x16, 3              # x0 仍為 0，驗證忽略寫回

    # 測試10: 同一目的暫存器多次覆蓋（WAW 序列）
    addi x20, x0, 1              # x20 = 1
    slli x20, x20, 1             # x20 = 2
    slli x20, x20, 4             # x20 = 32
    slli x20, x20, 0             # x20 = 32（shamt=0）
    slli x20, x20, 31            # x20 = 0

    # 測試11: 最高位為 1 的來源（負值形態）
    lui  x21, 0x80000            # x21 = 0x80000000
    addi x21, x21, 1             # x21 = 0x80000001
    slli x22, x21, 1             # x22 = 0x00000002

    # 測試12: shamt = 30 與 31 的邊界差異（2 << 30 與 2 << 31）
    addi x23, x0, 2              # x23 = 2
    slli x24, x23, 30            # x24 = 0x80000000
    slli x25, x23, 31            # x25 = 0x00000000

    # 測試13: rs1 為 x0，shamt=0（仍寫回 0）
    slli x26, x0, 0              # x26 = 0

    # 測試14: 末位為 1 的高位樣式，左移 31 -> 0x80000000
    lui  x27, 0xF00F0            # x27 = 0xF00F0000
    addi x27, x27, 0x0F1         # x27 = 0xF00F00F1（LSB=1）
    slli x28, x27, 31            # x28 = 0x80000000

end:
    jal x0, end