_start:
    # base = 0x00000100
    addi x1, x0, 256

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

    # -------- sh tests on word [base+4]
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

    # -------- negative S-imm addressing checks on [base+12]
    sw   x0, 12(x1)           # clear word
    sb   x2, 12(x1)           # byte0 = 0x11
    lw   x24, 12(x1)          # expect 0x00000011

    addi x23, x1, 16          # x23 = base + 16
    sh   x6, -2(x23)          # store 0x1234 to [base+14] (high half of [base+12])
    lw   x24, 12(x1)          # expect 0x12340011

    # -------- unaligned sb/sh stress on consecutive addresses [base+16..base+23]
    # layout two words at base+16 and base+20. Repeated overwrites to exercise masks.
    sw   x0, 16(x1)           # clear word W0
    sw   x0, 20(x1)           # clear word W1
    # Round 1: fill bytes at offsets 0..3 in W0, and 0..3 in W1
    addi x25, x0, 0xAA
    addi x26, x0, 0xBB
    addi x27, x0, 0xCC
    addi x28, x0, 0xDD
    sb   x25, 16(x1)          # W0[0]=AA
    sb   x26, 17(x1)          # W0[1]=BB
    sb   x27, 18(x1)          # W0[2]=CC
    sb   x28, 19(x1)          # W0[3]=DD  -> W0=0xDDCCBBAA
    lw   x29, 16(x1)
    sb   x25, 20(x1)          # W1[0]=AA
    sb   x26, 21(x1)          # W1[1]=BB
    sb   x27, 22(x1)          # W1[2]=CC
    sb   x28, 23(x1)          # W1[3]=DD  -> W1=0xDDCCBBAA
    lw   x30, 20(x1)

    # Round 5: unaligned sh on W0 at offsets 1 and 3
    sh   x7, 17(x1)          # W0 low half = 0xABCD (odd offset still selects low half)
    lw   x29, 16(x1)         # expect 0xA556ABCD
    sh   x6, 19(x1)          # W0 high half = 0x1234 (odd offset selects high half)
    lw   x29, 16(x1)         # expect 0x1234ABCD

    # Round 2: overwrite W0 with different pattern using unaligned sh pairs
    # Write low half then high half using offsets 16 and 18 (cross-check both halves)
    addi x11, x0, 0x34        # 0x1234 low byte
    slli x11, x11, 8          # 0x3400
    ori  x11, x11, 0x12       # x11 = 0x3412 (little-endian half when stored to low half)
    addi x12, x0, 0x78
    slli x12, x12, 8
    ori  x12, x12, 0x56       # x12 = 0x7856
    sh   x11, 16(x1)          # W0 low half = 0x3412
    sh   x12, 18(x1)          # W0 high half = 0x7856  -> W0=0x78563412
    lw   x29, 16(x1)

    # Round 3: overlapping writes on W0 to stress byte enables
    addi x25, x0, 0x9E
    sb   x25, 17(x1)          # overwrite byte1 -> W0 becomes 0x78569E12
    lw   x29, 16(x1)
    addi x26, x0, 0xA5
    sb   x26, 19(x1)          # overwrite byte3 -> W0 becomes 0xA5569E12
    lw   x29, 16(x1)

    # Round 4: cross-word boundary halfword write to W1 using -2 offset from base+22
    # Equivalent to writing high half at 20 and low half at 22 in one instruction
    # but sh stores 16-bit starting at address; so use separate ops to construct expected value.
    sh   x11, 20(x1)          # W1 low half = 0x3412
    sh   x12, 22(x1)          # W1 high half = 0x7856 -> W1=0x78563412
    lw   x30, 20(x1)

end:
    jal x0, end