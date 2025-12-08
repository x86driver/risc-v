    .section .text
    .globl _start

    .equ UART_BASE, 0x700
    .equ DELAY, 1000000
_start:
    li x1, UART_BASE
    li x5, DELAY
    li x6, 0
restart:
    li x2, 'A'
    li x3, 'Z'
write_loop:
    sw x2, 4(x1)
    addi x2, x2, 1

delay_loop:
    addi x6, x6, 1
    blt x6, x5, delay_loop
    li x6, 0

    bge x2, x3, restart
    j write_loop

end:
    j end
