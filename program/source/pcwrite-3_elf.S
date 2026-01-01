    .section .text.init
    .globl _start
    .option norvc

// pcwrite-3_elf.S
// - 基於 program/source/pcwrite-3.S
// - 修改：
//   1) data memory base -> 0x8000_0100
//   2) 結尾寫 tohost=1 自動停機

_start:
    # pcwrite-3: PCWrite/flush/stall 交錯 corner-case 測試
    # 通用設定
    addi x31, x0, 0             # pass counter
    # Spike unified memory：避免 data store 覆寫 .text（自修改）
    lui  x10, 0x80003
    addi x10, x10, 0             # base = 0x8000_3000
    addi x12, x0, 1              # data = 1
    sw   x12, 0(x10)             # [base+0] = 1

    # ------------------------------------------------------------
    # Case 1: lw -> beq (load-use hazard)
    # ------------------------------------------------------------
    addi x4, x0, 0
    lw   x4, 0(x10)
    beq  x4, x0, C1_fail
    addi x31, x31, 1             # PASS1
    jal  x0, C1_end
C1_fail:
    addi x3, x0, -1              # FAIL marker (should never commit)
C1_end:

    # ------------------------------------------------------------
    # Case 2: unconditional taken
    # ------------------------------------------------------------
    lw   x5, 0(x10)
    beq  x0, x0, C2_tgt
    addi x3, x0, -2
C2_tgt:
    addi x31, x31, 1             # PASS2

    # ------------------------------------------------------------
    # Case 3: jal (rd!=0)
    # ------------------------------------------------------------
    lw   x6, 0(x10)
    jal  x7, C3_tgt
    addi x3, x0, -3
C3_tgt:
    addi x7, x7, 1
    addi x31, x31, 1             # PASS3

    # ------------------------------------------------------------
    # Case 4: sw + jalr (rd!=0)
    # ------------------------------------------------------------
    sw   x12, 4(x10)
    lui  x8, %hi(C4_tgt)
    addi x8, x8, %lo(C4_tgt)
    jalr x9, x8, 0               # write link to x9
    addi x3, x0, -4
C4_tgt:
    addi x9, x9, 1
    addi x31, x31, 1             # PASS4

    # ------------------------------------------------------------
    # Case 5: sw(label) -> lw -> jalr x0
    # ------------------------------------------------------------
    lui  x11, %hi(C5_tgt)
    addi x11, x11, %lo(C5_tgt)
    sw   x11, 8(x10)
    lw   x13, 8(x10)
    jalr x0, x13, 0
    addi x3, x0, -5
C5_tgt:
    addi x31, x31, 1             # PASS5

    # ------------------------------------------------------------
    # Case 6: back-to-back redirect
    # ------------------------------------------------------------
    beq  x0, x0, C6_l1
    addi x3, x0, -6
C6_l1:
    jal  x0, C6_l2
    addi x3, x0, -7
C6_l2:
    addi x31, x31, 1             # PASS6

    # 最終：把 pass counter 搬到 x5（x5 應為 6）
    addi x5, x31, 0

    # Done
    li   gp, 1
    la   t0, tohost
    sw   gp, 0(t0)
1:
    j 1b

    .section .tohost, "aw", @progbits
    .align 6
    .globl tohost
tohost:
    .dword 0
    .globl fromhost
fromhost:
    .dword 0

