    .section .text
    .globl _start

#
# csr-2.S
# - 驗證 Zicsr「rs1/zimm=0 → 只讀不寫」語意（CSRRS/CSRRC/CSRRSI/CSRRCI）
# - 驗證 CSR write->read 同位址 RAW hazard 需要 stall（從 log 可看到 [CSR hazard]）
#
# Pass 條件：
# - 讀回 mtvec 的值必須等於剛寫入的新值（代表 stall 生效）
# - 其他 CSR 讀值為 0（未觸發 trap）
#
# 注意：本測試也刻意安排了多組「連續兩條只讀 CSR 指令」，
# 若控制單元錯把它們當成 CSR write，log 會額外出現
#   id_csr=342 / id_csr=343 的 [CSR hazard] STALL 訊息。
#

_start:
    addi x3, x0, 0          # fail_bits = 0

    # ------------------------------------------------------------
    # Test1: CSR write -> CSR read (same CSR) must stall
    # mtvec initial = 0xDEAD_BEEF; write mtvec=0x80 then read back into x2
    # Expect: x2 == 0x80
    # Log should include: [CSR hazard] ... id_csr=305 ...
    # ------------------------------------------------------------
    addi  x1, x0, 0x80      # new mtvec (aligned)
    csrrw x0, mtvec, x1
    csrrs x2, mtvec, x0     # read-only; must stall behind CSRRW
    addi  x4, x0, 0x80
    bne   x2, x4, t1_fail

    # ------------------------------------------------------------
    # Test2: CSRRS (rs1=x0) is read-only => should NOT be treated as CSR write
    # Back-to-back CSRRS on mcause (0x342). Expect x5 == 0.
    # Log should NOT include: id_csr=342 conflicts ...
    # ------------------------------------------------------------
    csrrs x0, mcause, x0
    csrrs x5, mcause, x0
    bne   x5, x0, t2_fail

    # ------------------------------------------------------------
    # Test3: CSRRSI (zimm=0) is read-only => should NOT be treated as CSR write
    # Back-to-back CSRRSI on mtval (0x343). Expect x6 == 0.
    # Log should NOT include: id_csr=343 conflicts ...
    # ------------------------------------------------------------
    csrrsi x0, mtval, 0
    csrrsi x6, mtval, 0
    bne    x6, x0, t3_fail

    # ------------------------------------------------------------
    # Test4: CSRRC (rs1=x0) is read-only => should NOT be treated as CSR write
    # Back-to-back CSRRC on mtval (0x343). Expect x7 == 0.
    # ------------------------------------------------------------
    csrrc x0, mtval, x0
    csrrc x7, mtval, x0
    bne   x7, x0, t4_fail

    # ------------------------------------------------------------
    # Test5: CSRRCI (zimm=0) is read-only => should NOT be treated as CSR write
    # Back-to-back CSRRCI on mcause (0x342). Expect x8 == 0.
    # ------------------------------------------------------------
    csrrci x0, mcause, 0
    csrrci x8, mcause, 0
    bne    x8, x0, t5_fail

pass:
pass_loop:
    jal x0, pass_loop

t1_fail:
    ori x3, x3, 0x1
    jal x0, pass

t2_fail:
    ori x3, x3, 0x2
    jal x0, pass

t3_fail:
    ori x3, x3, 0x4
    jal x0, pass

t4_fail:
    ori x3, x3, 0x8
    jal x0, pass

t5_fail:
    ori x3, x3, 0x10
    jal x0, pass