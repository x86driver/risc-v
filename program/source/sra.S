_start:
    addi x1, x0, 1          # 基本資料 (1)
    addi x2, x0, 2          # 基本位移 (2)
    sra  x3, x1, x2         # 1 >> 2(arith) = 0

    # 負數右移（帶符號擴展）
    addi x4, x0, -16        # 0xFFFFFFF0
    sra  x5, x4, x2         # 0xFFFFFFF0 >> 2 = 0xFFFFFFFC

    # srl vs sra 差異（-1 >> 1）
    addi x6, x0, -1         # 0xFFFFFFFF
    addi x7, x0, 1          # shamt = 1
    sra  x8, x6, x7         # 0xFFFFFFFF
    srl  x9, x6, x7         # 0x7FFFFFFF

    # 位移 0（rs2 = x0）
    sra  x10, x5, x0        # 應等於 x5
    srl  x11, x5, x0        # 同上

    # 31 位移邊界，以及與 SRL 的差異（0x80000000 >> 31）
    lui  x12, 0x80000       # 0x80000000
    addi x13, x0, 31
    sra  x14, x12, x13      # 0xFFFFFFFF
    srl  x15, x12, x13      # 0x00000001

    # 超界位移只取低 5 位（32 -> 0；63 -> 31）
    addi x16, x0, 32
    sra  x17, x1,  x16      # 1 >> 0 = 1
    addi x18, x0, 63
    sra  x19, x1,  x18      # 1 >> 31 = 0

    # 目的與來源相同（連續帶符號右移，測 forwarding/hazard）
    lui  x20, 0xF0000       # 0xF0000000
    addi x21, x0, 1         # shamt = 1
    sra  x20, x20, x21      # 0xF8000000
    sra  x20, x20, x21      # 0xFC000000
    sra  x20, x20, x21      # 0xFE000000
    sra  x22, x1,  x20      # x20[4:0]=0 -> 1 >> 0 = 1

    # 負數與一般資料混合（0x80000001 >> 4），對照 SRL
    lui  x23, 0x80000       # 0x80000000
    addi x23, x23, 1        # 0x80000001
    addi x24, x0, 4
    sra  x25, x23, x24      # 0xF8000000
    srl  x26, x23, x24      # 0x08000000

    # rs1 = x0（0 >> 1 = 0）
    sra  x27, x0,  x7

    # 寫回 x0（不應產生 commit）
    sra  x0,  x1,  x7

end:
    jal x0, end