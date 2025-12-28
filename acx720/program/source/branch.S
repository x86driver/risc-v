_start:
    # 用 x31 當作通過計數器（每通過一項測試就 x31 += 1）
    addi x31, x0, 0

    # --- beq 測試 ---
    # 1) beq taken: 5 == 5
    addi x1, x0, 5
    addi x2, x0, 5
    beq x1, x2, beq_t1_ok
    addi x3, x0, -1  # should be wrong
    jal x0, beq_t1_end
beq_t1_ok:
    addi x31, x31, 1
beq_t1_end:

    # 2) beq not taken: 1 != 2
    addi x1, x0, 1
    addi x2, x0, 2
    beq x1, x2, beq_nt_wrong
    addi x31, x31, 1
    jal x0, beq_nt_end
beq_nt_wrong:
    addi x3, x0, -1  # should be wrong
beq_nt_end:

    # --- bne 測試 ---
    # 3) bne taken: 1 != 2
    addi x1, x0, 1
    addi x2, x0, 2
    bne x1, x2, bne_t_ok
    addi x3, x0, -1  # should be wrong
    jal x0, bne_t_end
bne_t_ok:
    addi x31, x31, 1
bne_t_end:

    # 4) bne not taken: 3 == 3
    addi x1, x0, 3
    addi x2, x0, 3
    bne x1, x2, bne_nt_wrong
    addi x31, x31, 1
    jal x0, bne_nt_end
bne_nt_wrong:
    addi x3, x0, -1  # should be wrong
bne_nt_end:

    # --- blt (signed) 測試 ---
    # 5) blt taken: -1 < 0
    addi x1, x0, -1
    addi x2, x0, 0
    blt x1, x2, blt_t1_ok
    addi x3, x0, -1  # should be wrong
    jal x0, blt_t1_end
blt_t1_ok:
    addi x31, x31, 1
blt_t1_end:

    # 6) blt not taken: 5 !< -1
    addi x1, x0, 5
    addi x2, x0, -1
    blt x1, x2, blt_nt1_wrong
    addi x31, x31, 1
    jal x0, blt_nt1_end
blt_nt1_wrong:
    addi x3, x0, -1  # should be wrong
blt_nt1_end:

    # --- bge (signed) 測試 ---
    # 7) bge taken: -1 >= -1
    addi x1, x0, -1
    addi x2, x0, -1
    bge x1, x2, bge_t1_ok
    addi x3, x0, -1  # should be wrong
    jal x0, bge_t1_end
bge_t1_ok:
    addi x31, x31, 1
bge_t1_end:

    # 8) bge not taken: -1 !>= 0
    addi x1, x0, -1
    addi x2, x0, 0
    bge x1, x2, bge_nt1_wrong
    addi x31, x31, 1
    jal x0, bge_nt1_end
bge_nt1_wrong:
    addi x3, x0, -1  # should be wrong
bge_nt1_end:

    # --- bltu (unsigned) 測試 ---
    # 9) bltu taken: 0 < 0xffffffff
    addi x1, x0, 0
    addi x2, x0, -1
    bltu x1, x2, bltu_t1_ok
    addi x3, x0, -1  # should be wrong
    jal x0, bltu_t1_end
bltu_t1_ok:
    addi x31, x31, 1
bltu_t1_end:

    # 10) bltu not taken: 0xffffffff !< 1
    addi x1, x0, -1
    addi x2, x0, 1
    bltu x1, x2, bltu_nt1_wrong
    addi x31, x31, 1
    jal x0, bltu_nt1_end
bltu_nt1_wrong:
    addi x3, x0, -1  # should be wrong
bltu_nt1_end:

    # --- bgeu (unsigned) 測試 ---
    # 11) bgeu taken: 0xffffffff >= 1
    addi x1, x0, -1
    addi x2, x0, 1
    bgeu x1, x2, bgeu_t1_ok
    addi x3, x0, -1  # should be wrong
    jal x0, bgeu_t1_end
bgeu_t1_ok:
    addi x31, x31, 1
bgeu_t1_end:

    # 12) bgeu not taken: 1 !>= 0xffffffff
    addi x1, x0, 1
    addi x2, x0, -1
    bgeu x1, x2, bgeu_nt1_wrong
    addi x31, x31, 1
    jal x0, bgeu_nt1_end
bgeu_nt1_wrong:
    addi x3, x0, -1  # should be wrong
bgeu_nt1_end:

    # --- 邊界值（signed/unsigned）組合 ---
    # 13) blt (signed) taken: MIN_INT < MAX_INT
    addi x1, x0, 1
    slli x1, x1, 31           # x1 = 0x80000000 (MIN_INT)
    addi x2, x0, -1
    srli x2, x2, 1            # x2 = 0x7fffffff (MAX_INT)
    blt x1, x2, blt_t2_ok
    addi x3, x0, -1  # should be wrong
    jal x0, blt_t2_end
blt_t2_ok:
    addi x31, x31, 1
blt_t2_end:

    # 14) bge (signed) taken: MAX_INT >= MIN_INT
    bge x2, x1, bge_t2_ok     # x2=max, x1=min
    addi x3, x0, -1  # should be wrong
    jal x0, bge_t2_end
bge_t2_ok:
    addi x31, x31, 1
