    .section .text.init
    .globl _start
    .option norvc

// hazard_elf.S
// - 基於 program/source/hazard.S
// - 加上 riscv-tests 風格的 tohost/fromhost，讓 Verilator+Spike runner 能自動停機並做比對
// - 注意：原本 hazard.S 的 lw 是從低位址(0xC)讀取，Spike 預設 RAM 在 0x8000_0000 會造成存取例外
//   這裡把 x6 設成 0x8000_0000，讓 load 也在 Spike RAM 區間內，才能跟 Spike 做逐字比對。

_start:
    addi   x1, x0, 10    // x1 = 0xa
    addi   x2, x0, 5     // x2 = 0x5
    add    x3, x1, x2    // x3 = 0xf
    sub    x4, x3, x2    // x4 = 0xa
    beq    x1, x4, _NEXT
_NEXT:
    add    x5, x4, x3    // x5 = 0x19

    // Make the load address valid in Spike default memory map (RAM@0x8000_0000)
    lui    x6, 0x80000   // x6 = 0x8000_0000
    lw     x7, 4(x6)     // x7 = *(0x8000_0004)
    add    x8, x6, x7    // x8 = x6 + x7 (load-use hazard)

    // Signal PASS to the test runner (write non-zero to tohost)
    li     gp, 1
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

