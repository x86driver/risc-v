    .section .text.init
    .globl _start
    .option norvc

// fence_i_elf.S
// 目的：
// - 測 self-modifying code + fence.i 行為（Zifencei）
// - 在 Spike（unified memory + fence.i）應該 PASS
// - 若 CPU 使用 Harvard instruction/data memory 且未做 I$ coherence，通常會 FAIL
//
// PASS: gp=1 -> tohost
// FAIL: gp=2 -> tohost

_start:
    # Call once: a0 should become 0
    jal   ra, patch_site

    # Patch the first instruction at patch_site to "addi a0, x0, 1" (0x00100513)
    la    t0, patch_site
    li    t1, 0x00100513
    sw    t1, 0(t0)

    # Ensure instruction stream sees the update
    fence.i

    # Call again: a0 should become 1 on correct implementations
    jal   ra, patch_site
    li    t2, 1
    bne   a0, t2, fail

pass:
    li    gp, 1
    j     write_tohost

fail:
    li    gp, 2

write_tohost:
    la    t3, tohost
    sw    gp, 0(t3)
1:
    j 1b

    .align 2
patch_site:
    addi  a0, x0, 0          # will be patched to addi a0, x0, 1
    jalr  x0, ra, 0

    .section .tohost, "aw", @progbits
    .align 6
    .globl tohost
tohost:
    .dword 0
    .globl fromhost
fromhost:
    .dword 0

