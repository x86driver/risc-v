_start:

    addi x5, x0, 5
    la x1, ex0
    # csrrw x2, mtvec, x1
    # nop
    # nop
    csrrwi x2, mtvec, 0x1c # rs1 = 0x1c = 28
    # nop
    # nop
    ecall

    addi x2, x0, 2
end:
    jal x0, end

ex0:
    addi x4, x0, 4
    addi x5, x0, 0xff

    csrrs x6, mepc, x4
    csrrs x7, mepc, x5
    j end
    # addi x6, x6, 4
    # csrrw x0, mepc, x6
    mret