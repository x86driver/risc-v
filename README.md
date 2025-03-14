要做的:
- [x] 讀寫 ram 的位址需要對齊 128 bits 嗎？ (好像是)
- [x] wraddr, araddr 要修正

現在讀寫 leds 模擬看起來正確 要放在板子上試試
還要跑原本 ddr3 的讀寫測試 因為改了 address_decoder 的邏輯
uart 可能也要跑

用這種方式產生的 可以得到正確的 auipc 位址
```bash
riscv64-linux-gnu-gcc -march=rv32i -mabi=ilp32 -nostdlib -fno-pic -g -o lw.o lw.S
```

auipc 要做的:
- [x] 實作指令
- [ ] 搬移 PC (包含 instruction memory)

0ecaffc43ce1bb6ee854de56fe76a1e3e042152a
測試是正確: 分開測試EX/MEM hazard、MEM/WB hazard 與 load-use hazar


uart 目前測試是 write_done 只會有一拍 看起來是正確的

接下來要做的:
- [ ] 把 uart/led 搬到更高的 address
- [ ] 在板子上測試 ddr3/uart/led
- [ ] 實作 jal 指令
- [ ] 把 ddr3_ram.sv 的 clk 拿掉, 直接傳 clk_50 進去

- [ ] instruction memory 要換成 ddr3


```bash
docker run -it -v ~/pro/riscv:/pro/riscv ubuntu:24.04
apt update
apt install gcc-riscv64-linux-gnu less
riscv64-linux-gnu-gcc -march=rv32i -mabi=ilp32 -g -c -o lw.32 lw.S
riscv64-linux-gnu-objdump -S lw.32|less
```

vivado:
~/pro/fpga/xilinx-docker$ ./run.sh
cd /xilinx/
. tools/Xilinx/Vivado/2024.2/settings64.sh
./run.sh