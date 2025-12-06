    .section .text
    .globl _start

    .equ UART_BASE, 0x700
    .equ UART_TX, 0x4
    .equ UART_STATUS, 0x8

_start:
    li x1, UART_BASE

    # Case 1: Basic Single Write
    # Expect: 'A'
    li x2, 'A'
    sw x2, UART_TX(x1)

    # Case 2: Back-to-Back Write
    # Checks if LSU resets state immediately for next instruction
    # Expect: 'BC'
    li x2, 'B'
    li x3, 'C'
    sw x2, UART_TX(x1)
    sw x3, UART_TX(x1)

    # Case 3: Write with Pipeline Bubbles (NOPs)
    # Checks if LSU state remains stable (doesn't re-fire) during stalls/bubbles
    # Expect: 'DE'
    li x2, 'D'
    li x3, 'E'
    sw x2, UART_TX(x1)
    nop
    nop
    nop
    sw x3, UART_TX(x1)

    # Case 4: Write same value Back-to-Back
    # Checks that we rely on handshake, not data value change
    # Expect: 'FF'
    li x2, 'F'
    sw x2, UART_TX(x1)
    sw x2, UART_TX(x1)

    # Case 5: Read-Modify-Write (Interleaved operations)
    # Read Status (just to occupy LSU read path), then Write
    # Expect: 'G'
    lw x3, UART_STATUS(x1)
    li x2, 'G'
    sw x2, UART_TX(x1)

    # Case 6: Tight Loop Write (Branching)
    # Checks interaction with branch/pipeline flushes
    # Expect: 'HIJ'
    li x2, 'H'
    li x3, 'J' # End char
loop_start:
    sw x2, UART_TX(x1)
    addi x2, x2, 1
    ble x2, x3, loop_start

end:
    j end
