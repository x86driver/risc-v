.globl _start

_start:
    jal x0, start_test

test_data:
    .byte 0x00, 0x7F, 0x80, 0xFF      # [0..3]
    .byte 0x12, 0x34, 0x56, 0x78      # [4..7]
    .word 0x00000000                  # [8..11]
    .word 0xFFFFFFFF                  # [12..15]

start_test:
    la   x1, test_data

    # Aligned word loads (lw)
    lw   x2, 0(x1)         # 0xff807f00
    lw   x3, 4(x1)         # 0x78563412
    lw   x4, 8(x1)         # 0x00000000
    lw   x5, 12(x1)        # 0xffffffff

    # Byte loads (signed)
    lb   x6, 0(x1)         # 0x00000000
    lb   x6, 1(x1)         # 0x0000007f
    lb   x6, 2(x1)         # 0xffffff80
    lb   x6, 3(x1)         # 0xffffffff

    # Byte loads (unsigned)
    lbu  x7, 0(x1)         # 0x00000000
    lbu  x7, 1(x1)         # 0x0000007f
    lbu  x7, 2(x1)         # 0x00000080
    lbu  x7, 3(x1)         # 0x000000ff

    # Next 4 bytes block pointer (points to 0x8)
    addi x8, x1, 4         # x8 = 8

    # Byte loads on next block (signed)
    lb   x9, 0(x8)         # 0x00000012
    lb   x9, 1(x8)         # 0x00000034
    lb   x9, 2(x8)         # 0x00000056
    lb   x9, 3(x8)         # 0x00000078

    # Cross-boundary byte loads (unsigned)
    lbu  x10, 7(x1)        # 0x000000ff
    lbu  x11, 8(x1)        # 0x00000012

    # Halfword loads (signed)
    lh   x12, 0(x1)        # 0x00007f00
    lh   x12, 2(x1)        # 0xffffff80
    lh   x13, 4(x1)        # 0x00003412
    lh   x13, 6(x1)        # 0x00007856

    # Halfword loads (unsigned)
    lhu  x14, 0(x1)        # 0x00007f00
    lhu  x14, 2(x1)        # 0x0000ff80
    lhu  x15, 4(x1)        # 0x00003412
    lhu  x15, 6(x1)        # 0x00007856

end:
    jal x0, end