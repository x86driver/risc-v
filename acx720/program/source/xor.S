_start:
    addi x1, x0, 1
    addi x2, x0, 2
    xor x3, x1, x2

    // 基本交換律與自 XOR 為零
    xor x4, x2, x1
    xor x5, x1, x1

    // 全 1 與 0/1 的 XOR
    addi x6, x0, -1
    xor x7, x6, x0
    xor x8, x6, x1

    // 高位測試：0x80000000 與 0x7fffffff
    lui x9, 0x80000
    lui x10, 0x80000
    addi x10, x10, -1
    xor x11, x9, x10
    xor x12, x11, x10

    // 低位模式：0xaa 與 0x55
    addi x13, x0, 0xaa
    addi x14, x0, 0x55
    xor x13, x13, x14
    xor x15, x13, x13

    // 隨機高低位混合
    lui x16, 0x12345
    addi x16, x16, 0x678
    lui x17, 0x0fedc
    addi x17, x17, 0x7ff
    addi x17, x17, 0x3aa
    xor x18, x16, x17

end:
    jal x0, end
