    .section .text.init
    .globl _start
    .option norvc

// illegal-csr_elf.S
// - 基於 program/source/illegal-csr.S
// - 改成 riscv-tests/tohost 風格：最後寫 tohost 讓 runner 自動停機並與 Spike 逐字比對
// - trap_count / fail_bits 放到 .signature 區間，順便驗證 signature dump + 比對

_start:
    la  x1, tohost             # x1 = tohost base
    la  x2, trap_count         # x2 = signature base (trap_count)
    li  x31, 0                 # fail_bits

    # trap_count = 0, fail_bits_sig = 0
    sw  x0, 0(x2)
    sw  x0, 4(x2)

    # 安裝 mtvec
    la  x17, trap_handler
    csrrw x0, mtvec, x17

    # ------------------------------------------------------------
    # Test0: CSRRW single-issue 檢查
    # ------------------------------------------------------------
    li   x5, 0
    csrrw x0, mstatus, x5
    li   x6, 0x123
    csrrw x7, mstatus, x6     # x7 = old mstatus, expect 0
    bne  x7, x0, t0_fail

t0_done:
    # ------------------------------------------------------------
    # Test1: ECALL 必須 trap
    # ------------------------------------------------------------
    la  x19, ecall_site        # expected mepc
    la  x20, after_ecall       # return pc
    li  x21, 11                # expected mcause (M-mode ecall)
    li  x22, 0x2               # fail mask (bit1)

ecall_site:
    ecall
    # 若跑到這裡，代表沒有 trap
    ori x31, x31, 0x2
    j   after_ecall

after_ecall:
    # ------------------------------------------------------------
    # Test2: Illegal CSR 必須 trap，且 faulting inst 不得寫回 rd（x10）
    # ------------------------------------------------------------
    li  x10, 0x55
    la  x19, illegal_csr_site
    la  x20, after_illegal_csr
    li  x21, 2
    li  x22, 0x4               # fail mask (bit2)

illegal_csr_site:
    .align 2
    .word 0x99901573           # csrrw x10, 0x999, x0   (CSR=0x999 必定非法)
    # 若跑到這裡，代表沒有 trap
    ori x31, x31, 0x4
    j   after_illegal_csr

after_illegal_csr:
    li  x5, 0x55
    bne x10, x5, t2_rd_fail

t2_done:
    # ------------------------------------------------------------
    # Test3: Illegal SYSTEM encoding（opcode=0x73, funct3=000, 非 ecall/mret）
    # 也必須 trap，且不得寫回 rd（x11）
    # ------------------------------------------------------------
    li  x11, 0x66
    la  x19, illegal_sys_site
    la  x20, after_illegal_sys
    li  x21, 2
    li  x22, 0x8               # fail mask (bit3)

illegal_sys_site:
    .align 2
    .word 0x7FF005F3           # illegal SYSTEM encoding (rd=x11, funct3=000, opcode=0x73)
    # 若跑到這裡，代表沒有 trap
    ori x31, x31, 0x8
    j   after_illegal_sys

after_illegal_sys:
    li  x5, 0x66
    bne x11, x5, t3_rd_fail

t3_done:
    # ------------------------------------------------------------
    # Test4: trap_count 應該剛好是 3
    # ------------------------------------------------------------
    lw  x6, 0(x2)
    li  x7, 3
    bne x6, x7, t4_trap_count_fail

done:
    # 把 fail_bits 也寫到 signature，方便 runner dump/比對
    sw   x31, 4(x2)

    # tohost：一律寫 1（PASS），避免 Spike 因為「非 1 的 tohost」直接以非 0 exit code 結束，
    # 造成 runner 無法取得 log。
    # 真正的 pass/fail 仍由 Spike-vs-DUT 的逐字比對 + signature 比對決定。
    li   x5, 1
    sw   x5, 0(x1)

end:
    j end

# ----------------------------
# Fail handlers
# ----------------------------
t0_fail:
    ori x31, x31, 0x1
    j   t0_done

t2_rd_fail:
    ori x31, x31, 0x4
    j   t2_done

t3_rd_fail:
    ori x31, x31, 0x8
    j   t3_done

t4_trap_count_fail:
    ori x31, x31, 0x10
    j   done

# ----------------------------
# Trap handler (Direct mode)
# ----------------------------
trap_handler:
    # trap_count++
    lw   x5, 0(x2)
    addi x5, x5, 1
    sw   x5, 0(x2)

    # 讀 mcause / mepc
    csrrs x6, mcause, x0
    csrrs x7, mepc, x0
    nop
    nop

    # 比對 mcause / mepc
    bne  x6, x21, trap_fail
    bne  x7, x19, trap_fail

trap_return:
    # 強制返回到預設 return pc
    csrrw x0, mepc, x20
    nop
    nop
    mret

trap_fail:
    or   x31, x31, x22
    j    trap_return

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
    .globl end_signature
end_signature:

