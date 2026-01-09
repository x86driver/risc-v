    .section .text.init
    .globl _start
    .option norvc

// misaligned_sw_elf.S
// - RV32I: Misaligned SW 應觸發例外 (mcause=6)
// - 本 repo 的 runner 會在第一次「寫入非 0 的 tohost」時停止比對：
//   我們一律在結尾寫 tohost=1，真正 PASS/FAIL 由 Spike-vs-DUT 的 log + signature 比對決定。

_start:
    la  x1, tohost             # x1 = tohost base
    la  x2, trap_count         # x2 = signature base
    li  x31, 0                 # fail_bits accumulator (recorded to signature at end)

    # signature init
    sw  x0, 0(x2)              # trap_count = 0
    sw  x0, 4(x2)              # fail_bits_sig = 0
    sw  x0, 8(x2)              # last_mcause = 0
    sw  x0, 12(x2)             # last_mepc = 0
    sw  x0, 16(x2)             # last_mtval = 0

    # install mtvec (direct mode)
    la   x17, trap_handler
    csrrw x0, mtvec, x17

    # ------------------------------------------------------------
    # Test0: misaligned LW must trap
    # ------------------------------------------------------------
    la   x19, misaligned_sw_site # expected mepc
    la   x20, after_misaligned   # return pc
    li   x21, 4                  # expected mcause: Load address misaligned
    li   x22, 0x1                # fail mask (bit0)
    mv   x23, x3                 # expected mtval (faulting address)

misaligned_sw_site:
    la   x3, data1
    addi x4, x3, -1             # misaligned address (data1 - 1) and forwarding
    sw   x4, 0(x4)              # should trap
    # 若跑到這裡，代表沒有 trap
    ori  x31, x31, 0x1
    j    after_misaligned

after_misaligned:
    # 把 fail_bits 寫到 signature，方便 runner 比對/除錯
    sw   x31, 4(x2)

    # tohost：一律寫 1（runner 以「第一次寫非 0」來截斷 Spike log）
    li   x5, 1
    sw   x5, 0(x1)

end:
    j end

# ----------------------------
# Trap handler (Direct mode)
# ----------------------------
trap_handler:
    # trap_count++
    lw   x5, 0(x2)
    addi x5, x5, 1
    sw   x5, 0(x2)

    # read mcause / mepc / mtval
    csrrs x6, mcause, x0
    csrrs x7, mepc, x0
    csrrs x8, mtval, x0

    # record for signature/debug
    sw   x6, 8(x2)
    sw   x7, 12(x2)
    sw   x8, 16(x2)

    # compare expected mcause/mepc/mtval
    bne  x6, x21, trap_fail
    bne  x7, x19, trap_fail
    bne  x8, x23, trap_fail
    j    trap_return

trap_fail:
    or   x31, x31, x22

trap_return:
    # 強制返回到預設 return pc，並跳過 faulting instruction
    csrrw x0, mepc, x20
    mret


    .section .tohost, "aw", @progbits
    .align 6
    .globl tohost
tohost:
    .dword 0
    .globl fromhost
fromhost:
    .dword 0

    .section .signature, "aw", @progbits
    .align 2
    .globl begin_signature
begin_signature:
trap_count:
    .word 0
fail_bits_sig:
    .word 0
last_mcause:
    .word 0
last_mepc:
    .word 0
last_mtval:
    .word 0
data1:
    .word 0x5a5a5a5a
    .globl end_signature
end_signature:
