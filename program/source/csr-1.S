    .section .text
    .globl _start

    .equ LED_BASE, 0x710
    .equ RAM_BASE, 0x000

# 這支程式包含兩個測試，都是為了驗證「hazard_stall 時插入的 bubble 必須真的把 ID/EX 變成 NOP」。
# 若你把 CPU 裡的 id_Flush_final 拿掉（只靠清部份控制訊號），下面兩個測試都可能失敗。
#
# 顯示方式：最後 LED(0x710) 會輸出 0x10 | fail_bits
# - bit0=1：Test1（lw → beq 的 load-use hazard）失敗
# - bit1=1：Test2（csrrw mepc 緊貼 ecall 的序列化）失敗
# 例：
# - 0x10：兩個都通過（理想）
# - 0x11：只有 Test1 失敗
# - 0x12：只有 Test2 失敗
# - 0x13：兩個都失敗

_start:
    li  x1, LED_BASE
    li  x31, 0            # fail_bits

    # ------------------------------------------------------------
    # Test1: load-use + beq
    # lw 後立刻 beq 使用 x4。
    # 正確：beq 應延後 1 拍，看到 x4=1，所以 NOT taken。
    # 錯誤(沒把 bubble 變 NOP)：beq 可能提早進 EX，用舊 x4=0 比較而誤跳。
    # ------------------------------------------------------------
    li  x2, RAM_BASE
    li  x3, 1
    sw  x3, 0(x2)

    addi x4, x0, 0
    lw  x4, 0(x2)
    beq x4, x0, t1_fail

t1_done:
    # ------------------------------------------------------------
    # Test2: CSR write (mepc) 緊貼 ecall
    # 先用 csrrw 把 mepc 寫成 bad_return 的位址，然後立刻 ecall。
    # stall_unit 會嘗試把 ecall 序列化（等前面 CSR write 退休）。
    # 若 bubble 沒變成 NOP，ecall 可能在 stall 當下被送進 EX 觸發 trap，
    # 接著舊的 csrrw(me pc) 會在之後的 WB 覆蓋掉 trap-entry 寫入的 mepc。
    # trap handler 讀到的 mepc 就會不是 ecall_site。
    # ------------------------------------------------------------
    la  x17, trap_handler
    csrrw x0, mtvec, x17

    la  x18, bad_return    # 故意寫進 mepc 的錯誤返回位址
    la  x19, ecall_site    # 期望 trap-entry 寫入的 mepc（= ecall 指令位址）
    la  x20, after_ecall   # trap handler 強制返回的位址

    csrrw x0, mepc, x18

ecall_site:
    ecall

after_ecall:
    addi x5, x31, 0x10
    sw   x5, 0(x1)

end:
    j end

# --- Test1 fail 路徑 ---
t1_fail:
    ori x31, x31, 0x1
    j   t1_done

# --- 若 mret 真的跳到這裡（不應該發生），也算 Test2 fail ---
bad_return:
    ori x31, x31, 0x2
    j   after_ecall

# --- Trap handler ---
trap_handler:
    # 讀 mepc，若不是 ecall_site => Test2 fail
    csrrs x6, mepc, x0
    nop
    nop
    bne  x6, x19, t2_fail

t2_done:
    # 強制返回到 after_ecall（避免 mepc 被錯誤覆蓋導致亂跳）
    csrrw x0, mepc, x20
    nop
    nop
    mret

t2_fail:
    ori  x31, x31, 0x2
    j    t2_done
