        .section .data
result: .word 0
msg:
        .asciz "Hello World"

        .section .text
        .globl _start

_start:
        addi x1, x0, 9
incr:
        addi x1, x1, 1
        jal x2, incr
        addi x3, x0, 0xf