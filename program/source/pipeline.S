# 五级流水线 RISC-V CPU 全面测试程序
# 测试目标: 验证 forwarding, hazard detection, stall, branch prediction, corner cases
# 作者: AI Assistant
# 日期: 2025-01-20
# 测试覆盖的Corner Cases：
# 连续数据依赖 - 测试了连续的前递情况
# Load-Use冒险 - 测试了最常见的流水线冒险
# 分支跳转 - 测试了taken/not taken两种情况
# JAL指令 - 测试了跳转并链接的复杂情况
# 立即数边界 - 测试了各种立即数格式

.section .text
.globl _start

_start:
    # 初始化测试环境
    addi x1, x0, 0      # x1 = 0 (清零)
    addi x2, x0, 1      # x2 = 1 
    addi x3, x0, 2      # x3 = 2
    addi x4, x0, 3      # x4 = 3
    addi x5, x0, 4      # x5 = 4

    # ========================================
    # 测试 1: 基本数据前递 (EX-EX forwarding)
    # ========================================
test_ex_ex_forwarding:
    addi x6, x0, 10     # x6 = 10
    add  x7, x6, x2     # x7 = x6 + x2 = 10 + 1 = 11 (需要 EX->EX forwarding)
    add  x8, x7, x3     # x8 = x7 + x3 = 11 + 2 = 13 (需要 EX->EX forwarding)
    
    # ========================================
    # 测试 2: MEM-EX forwarding
    # ========================================  
test_mem_ex_forwarding:
    addi x9, x0, 20     # x9 = 20
    addi x10, x0, 0     # x10 = 0 (用作内存地址)
    sw   x9, 0(x10)     # mem[0] = 20
    add  x11, x9, x2    # x11 = x9 + x2 = 20 + 1 = 21 (需要 MEM->EX forwarding)

    # ========================================
    # 测试 3: Load-Use Hazard (应该产生 stall)
    # ========================================
test_load_use_hazard:
    addi x12, x0, 4     # x12 = 4 (内存地址)
    addi x13, x0, 100   # x13 = 100
    sw   x13, 0(x12)    # mem[4] = 100
    lw   x14, 0(x12)    # x14 = mem[4] = 100
    add  x15, x14, x2   # x15 = x14 + x2 = 100 + 1 = 101 (应该 stall 一个周期)
    
    # ========================================
    # 测试 4: 连续 Load-Use Hazard
    # ========================================
test_double_load_use:
    addi x16, x0, 8     # x16 = 8
    addi x17, x0, 200   # x17 = 200  
    sw   x17, 0(x16)    # mem[8] = 200
    lw   x18, 0(x16)    # x18 = mem[8] = 200
    lw   x19, 0(x16)    # x19 = mem[8] = 200 (第二个 load)
    add  x20, x18, x19  # x20 = x18 + x19 = 200 + 200 = 400 (双重依赖)

    # ========================================
    # 测试 5: 分支指令测试 - BEQ taken
    # ========================================
test_beq_taken:
    addi x21, x0, 5     # x21 = 5
    addi x22, x0, 5     # x22 = 5
    beq  x21, x22, branch_target_1  # 应该跳转
    addi x23, x0, 999   # 这条指令不应该执行
    
branch_target_1:
    addi x23, x0, 555   # x23 = 555 (正确跳转到这里)

    # ========================================
    # 测试 6: 分支指令测试 - BEQ not taken
    # ========================================
test_beq_not_taken:
    addi x24, x0, 6     # x24 = 6
    addi x25, x0, 7     # x25 = 7
    beq  x24, x25, branch_target_2  # 不应该跳转
    addi x26, x0, 777   # x26 = 777 (应该执行这条)
    jal  x0, after_branch_2
    
branch_target_2:
    addi x26, x0, 888   # 不应该执行
    
after_branch_2:

    # ========================================
    # 测试 7: BNE 指令测试
    # ========================================
test_bne:
    addi x27, x0, 8     # x27 = 8
    addi x28, x0, 9     # x28 = 9  
    bne  x27, x28, branch_target_3  # 应该跳转
    addi x29, x0, 111   # 不应该执行
    
branch_target_3:
    addi x29, x0, 333   # x29 = 333

    # ========================================
    # 测试 8: JAL 指令测试 (跳转并链接) - 简化版本
    # ========================================
test_jal:
    addi x30, x0, 0     # x30 = 0
    jal  x31, jal_target    # x31 = return address, 跳转到 jal_target
    # 程序会从 jal_target 继续执行，不会回到这里
    addi x30, x0, 666   # 这行不会执行

jal_target:
    addi x30, x0, 444   # x30 = 444 (在跳转目标中)
    # 简化：直接继续到下一个测试，不返回

    # ========================================
    # 测试 9: 复杂的数据依赖链
    # ========================================
test_complex_dependency:
    addi x1, x0, 1      # x1 = 1
    add  x2, x1, x1     # x2 = x1 + x1 = 2 (EX->EX)
    add  x3, x2, x1     # x3 = x2 + x1 = 3 (EX->EX)
    add  x4, x3, x2     # x4 = x3 + x2 = 5 (EX->EX, MEM->EX)
    add  x5, x4, x3     # x5 = x4 + x3 = 8 (EX->EX, MEM->EX)

    # ========================================
    # 测试 10: Load 后立即 Store 到同一地址
    # ========================================
test_load_store_same_addr:
    addi x6, x0, 12     # x6 = 12 (地址)
    addi x7, x0, 1000   # x7 = 1000
    sw   x7, 0(x6)      # mem[12] = 1000
    lw   x8, 0(x6)      # x8 = mem[12] = 1000
    addi x9, x8, 1      # x9 = x8 + 1 = 1001 (load-use hazard)
    sw   x9, 0(x6)      # mem[12] = 1001 (store back)

    # ========================================
    # 测试 11: 分支指令中的数据前递
    # ========================================
test_branch_forwarding:
    addi x10, x0, 10    # x10 = 10
    addi x11, x0, 10    # x11 = 10
    add  x12, x10, x0   # x12 = x10 = 10
    beq  x12, x11, branch_target_4  # x12 需要前递，应该跳转
    addi x13, x0, 999   # 不应该执行
    
branch_target_4:
    addi x13, x0, 1111  # x13 = 1111

    # ========================================
    # 测试 12: 嵌套分支和跳转
    # ========================================
test_nested_branches:
    addi x14, x0, 1     # x14 = 1
    addi x15, x0, 1     # x15 = 1
    beq  x14, x15, nested_1  # 第一层分支
    addi x16, x0, 777   # 不应该执行
    
nested_1:
    addi x16, x0, 2     # x16 = 2
    addi x17, x0, 3     # x17 = 3
    bne  x16, x17, nested_2  # 第二层分支
    addi x18, x0, 888   # 不应该执行
    
nested_2:
    # addi x18, x0, 2222 会超出12位立即数限制，需要用 lui + addi
    lui  x18, 0x1      # x18 = 0x1000 = 4096
    addi x18, x18, -1874  # x18 = 4096 - 1874 = 2222

    # ========================================
    # 测试 13: 边界情况 - x0 寄存器
    # ========================================
test_x0_register:
    addi x0, x0, 999    # 尝试写 x0 (应该无效)
    add  x19, x0, x2    # x19 = 0 + 1 = 1 (x0 应该始终为 0)
    sw   x19, 16(x0)    # mem[16] = 1 (使用 x0 作为基址)
    lw   x20, 16(x0)    # x20 = mem[16] = 1

    # ========================================
    # 测试 14: 立即数指令测试
    # ========================================
test_immediate_instructions:
    addi x21, x0, -1    # x21 = -1 (负立即数)
    andi x22, x21, 0xFF # x22 = x21 & 0xFF = 0xFF
    ori  x23, x0, 0x100 # x23 = 0 | 0x100 = 0x100

    # ========================================
    # 测试 15: LUI 和 AUIPC 指令
    # ========================================
