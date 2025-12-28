    .section .text
    .globl _start

_start:
    .equ LED_BASE, 0x710
    .equ RAM_BASE, 0x000

    li  x1, LED_BASE
    li  x2, RAM_BASE

    # 進度標記：0x40
    li  x3, 0x40
    sw  x3, 0(x1)

    # ------------------------------------------------------------
    # 1) 製造 memory stall + load-use hazard（測試 stage_valid 在 stall 時是否 hold）
    # ------------------------------------------------------------
    li  x4, 0x12345678
    sw  x4, 0(x2)
    lw  x5, 0(x2)
    addi x6, x5, 1            # 立刻使用 x5：會觸發 load-use hazard

    # ------------------------------------------------------------
    # 2) 製造 control flush（jal 會在 EX 造成 if_Flush/id_Flush）
    # ------------------------------------------------------------
    jal x0, after_flush
    addi x7, x0, 0x777        # 這行理論上應被 flush 掉（不重要，只是提供觀察點）

after_flush:
    # ------------------------------------------------------------
    # 3) 0x73：寫 mtvec（SYSTEM/CSR 指令）
    # ------------------------------------------------------------
    la  x8, trap_handler
    csrw mtvec, x8
    csrrs x9, mtvec, x0       # 再讀回，讓 CSR 路徑也走一次

    # 進度標記：0x41
    li  x3, 0x41
    sw  x3, 0(x1)

end:
    j end

trap_handler:
    # 如果真的進來 trap（本測試預期不會），就亮 0x99
    li  x1, LED_BASE
    li  x3, 0x99
    sw  x3, 0(x1)
    j trap_handler