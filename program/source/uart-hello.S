    .section .text
    .globl _start
    .option norvc

// ================================================================
// BRAM Dual-Port Collision Test (FPGA)
// ================================================================
//
// This CPU uses a unified true dual-port BRAM:
//   Port A = instruction fetch (imem, read-only)
//   Port B = data access       (dmem, read/write)
//
// When sw is in MEM, the pipeline stall sequence guarantees that
// dmem's web (port B write-enable) is active on the SAME clock
// edge that imem captures douta (port A read) — if the target
// instruction is 2 NOPs after the sw.
//
// On Xilinx UltraScale BRAM, the cross-port collision behavior
// depends on the inferred write mode:
//   READ_FIRST  → port A reads OLD data → x10 = 42 → 'O'
//   WRITE_FIRST → port A reads NEW data → x10 = 99 → 'N'
//   Undefined   → port A reads garbage  → x10 = ??  → 'X'
//
// UART output: one character per test iteration, 20 per line.
//   'O' = Old value fetched (correct, READ_FIRST)
//   'N' = New value fetched (WRITE_FIRST or post-write fetch)
//   'X' = Corruption detected
// ================================================================

    .equ UART_BASE,  0x700
    .equ UART_TX,    4          // TX FIFO offset
    .equ CHAR_DELAY, 1000000   // inter-char delay (~10 ms @ 100 MHz)
    .equ ITERATIONS, 20        // tests per line

_start:
    // Stack in mid-BRAM (far from code at index 0)
    li   sp, 0x80004000
    li   s0, UART_BASE

    // ---- Print banner "COL:" ----
    li   a0, 'C'
    jal  ra, uart_putc
    li   a0, 'O'
    jal  ra, uart_putc
    li   a0, 'L'
    jal  ra, uart_putc
    li   a0, ':'
    jal  ra, uart_putc

main_loop:
    li   s1, 0                  // iteration counter

batch_loop:
    // ============================================================
    // Set up collision scenario
    // ============================================================
    // collide_target holds "addi x10, x0, 42" (encoding 0x02A00513).
    // We overwrite it with  "addi x10, x0, 99" (encoding 0x06300513).
    //
    // Pipeline timing (5-stage, multi-cycle IF):
    //   After 'sw' is fetched, the pipeline advances 3 times before
    //   sw reaches MEM.  Each advance pulls the next instruction
    //   into IF.  With 2 NOPs between sw and collide_target:
    //     advance 1 → nop (sw+1) enters IF
    //     advance 2 → nop (sw+2) enters IF
    //     advance 3 → collide_target enters IF, sw enters MEM
    //   ⇒ imem port A reads collide_target while dmem port B
    //     writes to the same BRAM word.  Collision guaranteed.
    // ============================================================

    la   t0, collide_target     // address of target instruction
    lw   t1, 0(t0)              // save original encoding
    li   x10, 0                 // clear result
    li   t2, 0x06300513         // "addi x10, x0, 99" — DIFFERENT encoding

    // --- Critical section: trigger collision ---
    sw   t2, 0(t0)              // dmem write to collide_target's BRAM word
    nop                         //   sw+1  (in EX when sw is in MEM)
    nop                         //   sw+2  (in ID when sw is in MEM)
collide_target:
    addi x10, x0, 42            // sw+3  (in IF when sw is in MEM) — 0x02A00513
    // --- End critical section ---

    // Restore original instruction for next iteration
    sw   t1, 0(t0)
    fence.i                     // flush pipeline, re-fetch from BRAM

    // ============================================================
    // Classify result and output via UART
    // ============================================================
    li   t3, 42
    beq  x10, t3, .Lold         // x10 = 42 → old instruction (READ_FIRST)
    li   t3, 99
    beq  x10, t3, .Lnew         // x10 = 99 → new instruction (WRITE_FIRST)
    // x10 = something else → corruption
    li   a0, 'X'
    jal  ra, uart_putc
    j    .Lnext

.Lold:
    li   a0, 'O'
    jal  ra, uart_putc
    j    .Lnext

.Lnew:
    li   a0, 'N'
    jal  ra, uart_putc

.Lnext:
    addi s1, s1, 1
    li   t4, ITERATIONS
    blt  s1, t4, batch_loop

    // End of batch — print CR LF
    li   a0, '\r'
    jal  ra, uart_putc
    li   a0, '\n'
    jal  ra, uart_putc

    // Brief pause, then next batch
    li   t5, 5000000
.Lpause:
    addi t5, t5, -1
    bnez t5, .Lpause
    j    main_loop

// ================================================================
// uart_putc — send one byte in a0 via AXI UARTLite TX FIFO
// ================================================================
uart_putc:
    sw   a0, UART_TX(s0)        // write to TX FIFO
    li   t6, CHAR_DELAY
.Ldelay:
    addi t6, t6, -1
    bnez t6, .Ldelay
    jalr x0, ra, 0              // return
