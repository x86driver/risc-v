_start:
    addi x1, x0, 1          # 基本資料 (1)
    addi x2, x0, 2          # 基本位移 (2)
    srl  x3, x1, x2         # 1 >> 2 = 0

    # 一般資料右移（0x655 >> 2）
    addi x4, x0, 0x655      # 0x00000655
    srl  x5, x4, x2         # 0x00000195

    # 大位移資料（0x7FF00000 >> 20 = 0x7FF）
    lui  x6, 0x7FF00        # 0x7FF00000
    addi x7, x0, 0x14       # 20
    srl  x8, x6, x7         # 0x000007FF

    # 位移 0（rs2 = x0）
    srl  x9,  x8,  x0       # 應等於 x8

    # rs1 = x0（輸出為 0）
    srl  x10, x0,  x1       # 0 >> 1 = 0

    # 超界位移：僅取 rs2[4:0]
    addi x11, x0, 32        # 32 -> 0
    srl  x12, x1,  x11      # 1 >> 0 = 1
    addi x13, x0, 63        # 63 -> 31
    srl  x14, x1,  x13      # 1 >> 31 = 0

    # 目的與來源相同（連續右移，測 forwarding/hazard）
    lui  x15, 0xF0000       # 0xF0000000
    addi x16, x0, 1         # shamt = 1
    srl  x15, x15, x16      # 0x78000000
    srl  x15, x15, x16      # 0x3C000000
    srl  x15, x15, x16      # 0x1E000000
    srl  x17, x1,  x15      # 1 >> (x15[4:0]=0) = 1

    # 高位截斷：0xF000000F >> 4 = 0x0F000000
    lui  x18, 0xF0000       # 0xF0000000
    addi x18, x18, 0x00F    # 0xF000000F
    addi x19, x0, 4
    srl  x20, x18, x19      # 0x0F000000

    # 31 位移邊界（含先建 0x7FFFFFFF）
    lui  x21, 0x80000       # 0x80000000
    addi x21, x21, -1       # 0x7FFFFFFF
    addi x22, x0, 31
    srl  x23, x21, x22      # 0x00000001

    # rs2 為 -1（底 5 bits 全 1 -> 31）
    addi x24, x0, -1        # 0xFFFFFFFF
    srl  x25, x1,  x24      # 1 >> 31 = 0

    # 邊界負數右移：0x80000000 >> 31，SRL=0x00000001（SRA 會得到 0xFFFFFFFF）
    lui  x26, 0x80000       # 0x80000000
    addi x27, x0, 31
    srl  x28, x26, x27      # 0x00000001

    # 寫回 x0（不應產生 commit）
    srl  x0,  x1,  x2

end:
    jal x0, end