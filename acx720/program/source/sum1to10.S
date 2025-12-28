  /*sum(1..to..10)*/

_start:
        add x2, x0, x0
        addi x1, x0, 10
.L1:
        add x2, x2, x1
        addi x1, x1, -1
        bne x1, x0, .L1