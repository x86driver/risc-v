# JAL/JALR 嚴格測試程式 - 修正版
# 專門測試 JAL 和 JALR 指令的正確性

_start:
    # 測試1: 基本 JAL 功能測試
    addi x1, x0, 1          # x1 = 1
    jal x2, test_jal        # x2 = PC+4, 跳到 test_jal
    addi x1, x1, 100        # BUG檢測: 如果執行，x1 會變成 101

test_jal:
    addi x3, x0, 3          # x3 = 3 (確認 JAL 跳躍成功)

    # 測試2: 基本 JALR 功能測試
    auipc x4, 0             # x4 = 當前 PC
    addi x4, x4, 16         # x4 = PC + 16 (指向 test_jalr)
    jalr x5, x4, 0          # x5 = PC+4, 跳到 x4
    addi x3, x3, 100        # BUG檢測: 如果執行，x3 會變成 103

test_jalr:
    addi x6, x0, 6          # x6 = 6 (確認 JALR 跳躍成功)

    # 測試3: JALR 帶偏移量測試
    auipc x7, 0             # x7 = 當前 PC
    addi x7, x7, 20         # x7 = PC + 20 (指向 test_jalr_offset + 4)
    jalr x8, x7, -4         # x8 = PC+4, 跳到 x7-4 (test_jalr_offset)
    addi x6, x6, 100        # BUG檢測: 如果執行，x6 會變成 106

test_jalr_offset:
    addi x9, x0, 9          # x9 = 9 (確認 JALR 偏移正確)

    # 測試4: JAL 不儲存返回地址 (rd = x0)
    jal x0, test_jal_x0     # 跳到 test_jal_x0，不儲存返回地址
    addi x9, x9, 100        # BUG檢測: 如果執行，x9 會變成 109

test_jal_x0:
    addi x10, x0, 10        # x10 = 10 (確認 JAL x0 正確)

    # 測試5: JALR 不儲存返回地址 (rd = x0)
    auipc x11, 0            # x11 = 當前 PC
    addi x11, x11, 16       # x11 = PC + 16 (指向 test_jalr_x0)
    jalr x0, x11, 0         # 跳到 x11，不儲存返回地址
    addi x10, x10, 100      # BUG檢測: 如果執行，x10 會變成 110

test_jalr_x0:
    addi x12, x0, 12        # x12 = 12 (確認 JALR x0 正確)

    # 測試6: 連續跳躍指令測試 (測試 pipeline flush)
    jal x13, chain1         # x13 = PC+4
    jal x0, return_point
    addi x12, x12, 100      # BUG檢測: 如果執行，x12 會變成 112

chain1:
    addi x14, x0, 14        # x14 = 14
    jal x15, chain2         # x15 = PC+4
    addi x14, x14, 100      # BUG檢測: 如果執行，x14 會變成 114

chain2:
    addi x16, x0, 16        # x16 = 16

    # 測試7: 回到之前儲存的地址
    jalr x17, x13, 0        # x17 = PC+4, 跳回到 x13
    addi x16, x16, 100      # BUG檢測: 如果執行，x16 會變成 116

return_point:
    addi x18, x0, 18        # x18 = 18 (確認返回正確)

    # 結束測試
end_test:
    jal x0, end_test        # 無限迴圈
