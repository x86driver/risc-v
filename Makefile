all:
	iverilog -g2012 -Wall -DIVERILOG -I risc-v.srcs/sources_1/new -o simv risc-v.srcs/sources_1/new/tb_riscv_cpu.sv risc-v.srcs/sources_1/new/cpu.sv risc-v.srcs/sources_1/new/clk_wiz_0_stub.sv

test:
	vvp ./simv +HEX=program/lw_prog.hex +CASE=lw
	vvp ./simv +HEX=program/hazard_prog.hex +CASE=hazard

clean:
	rm -f simv