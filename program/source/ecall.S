_start:

    la x1, ex0
    csrrw x2, mtvec, x1
    nop
    nop
    ecall

    addi x2, x0, 2
end:
    jal x0, end

ex0:
    addi x3, x0, 3
    j end

    # csrr x6, mepc
    # addi x6, x6, 4
    # csrrw x0, mepc, x6
    # mret