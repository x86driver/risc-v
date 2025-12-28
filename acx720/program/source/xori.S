_start:
    # 測試1: 基本 xori 操作
    addi x1, x0, 0x5A5        # x1 = 0x000005A5
    xori x2, x1, 0x0F0        # x2 = 0x5A5 ^ 0x0F0 = 0x00000555

    # 測試2: xori with 0 (應該保持原值)
    addi x3, x0, 0x123        # x3 = 0x00000123
    xori x4, x3, 0            # x4 = 0x123 ^ 0 = 0x00000123

    # 測試3: xori with -1 (0xFFF -> 符號擴展為 0xFFFFFFFF，反轉所有位)
    addi x5, x0, 0x5A5        # x5 = 0x000005A5
    xori x6, x5, -1           # x6 = 0x5A5 ^ 0xFFFFFFFF = 0xFFFFFA5A

    # 測試4: 12-bit 立即數最大正值 (0x7FF)
    addi x7, x0, 0x555        # x7 = 0x00000555
    xori x8, x7, 0x7FF        # x8 = 0x555 ^ 0x7FF = 0x000002AA

    # 測試5: 12-bit 立即數負值 -2048 (0x800 -> 符號擴展為 0xFFFFF800)
    addi x9, x0, 0x7FF        # x9 = 0x000007FF
    xori x10, x9, -2048       # x10 = 0x7FF ^ 0xFFFFF800 = 0xFFFFF7FF

    # 測試6: 產生全零結果
    addi x11, x0, 0x3C3       # x11 = 0x000003C3
    xori x12, x11, 0x3C3      # x12 = 0x3C3 ^ 0x3C3 = 0x00000000

    # 測試7: 測試負數立即數 -256 (0xF00 -> 符號擴展為 0xFFFFFF00)
    addi x13, x0, 0xFF        # x13 = 0x000000FF
    xori x14, x13, -256       # x14 = 0xFF ^ 0xFFFFFF00 = 0xFFFFFEFF

    # 測試8: 測試立即數 -1024 (0xC00 -> 符號擴展為 0xFFFFFC00)
    lui x15, 0x12345          # x15 = 0x12345000
    xori x16, x15, -1024      # x16 = 0x12345000 ^ 0xFFFFFC00 = 0xEDCBAC00

    # 測試9: 對零暫存器做 xori
    xori x17, x0, 0x555       # x17 = 0 ^ 0x555 = 0x00000555

    # 測試10: 測試所有位元
    lui x18, 0xAAAAA          # x18 = 0xAAAAA000
    addi x18, x18, 0x555      # x18 = 0xAAAAA555
    xori x19, x18, 0x0AA      # x19 = 0xAAAAA555 ^ 0x0AA = 0xAAAAA5FF

    # 測試11: 連續 xori (測試資料前遞)
    addi x20, x0, 0x100       # x20 = 0x00000100
    xori x21, x20, 0x0FF      # x21 = 0x100 ^ 0x0FF = 0x000001FF
    xori x22, x21, 0x1FF      # x22 = 0x1FF ^ 0x1FF = 0x00000000

    # 測試12: 測試負數 -17 (0xFEF -> 符號擴展為 0xFFFFFFEF)
    addi x23, x0, 0x0F        # x23 = 0x0000000F
    xori x24, x23, -17        # x24 = 0x0F ^ 0xFFFFFFEF = 0xFFFFFFE0

    # 測試13: 測試交替位模式
    lui x25, 0x55555          # x25 = 0x55555000
    addi x25, x25, 0x555      # x25 = 0x55555555
    xori x26, x25, 0x2AA      # x26 = 0x55555555 ^ 0x2AA = 0x555557FF

    # 測試14: 測試立即數 1365 (0x555)
    lui x27, 0xFFFFF          # x27 = 0xFFFFF000
    xori x28, x27, 0x555      # x28 = 0xFFFFF000 ^ 0x555 = 0xFFFFF555

    # 測試15: 測試負值結果
    addi x29, x0, 1           # x29 = 0x00000001
    xori x30, x29, -2         # x30 = 0x1 ^ 0xFFFFFFFE = 0xFFFFFFFF

    # 測試16: 測試 12-bit 立即數邊界值 0x7FE
    addi x31, x0, 0x001       # x31 = 0x00000001
    xori x1, x31, 0x7FE       # x1 = 0x001 ^ 0x7FE = 0x000007FF

    # 測試17: 測試 -2047 (最小負值+1)
    addi x2, x0, 0x7FE        # x2 = 0x000007FE  
    xori x3, x2, -2047        # x3 = 0x7FE ^ 0xFFFFF801 = 0xFFFFFFFF

    # 測試18: 測試交替位元模式 -1366 (0xAAA 的 12-bit 表示)
    addi x4, x0, 0x555        # x4 = 0x00000555
    xori x5, x4, -1366        # x5 = 0x555 ^ 0xFFFFFAAA = 0xFFFFFFFF

    # 測試19: 測試 xori 連續使用同一暫存器 (hazard 測試)
    addi x6, x0, 0x0F0        # x6 = 0x000000F0
    xori x6, x6, 0x00F        # x6 = 0x0F0 ^ 0x00F = 0x000000FF
    xori x6, x6, 0x0F0        # x6 = 0x0FF ^ 0x0F0 = 0x0000000F
    xori x6, x6, 0x00F        # x6 = 0x00F ^ 0x00F = 0x00000000

    # 測試20: 測試特殊值 -1366 和 -1365
    addi x7, x0, -1366        # x7 = 0xFFFFFAAA (-1366 符號擴展)
    xori x8, x7, -1365        # x8 = 0xFFFFFAAA ^ 0xFFFFFAAB = 0x00000001

end:
    jal x0, end