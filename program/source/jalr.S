_start:
    addi x1, x0, 1
    jal x2, L1
    addi x4, x0, 4
end:
    jal x0, end

L1:
    addi x3, x0, 3
    jalr x0, x2, 0