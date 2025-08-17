all:
	iverilog -g2012 -Wall -DIVERILOG -I risc-v.srcs/sources_1/new -o simv risc-v.srcs/sources_1/new/tb_riscv_cpu.sv risc-v.srcs/sources_1/new/cpu.sv risc-v.srcs/sources_1/new/clk_wiz_0_stub.sv

# Build program/main_prog.hex from program/source/main.S with comments
.PHONY: mainhex
mainhex: program/main_prog.hex

program/%_prog.hex: program/source/%.S scripts/asm_to_hex.py
	python3 scripts/asm_to_hex.py --input $< --output $@

test: all
	vvp ./simv +HEX=program/lw_prog.hex +EXP=program/lw.exp +CASE=lw
	vvp ./simv +HEX=program/hazard_prog.hex +EXP=program/hazard.exp +CASE=hazard
	vvp ./simv +HEX=program/jal_prog.hex +EXP=program/jal.exp +CASE=jal +FORBID_RD=3 +EXPECT_REG=2:0x0000000c
	vvp ./simv +HEX=program/sum1to10_prog.hex +EXP=program/sum1to10.exp +CASE=sum1to10

clean:
	rm -f simv

# Parametric single test run: make run TEST=<name>
# expects program/<name>_prog.hex and optional program/<name>.exp
run:
	vvp ./simv +HEX=program/$(TEST)_prog.hex +EXP=program/$(TEST).exp +CASE=$(TEST)

# Run all tests that have *_prog.hex in program/ and matching .exp files if present
test-all:
	@set -e; for f in program/*_prog.hex; do \
	  n=$${f##*/}; n=$${n%_prog.hex}; \
	  echo "== $$n =="; \
	  if [ -f program/$$n.exp ]; then \
	    vvp ./simv +HEX=$$f +EXP=program/$$n.exp +CASE=$$n; \
	  else \
	    vvp ./simv +HEX=$$f +CASE=$$n; \
	  fi; \
	done