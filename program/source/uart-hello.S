    .section .text
    .globl _start

    .equ UART_BASE, 0x700

_start:
    li x1, UART_BASE
    li x2, 'A'
    li x3, 'B'
    sw x2, 4(x1)
#    sw x3, 4(x1)
#    sw x3, 4(x1)
#    lw x3, 8(x1) # STAT_REG

end:
    j end
