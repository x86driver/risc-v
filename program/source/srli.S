_start:
    # 測試1: 基本 srli
    addi x1, x0, 8               # x1 = 8
    srli x2, x1, 2               # x2 = 2

    # 測試2: shamt = 0 應保持原值
    lui  x3, 0x12345             # x3 = 0x12345000
    addi x3, x3, 0x678           # x3 = 0x12345678
    srli x4, x3, 0               # x4 = 0x12345678

    # 測試3: 負值（MSB=1）的邏輯右移（零填充）
    lui  x5, 0x80000             # x5 = 0x80000000
    srli x6, x5, 1               # x6 = 0x40000000
    srli x7, x5, 31              # x7 = 0x00000001

    # 測試4: 全 1 模式（區分 SRLI 與 SRAI）
    addi x8, x0, -1              # x8 = 0xFFFFFFFF
    srli x9,  x8, 1              # x9  = 0x7FFFFFFF
    srli x10, x8, 31             # x10 = 0x00000001

    # 測試5: 源為 0（任意 shamt 皆為 0）
    addi x11, x0, 0              # x11 = 0
    srli x12, x11, 17            # x12 = 0

    # 測試6: 大型 pattern 右移 4 位（零填充）
    lui  x13, 0xF0F0F            # x13 = 0xF0F0F000
    addi x13, x13, 0x0F0         # x13 = 0xF0F0F0F0
    srli x14, x13, 4             # x14 = 0x0F0F0F0F

    # 測試7: RD==RS1 自身連續右移（前遞/危害）
    lui  x15, 0x80000            # x15 = 0x80000000
    addi x15, x15, 1             # x15 = 0x80000001
    srli x15, x15, 1             # x15 = 0x40000000
    srli x15, x15, 1             # x15 = 0x20000000
    srli x15, x15, 28            # x15 = 0x00000002

    # 測試8: 連續相依（前遞）
    addi x16, x0, 0x80           # x16 = 0x00000080
    srli x17, x16, 4             # x17 = 0x00000008
    srli x18, x17, 1             # x18 = 0x00000004

    # 測試9: 寫 x0（不應有提交事件）
    srli x0, x18, 3              # x0 仍為 0

    # 測試10: shamt = 30 與 31 邊界（0x80000000）
    lui  x19, 0x80000            # x19 = 0x80000000
    srli x20, x19, 30            # x20 = 0x00000002
    srli x21, x19, 31            # x21 = 0x00000001

    # 測試11: rs1 = x0，shamt=0（仍寫回 0）
    srli x22, x0, 0              # x22 = 0

    # 測試12: 小值右移至 0
    addi x23, x0, 1              # x23 = 1
    srli x24, x23, 31            # x24 = 0

    # 測試13: 高位截斷（0xF000000F >> 4 = 0x0F000000）
    lui  x25, 0xF0000            # x25 = 0xF0000000
    addi x25, x25, 0x00F         # x25 = 0xF000000F
    srli x26, x25, 4             # x26 = 0x0F000000

end:
    jal x0, end