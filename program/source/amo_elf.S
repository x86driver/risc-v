    .section .text.init
    .globl _start
    .option norvc

_start:
    # ================================================================
    # Part 1: amoadd.d / amoadd.w 功能驗證（與 spike 逐條比對）
    # ================================================================
    li   a1, 1
    la   a0, amo_var
    amoadd.d a2, a1, (a0)      # a2 = 5,  mem = 6
    amoadd.w a3, a1, (a0)      # a3 = 6,  mem = 7
    ld   a4, 0(a0)             # a4 = 7

    la   a0, amo_var2
    amoadd.w a5, a1, (a0)      # a5 = 0x7fffffff, 低位 word 溢位 wrap 成 0x80000000
    ld   a6, 0(a0)             # a6 = 0xaaaaaaaa_80000000（高位 word 不可被進位污染）

    la   a0, amo_var3
    amoadd.w a7, a1, (a0)      # a7 = 0xffffffff_80000000（舊值 sign-extend）
    ld   s2, 0(a0)             # s2 = 0x55555555_80000001

    # ================================================================
    # Part 2: sd 後面緊跟 CSR 指令
    # 預期 DUT bug：store 完成時 system 序列化讓 backend 前進，
    # 殘留的 dmem_web 把 store 資料寫到實體位址 0（BRAM word 0），
    # 也就是 0x80000000 的前兩條指令。
    # ================================================================
    la   t3, _start
    ld   s1, 0(t3)             # 先快照 _start 的第一個 dword

    la   t0, scratch
    li   t1, 0xBEEF
    sd   t1, 0(t0)             # store...
    csrr t2, mhartid           # ...緊跟一條 0x73 opcode 指令

    ld   t4, 0(t3)             # spike: == s1；DUT bug: == 0xBEEF

    # ================================================================
    # Part 3: amoadd.d 後面緊跟 CSR 指令（AMO 版本的同一個 bug）
    # ================================================================
    la   a0, amo_var
    amoadd.d t5, a1, (a0)      # mem = 8, t5 = 7
    csrr t6, mhartid

    ld   s0, 0(t3)             # spike: == s1；DUT bug: == 8

    bne  t4, s1, fail
    bne  s0, s1, fail

end:
    li     gp, 1
    la     t0, tohost
    sw     gp, 0(t0)
1:
    j 1b

fail:
    li     gp, 2
    la     t0, tohost
    sw     gp, 0(t0)
1:
    j 1b

    // ----------------------------------------------------------------
    // riscv-tests style symbols
    // ----------------------------------------------------------------
    .section .tohost, "aw", @progbits
    .align 6
    .globl tohost
tohost:
    .dword 0
    .globl fromhost
fromhost:
    .dword 0

    .globl begin_signature
begin_signature:
    .align 3
amo_var:
    .dword 5
amo_var2:
    .dword 0xAAAAAAAA7FFFFFFF
amo_var3:
    .dword 0x5555555580000000
scratch:
    .dword 0
    .globl end_signature
end_signature:
