    .section .text
    .globl _start

    .equ DATA_ADDR, 0x100

_start:
    addi x1, x0, 1
    addi x2, x0, 2
    addi x3, x0, 3
    li x4, DATA_ADDR
    sw x1, 0(x4)
    sw x2, 4(x4)
    sw x3, 8(x4)

    lw x5, 0(x4)
    lw x6, 4(x4)
    lw x7, 8(x4)

end:
    j end
