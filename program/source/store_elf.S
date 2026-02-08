    .section .text.init
    .globl _start
    .option norvc

// store_elf.S
// - 基於 program/source/store.S（保留主要的 sb/sh/sw 覆寫行為）
// - 移除「misaligned halfword store」(odd address 的 sh) 以避免 Spike 直接陷入（除非你已實作 misaligned trap）
// - base 改到 0x8000_0100，確保 Spike memory map 內可存取
// - 結尾寫 tohost 讓 runner 自動停機並做逐字比對

_start:
    # base = 0x8000_0100
    li   x1, 0x80000100

    # prepare byte values: 0x11, 0x22, 0x80, 0xFF
    addi x2, x0, 17
    addi x3, x0, 34
    addi x4, x0, 128
    addi x5, x0, 255

    # prepare halfword values: 0x1234, 0xABCD
    lui  x6, 0x1
    ori  x6, x6, 0x234
    addi x7, x0, 0xab       # 0x00ab
    slli x7, x7, 8          # 0x00ab00
    ori  x7, x7, 0xcd       # 0x00abcd

    # prepare word value: 0xA1B2C3D4 and byte 0x55
    lui  x8, 0xa1b2c
    ori  x8, x8, 0x3d4
    addi x9, x0, 0x55

    # -------- sb tests on word [base+0]
    sw   x0, 0(x1)            # clear word
    sb   x2, 0(x1)            # [7:0]   = 0x11
    lw   x10, 0(x1)           # expect 0x00000011

    sb   x3, 1(x1)            # [15:8]  = 0x22
    lw   x10, 0(x1)           # expect 0x00002211

    sb   x4, 2(x1)            # [23:16] = 0x80
    lw   x10, 0(x1)           # expect 0x00802211

    sb   x5, 3(x1)            # [31:24] = 0xFF
    lw   x10, 0(x1)           # expect 0xFF802211

    # byte-precise readback
    lbu  x13, 0(x1)           # 0x11
    lbu  x14, 1(x1)           # 0x22
    lbu  x15, 2(x1)           # 0x80
    lbu  x16, 3(x1)           # 0xFF

    # -------- sh tests on word [base+4] (aligned)
    sw   x0, 4(x1)            # clear word
    sh   x6, 4(x1)            # low half = 0x1234
    lw   x17, 4(x1)           # expect 0x00001234

    sh   x7, 6(x1)            # high half = 0xABCD
    lw   x17, 4(x1)           # expect 0xABCD1234

    lhu  x19, 4(x1)           # 0x1234
    lhu  x20, 6(x1)           # 0xABCD

    # -------- sw test and overlapping sb/sh on word [base+8]
    sw   x8, 8(x1)            # write 0xA1B2C3D4
    lw   x21, 8(x1)           # expect 0xA1B2C3D4

    sb   x9, 10(x1)           # modify byte[2] -> 0x55
    lw   x21, 8(x1)           # expect 0xA155C3D4

    lui  x22, 0x6
    ori  x22, x22, 0x677      # x22 = 0x00006677
    sh   x22, 10(x1)          # overwrite high half -> 0x6677C3D4
    lw   x21, 8(x1)           # expect 0x6677C3D4

end:
    li     gp, 1
    la     t0, tohost
    sw     gp, 0(t0)
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

