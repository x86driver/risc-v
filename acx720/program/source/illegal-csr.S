    .section .text
    .globl _start

    .equ LED_BASE, 0x710
    .equ RAM_BASE, 0x000

# ------------------------------------------------------------
# illegal-csr.S
# 目的：用來驗證你「把所有 0x73(system/CSR) 指令都序列化」後，是否滿足：
#   1) 0x73 不會因為序列化控制而被重複 issue（常見 bug：同一條 0x73 反覆執行）
#   2) 同步陷入（ecall / illegal CSR / illegal SYSTEM encoding）為 precise exception：
#      - mcause / mepc 正確
#      - faulting instruction 不得寫回 rd（不得改變 GPR）
#      - 0x73 funct3==000（非 ecall/mret）也必須能被當成 illegal instruction 處理
#
# 顯示方式：
#   最後 LED(0x710) 會輸出 0x80 | fail_bits
#   - bit0=1：Test0 失敗（CSRRW single-issue 檢查）
#   - bit1=1：Test1 失敗（ECALL：mcause/mepc 或未 trap）
#   - bit2=1：Test2 失敗（Illegal CSR：mcause/mepc/未 trap 或 rd 被改）
#   - bit3=1：Test3 失敗（Illegal SYSTEM encoding：mcause/mepc/未 trap 或 rd 被改）
#   - bit4=1：Test4 失敗（trap 次數不等於 3，代表漏 trap 或重複 trap）
# ------------------------------------------------------------

_start:
    li  x1, LED_BASE
    li  x2, RAM_BASE          # RAM base: 0(x2) 用來存 trap_count
    li  x31, 0                # fail_bits

    # trap_count = 0
    sw  x0, 0(x2)

    # 安裝 mtvec
    la  x17, trap_handler
    csrrw x0, mtvec, x17

    # ------------------------------------------------------------
    # Test0: CSRRW single-issue 檢查
    #   先把 mstatus 設成 0，再用 csrrw 寫入 0x123
    #   期待讀回的舊值為 0。若序列化控制有「重複 issue」bug，
    #   這裡很容易讀到 0x123 而失敗。
    # ------------------------------------------------------------
    li   x5, 0
    csrrw x0, mstatus, x5
    li   x6, 0x123
    csrrw x7, mstatus, x6     # x7 = old mstatus, expect 0
    bne  x7, x0, t0_fail

t0_done:
    # ------------------------------------------------------------
    # Test1: ECALL 必須 trap
    #   期待：
    #     mcause = 11
    #     mepc   = ecall_site
    # ------------------------------------------------------------
    la  x19, ecall_site        # expected mepc
    la  x20, after_ecall       # return pc (handler 會強制寫回 mepc)
    li  x21, 11                # expected mcause
    li  x22, 0x2               # fail mask for this test (bit1)

ecall_site:
    ecall
    # 若跑到這裡，代表沒有 trap
    ori x31, x31, 0x2
    j   after_ecall

after_ecall:
    # ------------------------------------------------------------
    # Test2: Illegal CSR（funct3!=000 且 CSR 位址不支援）必須 trap，
    # 且 faulting instruction 不得寫回 rd（這裡用 x10 測）
    #   期待：
    #     mcause = 2
    #     mepc   = illegal_csr_site
    #     x10    維持 0x55 不變
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
    # 也必須當成 illegal instruction trap，且不得寫回 rd（這裡用 x11 測）
    #   期待：
    #     mcause = 2
    #     mepc   = illegal_sys_site
    #     x11    維持 0x66 不變
    # ------------------------------------------------------------
    li  x11, 0x66
    la  x19, illegal_sys_site
    la  x20, after_illegal_sys
    li  x21, 2
    li  x22, 0x8               # fail mask (bit3)

illegal_sys_site:
    .align 2
    .word 0x7FF005F3           # (imm=0x7FF, rd=x11, funct3=000, rs1=0, opcode=0x73) => 應視為 illegal
    # 若跑到這裡，代表沒有 trap
    ori x31, x31, 0x8
    j   after_illegal_sys

after_illegal_sys:
    li  x5, 0x66
    bne x11, x5, t3_rd_fail

t3_done:
    # ------------------------------------------------------------
    # Test4: trap_count 應該剛好是 3（ecall + illegal csr + illegal sys）
    # 若序列化/控制有 bug，可能會漏 trap 或重複 trap。
    # ------------------------------------------------------------
    lw  x6, 0(x2)
    li  x7, 3
    bne x6, x7, t4_trap_count_fail

done:
    addi x5, x31, 0x80
    sw   x5, 0(x1)

end:
    j end

# ----------------------------
# Fail handlers (回到流程繼續跑)
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
# - 讀 mcause/mepc 與預期值比較，不符就 OR fail_bits
# - 強制把 mepc 寫成 x20，然後 mret
# - 同時維護 trap_count（RAM[0]）
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
    # 強制返回到預設 return pc（避免 mepc 被錯誤覆蓋導致亂跳）
    csrrw x0, mepc, x20
    nop
    nop
    mret

trap_fail:
    or   x31, x31, x22
    j    trap_return