bge_t2_end:

    # 15) bltu (unsigned) not taken: 0x80000000 !< 0x7fffffff
    bltu x1, x2, bltu_nt2_wrong  # x1=min (as unsigned, larger than x2)
    addi x31, x31, 1
    jal x0, bltu_nt2_end
bltu_nt2_wrong:
    addi x3, x0, -1  # should be wrong
bltu_nt2_end:

    # 16) bgeu (unsigned) equality: 123 >= 123
    addi x1, x0, 123
    addi x2, x0, 123
    bgeu x1, x2, bgeu_eq_ok
    addi x3, x0, -1  # should be wrong
    jal x0, bgeu_eq_end
bgeu_eq_ok:
    addi x31, x31, 1
bgeu_eq_end:

    # 17) bne with x0, x0 (not taken)
    bne x0, x0, bne_x0_wrong
    addi x31, x31, 1
    jal x0, bne_x0_end
bne_x0_wrong:
    addi x3, x0, -1  # should be wrong
bne_x0_end:

    # 18) beq 反向位移（向後跳）測試：從後面的 beq 跳回到這裡
    jal x0, beq_backward_entry   # 跳過回跳目標區塊，先到 beq
back_ok:
    addi x31, x31, 1
    jal x0, back_end
beq_backward_entry:
    beq x0, x0, back_ok          # 一次性向後跳
    addi x3, x0, -1  # should be wrong
back_end:

# 19) 前遞（EX->EX）taken：上一條 ALU 寫回，下一條分支比較
    addi x23, x0, 2
    addi x20, x0, 1
    addi x21, x0, 1
    add  x22, x20, x21         # x22 = 2（立即前一條）
    beq  x22, x23, fwd_ex_t1_ok
    addi x3, x0, -1            # wrong path
    jal  x0, fwd_ex_t1_end
fwd_ex_t1_ok:
    addi x31, x31, 1
fwd_ex_t1_end:

# 20) 前遞（EX->EX）not-taken：比較不相等
    addi x23, x0, 3
    addi x20, x0, 1
    addi x21, x0, 1
    add  x22, x20, x21         # x22 = 2（立即前一條）
    beq  x22, x23, fwd_ex_nt1_wrong
    addi x31, x31, 1
    jal  x0, fwd_ex_nt1_end
fwd_ex_nt1_wrong:
    addi x3, x0, -1
fwd_ex_nt1_end:

# 21) load-use hazard（taken）：lw 後緊接 beq 使用載入值
    addi x1, x0, 256           # base addr 0x100
    addi x2, x0, 123           # 期望值
    sw   x2, 0(x1)
    lw   x10, 0(x1)            # 立刻被分支使用
    beq  x10, x2, load_use_t_ok
    addi x3, x0, -1
    jal  x0, load_use_t_end
load_use_t_ok:
    addi x31, x31, 1
load_use_t_end:

# 22) load-use hazard（not-taken）：lw 後緊接 beq 不相等
    addi x2, x0, 123
    sw   x2, 0(x1)
    lw   x10, 0(x1)
    addi x12, x0, 124
    beq  x10, x12, load_use_nt_wrong
    addi x31, x31, 1
    jal  x0, load_use_nt_end
load_use_nt_wrong:
    addi x3, x0, -1
load_use_nt_end:

# 23) 大位移分支（正向，taken）：填充多個 NOP 確保較大偏移
    beq  x0, x0, big_fwd_target
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
big_fwd_target:
    addi x31, x31, 1

# 24) 大位移分支（負向，taken）：從較後位置往前跳
    jal  x0, big_back_branch   # 先跳過目標，確保是負位移
big_back_target:
    addi x31, x31, 1
    jal  x0, big_back_end
    # 大量 NOP 增加距離
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
big_back_branch:
    beq  x0, x0, big_back_target
    addi x3, x0, -1
big_back_end:

# 25) jal 與分支交錯：jal 直接跳過包含分支的區塊（應 flush 順序路徑）
    jal  x0, jal_skip_block1
    beq  x0, x0, jal_wrong1
    addi x3, x0, -1
jal_wrong1:
    addi x3, x0, -1
jal_skip_block1:
    addi x31, x31, 1

# 26) 分支跳入目標內含 jal，再次跳轉（連續兩次控制移轉 flush）
    beq  x0, x0, jal_in_target
    addi x3, x0, -1
jal_in_target:
    jal  x0, jal_after_target
    addi x3, x0, -1
jal_after_target:
    addi x31, x31, 1

# 27) jalr 以暫存器目標（透過 %hi/%lo 載入標籤地址），驗證 PC 以暫存器更新
    lui  x5, %hi(jalr_tgt1)
    addi x5, x5, %lo(jalr_tgt1)
    jalr x0, x5, 0
    addi x3, x0, -1
jalr_tgt1:
    addi x31, x31, 1

# 28) 分支進入區塊後再以 jalr 跳轉（flush + register target 更新）
    beq  x0, x0, setup_jalr_blk
    addi x3, x0, -1
setup_jalr_blk:
    lui  x6, %hi(jalr_tgt2)
    addi x6, x6, %lo(jalr_tgt2)
    jalr x0, x6, 0
    addi x3, x0, -1
jalr_tgt2:
    addi x31, x31, 1

end:
    jal x0, end