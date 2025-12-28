_start:
    addi x1, x0, 1          # 基本資料 (1)
    addi x2, x0, 2          # 基本位移 (2)
    sll x3, x1, x2          # 1 << 2 = 4

    # 大位移資料 (0x7FF << 20)
    addi x4, x0, 0x7FF      # 0x000007FF
    addi x5, x0, 0x14       # 20
    sll x6, x4, x5          # 0x7FF00000

    # 位移 0（rs2 = x0）
    sll x7, x6, x0          # 應等於 x6

    # rs1 = x0（輸出為 0）
    sll x8, x0, x1          # 0 << 1 = 0

    # 超界位移：僅取 rs2[4:0]
    addi x9,  x0, 32        # 32 -> 0
    sll  x10, x1, x9        # 1 << 0 = 1
    addi x11, x0, 63        # 63 -> 31
    sll  x12, x1, x11       # 1 << 31 = 0x80000000

    # 目的與來源相同（連續左移，測 forwarding/hazard）
    addi x13, x0, 3         # 3
    addi x14, x0, 1         # shamt = 1
    sll  x13, x13, x14      # 6
    sll  x13, x13, x14      # 12
    sll  x13, x13, x14      # 24
    sll  x15, x1,  x13      # 1 << 24 = 0x01000000

    # 高位溢出截斷：0xF000000F << 4 = 0x000000F0
    lui  x16, 0xF0000       # 0xF0000000
    addi x16, x16, 0x00F    # 0xF000000F
    addi x17, x0, 4
    sll  x18, x16, x17      # 0x000000F0

    # 31 位移邊界（含先建 0x7FFFFFFF）
    lui  x19, 0x80000       # 0x80000000
    addi x19, x19, -1       # 0x7FFFFFFF
    addi x20, x0, 31
    sll  x21, x19, x20      # 0x80000000

    # rs2 為 -1（底 5 bits 全 1 -> 31）
    addi x22, x0, -1        # 0xFFFFFFFF
    sll  x23, x1,  x22      # 1 << 31 = 0x80000000

    # 寫回 x0（不應產生 commit）
    sll  x0,  x1,  x2

end:
    jal x0, end