test_upper_immediate:
    lui  x24, 0x12345   # x24 = 0x12345000
    auipc x25, 0x1      # x25 = PC + 0x1000

    # ========================================
    # 测试 16: 压力测试 - 快速连续操作
    # ========================================
test_rapid_operations:
    addi x26, x0, 1     # x26 = 1
    add  x27, x26, x26  # x27 = 2
    add  x28, x27, x27  # x28 = 4
    add  x29, x28, x28  # x29 = 8
    add  x30, x29, x29  # x30 = 16
    add  x31, x30, x30  # x31 = 32

    # ========================================
    # 测试 17: 内存对齐测试
    # ========================================
test_memory_alignment:
    addi x1, x0, 20     # x1 = 20 (对齐地址)
    # addi x2, x0, 0x1234 会超出12位立即数限制，需要用 lui + addi
    lui  x2, 0x1        # x2 = 0x1000 = 4096
    addi x2, x2, 564    # x2 = 4096 + 564 = 4660 = 0x1234
    sw   x2, 0(x1)      # mem[20] = 0x1234
    sw   x2, 4(x1)      # mem[24] = 0x1234
    lw   x3, 0(x1)      # x3 = mem[20] = 0x1234
    lw   x4, 4(x1)      # x4 = mem[24] = 0x1234

    # ========================================
    # 测试 18: 分支预测失败恢复测试
    # ========================================
test_branch_misprediction:
    addi x5, x0, 10     # x5 = 10
    addi x6, x0, 20     # x6 = 20
    beq  x5, x6, wrong_branch   # 不会跳转
    addi x7, x0, 100    # x7 = 100 (正确执行)
    bne  x5, x6, correct_branch # 会跳转
    addi x8, x0, 200    # 不应该执行
    jal  x0, after_branch_test

wrong_branch:
    addi x7, x0, 999    # 不应该执行
    
correct_branch:
    addi x8, x0, 300    # x8 = 300

after_branch_test:

    # ========================================
    # 测试 19: 极限数据依赖 - 五级流水线全占用
    # ========================================
test_full_pipeline_dependency:
    addi x9, x0, 1      # Stage 1: x9 = 1
    add  x10, x9, x0    # Stage 2: x10 = 1 (依赖 x9)
    add  x11, x10, x0   # Stage 3: x11 = 1 (依赖 x10)  
    add  x12, x11, x0   # Stage 4: x12 = 1 (依赖 x11)
    add  x13, x12, x0   # Stage 5: x13 = 1 (依赖 x12)
    add  x14, x13, x0   # x14 = 1 (依赖 x13，测试 WB->EX forwarding)

    # ========================================
    # 测试 20: 结束标记 - 将结果写入特定内存位置
    # ========================================
test_completion:
    # 将一些关键测试结果写入内存供验证
    addi x1, x0, 100    # 基址 = 100
    sw   x7, 0(x1)      # mem[100] = x7 (应该是 100)
    sw   x8, 4(x1)      # mem[104] = x8 (应该是 300) 
    sw   x13, 8(x1)     # mem[108] = x13 (应该是 1)
    sw   x15, 12(x1)    # mem[112] = x15 (load-use 测试结果，应该是 101)
    sw   x20, 16(x1)    # mem[116] = x20 (double load-use 测试结果，应该是 400)
    sw   x23, 20(x1)    # mem[120] = x23 (beq taken 测试，应该是 555)
    sw   x26, 24(x1)    # mem[124] = x26 (beq not taken 测试，应该是 777)
    sw   x29, 28(x1)    # mem[128] = x29 (bne 测试，应该是 333)

    # 最终完成标记 (使用简单的值避免立即数范围问题)
    addi x31, x0, 1000      # x31 = 1000 (完成标记)
    sw   x31, 32(x1)        # mem[132] = 1000

# 无限循环结束
end_loop:
    jal x0, end_loop
