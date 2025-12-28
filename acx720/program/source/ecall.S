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
    csrr x4, mepc
    addi x4, x4, 4
    csrw mepc, x4
    mret
