_start:
    addi x1, x0, 1
    addi x2, x1, 2
    addi x2, x1, 2
    addi x2, x1, 2

    # 以下是 lui rs1 的 forwarding test 測不出來 但可以用來觀察 $display 的結果
    addi x2, x0, 2
    lui x1, 0x10
    lui x3, 0x200

end:
    jal x0, end