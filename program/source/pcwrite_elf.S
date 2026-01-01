    .section .text.init
    .globl _start
    .option norvc

// pcwrite_elf.S
// - 基於 program/source/pcwrite.S
// - 目標：用 Spike 作為 oracle 做逐字比對（不依賴 .exp）
// - 修改：
//   1) 將 data memory base 從 0x100 改到 0x8000_0100（符合 Spike 預設 RAM@0x8000_0000）
//   2) 結尾寫 tohost=1，讓 runner 自動停機

_start:
    # 基本設定：x10 作為資料位址基底，x12 作為資料值
    # 注意：Spike 是 unified memory；若把 base 放在 0x8000_0100 之類太靠近 .text 的位置，
    # 可能會覆寫後面的指令造成自修改/illegal instruction。
    # 這裡把 scratch data 區移到更遠的位址，避免覆寫 .text。
    lui  x10, 0x80003
    addi x10, x10, 0           # base = 0x8000_3000
    addi x12, x0, 85           # data = 0x55

    # Case 1: data-mem write；緊接著分支（beq taken）
    sw   x12, 0(x10)
    beq  x0, x0, after_sw_branch1
    addi x3, x0, -1            # 若 PCWrite 錯誤，可能錯誤執行到此
after_sw_branch1:
    addi x1, x0, 1             # 期望提交：x1 = 1

    # Case 2: data-mem write；緊接著 jal（taken, rd=x0 無寫回）
    sw   x12, 4(x10)
    jal  x0, after_sw_jal1
    addi x3, x0, -1            # 若 PCWrite 錯誤，可能錯誤執行到此
after_sw_jal1:
    addi x2, x0, 2             # 期望提交：x2 = 2

    # Case 3: 連續分支決議（beq taken 後緊接 jal x0）
    beq  x0, x0, Lb2
    addi x5, x0, -1
Lb2:
    jal  x0, Lj2
    addi x5, x0, -2
Lj2:
    addi x4, x0, 4             # 期望提交：x4 = 4

    # Case 4: 連續兩次 beq taken
    beq  x0, x0, Lc1
    addi x31, x0, -1
Lc1:
    beq  x0, x0, Lc2
    addi x31, x0, -1
Lc2:
    addi x8, x0, 8             # 期望提交：x8 = 8

    # Case 5: 三連 beq taken
    beq  x0, x0, Ld1
    addi x31, x0, -1
Ld1:
    beq  x0, x0, Ld2
    addi x31, x0, -1
Ld2:
    beq  x0, x0, Ld3
    addi x31, x0, -1
Ld3:
    addi x9, x0, 9             # 期望提交：x9 = 9

    # Case 6: lw-use hazard + 分支（beq）立即使用載入值（taken）
    lw   x5, 0(x10)             # 來自先前 sw 的 0x55
    beq  x5, x12, Lw1
    addi x3, x0, -1
Lw1:
    addi x6, x0, 6              # 期望提交：x6 = 6

    # Case 7: sw 與 jalr x0 同期（在 EX/MEM 交疊）
    sw   x12, 8(x10)
    lui  x5, %hi(after_jalr1)
    addi x5, x5, %lo(after_jalr1)
    jalr x0, x5, 0
    addi x3, x0, -1
after_jalr1:
    addi x11, x0, 11            # 期望提交：x11 = 11

    # Case 8: beq not-taken
    sw   x12, 12(x10)
    addi x15, x0, 0
    addi x16, x0, 1
    beq  x15, x16, Ln1          # not taken
    addi x13, x0, 13            # 期望提交：x13 = 13
Ln1:
    addi x14, x0, 14            # 期望提交：x14 = 14

    # Case 9: 密集分支鏈（全 taken）
    beq  x0, x0, C9b1
    addi x3, x0, -1
C9b1:
    beq  x0, x0, C9b2
    addi x3, x0, -1
C9b2:
    beq  x0, x0, C9b3
    addi x3, x0, -1
C9b3:
    beq  x0, x0, C9b4
    addi x3, x0, -1
C9b4:
    beq  x0, x0, C9b5
    addi x3, x0, -1
C9b5:
    beq  x0, x0, C9b6
    addi x3, x0, -1
C9b6:
    beq  x0, x0, C9b7
    addi x3, x0, -1
C9b7:
    beq  x0, x0, C9end
    addi x3, x0, -1
C9end:
    addi x20, x0, 20            # 期望提交：x20 = 20

    # Case 10: not-taken 交錯
    sw   x12, 16(x10)
    beq  x0, x1, C10_wrong      # not taken
    addi x21, x0, 21
    jal  x0, C10_end
C10_wrong:
    addi x3, x0, -1
C10_end:

    # Case 11: 密集 lw x0 與分支交錯
    lw   x0, 0(x10)
    beq  x0, x0, C11a
    lw   x0, 4(x10)
C11a:
    beq  x0, x0, C11b
    lw   x0, 8(x10)
C11b:
    addi x22, x0, 22

    # Done (always write tohost=1 so Spike runner can collect logs)
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

