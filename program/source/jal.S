_start:
    addi x1, x0, 10
    add x2, x0, x0
    add x3, x0, x0
.L1:
    add x2, x2, x1
    addi x1, x1, -1
    bne x1, x0, .L1
    jal x4, .L2
    addi x3, x3, 1
.L2:
    addi x3, x3, 2
