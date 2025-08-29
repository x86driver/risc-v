# 本專案 RISC-V CPU 支援的指令集

## 支援的指令列表

### R-Type 指令（暫存器運算）
| 指令 | 操作碼 | funct3 | funct7 | 說明 |
|------|--------|--------|--------|------|
| ADD  | 0110011 | 000 | 0000000 | 暫存器加法：rd = rs1 + rs2 |
| SUB  | 0110011 | 000 | 0100000 | 暫存器減法：rd = rs1 - rs2 |
| AND  | 0110011 | 111 | 0000000 | 暫存器位元 AND：rd = rs1 & rs2 |
| OR   | 0110011 | 110 | 0000000 | 暫存器位元 OR：rd = rs1 \| rs2 |
| XOR  | 0110011 | 100 | 0000000 | 暫存器 XOR: rd = rs1 ^ rs2 |
| SLL  | 0110011 | 001 | 0000000 | 暫存器 Shift Left Logical: rd = rs1 << rs2[4:0] |
| SRL  | 0110011 | 101 | 0000000 | 暫存器 Shift Right Logical: rd = rs1 >> rs2[4:0] |
| SRA  | 0110011 | 101 | 0100000 | 暫存器 Shift Right Arith: rd = rs1 >> rs2[4:0] msb-extends |
| SLT  | 0110011 | 010 | 0000000 | 暫存器 Set Less Than: rd = (rs1 < rs2) ? 1 : 0 |
| SLTU | 0110011 | 011 | 0000000 | 暫存去 Set Less Than (U): rd = (rs1 < rs2) ? 1 : 0 zero-extends |

### I-Type 指令（立即數運算）
| 指令 | 操作碼 | funct3 | 說明 |
|------|--------|--------|------|
| ADDI | 0010011 | 000 | 立即數加法：rd = rs1 + imm |
| XORI | 0010011 | 100 | 立即數 XOR: rd = rs1 ^ imm |
| ANDI | 0010011 | 111 | 立即數位元 AND：rd = rs1 & imm |
| ORI  | 0010011 | 110 | 立即數位元 OR：rd = rs1 \| imm |
| SLLI | 0010011 | 001 | 立即數 Shift Left Logical Imm: rd = rs1 << imm[0:4] imm[5:11]=0x00 |
| JALR | 1100111 | 000 | rd = PC + 4; PC = rs1 + imm |

### Load/Store 指令
| 指令 | 操作碼 | funct3 | 說明 |
|------|--------|--------|------|
| LW   | 0000011 | 010 | 載入字組：rd = mem[rs1 + imm] |
| SW   | 0100011 | 010 | 儲存字組：mem[rs1 + imm] = rs2 |

### 分支指令
| 指令 | 操作碼 | funct3 | 說明 |
|------|--------|--------|------|
| BEQ  | 1100011 | 000 | 相等則分支：if (rs1 == rs2) PC = PC + imm |
| BNE  | 1100011 | 001 | 不相等則分支：if (rs1 != rs2) PC = PC + imm |

### 跳躍指令
| 指令 | 操作碼 | 說明 |
|------|--------|------|
| JAL  | 1101111 | 跳躍並連結：rd = PC + 4; PC = PC + imm |

### U-Type 指令（高位立即數）
| 指令 | 操作碼 | 說明 |
|------|--------|------|
| LUI   | 0110111 | 載入高位立即數：rd = imm << 12 |
| AUIPC | 0010111 | PC 加高位立即數：rd = PC + (imm << 12) |

## 實作細節

### 1. ALU 運算單元
- 支援 4 種基本運算：AND、OR、ADD、SUB
- 運算控制由 ALU control 單元根據 ALUOp、funct3 和 isSub 訊號決定

### 2. 記憶體存取
- 支援 32 位元字組的讀寫操作
- 記憶體地址計算：base address (rs1) + sign-extended immediate

### 3. 分支預測與控制
- 在 EX 階段進行分支判斷
- 支援分支預測失敗時的 pipeline flush 機制
- JAL 指令在 EX 階段計算跳躍目標地址

### 4. 立即數產生
- I-Type：12 位元有號擴展
- S-Type：12 位元有號擴展（由 inst[31:25] 和 inst[11:7] 組成）
- B-Type：13 位元有號擴展（用於分支偏移）
- U-Type：20 位元左移 12 位
- J-Type：21 位元有號擴展（用於 JAL）

## 注意事項
- 所有指令都是 32 位元寬度
- 支援 32 個通用暫存器（x0-x31），其中 x0 固定為 0
- 採用 5 階段 pipeline：IF → ID → EX → MEM → WB
- 實作了 data forwarding 和 hazard detection 機制

## 尚未支援的指令

srli
srai
slti
sltiu

lb
lh
lbu
lhu

sb
sh

blt
bge
bltu
bgeu

ecall
ebreak
fence
fence.i
csrrw
csrrs
csrrc
csrrwi
csrrsi
csrrci
