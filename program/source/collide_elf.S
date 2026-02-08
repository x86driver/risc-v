    .section .text.init
    .globl _start
    .option norvc

_start:
    // ======== Test: imem read + dmem write at the same address ========
    //
    // This CPU uses a unified true dual-port BRAM:
    //   Port A = instruction fetch (read-only)
    //   Port B = data access (read/write)
    //
    // When both ports hit the same BRAM word on the same clock edge
    // (port A reading, port B writing), the Verilog non-blocking
    // assignment evaluation order may corrupt port A's read in
    // simulation (Verilator, iverilog).
    //
    // Strategy:
    //   1. lw  reads the encoding of 'collide_target' into t1
    //   2. sw  writes the SAME encoding back → memory content unchanged
    //   3. If IF correctly fetches the original instruction → x10 = 42 → PASS
    //   4. If the dual-port collision corrupts the fetch → x10 ≠ 42 → FAIL
    //
    // Because the stored value is identical to the original, Spike
    // (reference model) always PASSes. A DUT failure pinpoints a
    // dual-port BRAM read/write collision bug.
    //
    // Pipeline timing (classic 5-stage):
    //   sw is in MEM when I[sw+3] is in IF, so 2 NOPs separate
    //   sw from collide_target. With multi-cycle memory the overlap
    //   may shift — adjust NOP count if needed.

    la     t0, collide_target    // address of the target instruction
    lw     t1, 0(t0)            // load its encoding (expect 0x02A00513)
    li     x10, 0               // clear result; also separates lw/sw to
                                // avoid load-use hazard on t1
    sw     t1, 0(t0)            // dmem write → same BRAM word as collide_target
    nop                          // pipeline filler (sw+1)
    nop                          // pipeline filler (sw+2)
collide_target:
    addi   x10, x0, 42          // 0x02A00513 — IF must fetch this correctly
    li     t2, 42
    bne    x10, t2, fail

    // Signal PASS to the test runner (write non-zero to tohost)
    li     gp, 1
    la     t0, tohost
    sw     gp, 0(t0)
1:
    j      1b

fail:
    li     gp, 2
    la     t0, tohost
    sw     gp, 0(t0)
1:
    j      1b

    // ----------------------------------------------------------------
    // riscv-tests style symbols
    // ----------------------------------------------------------------
    .section .tohost, "aw", @progbits
    .align 6
    .globl tohost
tohost:
    .dword 0
    .globl fromhost
fromhost:
    .dword 0

    // Keep signature region empty by default (begin == end).
    // The Verilator runner will still create an empty .sig file for tooling.
    .globl begin_signature
begin_signature:
    .globl end_signature
end_signature:

