    .section .text.init
    .globl _start
    .option norvc

// - 本 repo 的 runner 會在第一次「寫入非 0 的 tohost」時停止比對：
//   我們一律在結尾寫 tohost=1，真正 PASS/FAIL 由 Spike-vs-DUT 的 log + signature 比對決定。

_start:
    la  x1, tohost
    la  x2, data1

    li  x3, 0x99
    sb  x3, 0(x2)

    li  x3, 0x88
    sb  x3, 1(x2)

    li  x3, 0x77
    sb  x3, 2(x2)

    li  x3, 0x66
    sb  x3, 3(x2)

    li  x3, 0x1122
    sh  x3, 0(x2)

    li  x3, 0x3344
    sh  x3, 2(x2)

    # tohost：一律寫 1（runner 以「第一次寫非 0」來截斷 Spike log）
    li   x5, 1
    sw   x5, 0(x1)

end:
    j end



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
data1:
    .word 0x5a5a5a5a
data2:
    .word 0xaabbccdd
    .globl end_signature
end_signature:
