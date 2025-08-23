all:
	iverilog -g2012 -Wall -DIVERILOG -I risc-v.srcs/sources_1/new -o simv risc-v.srcs/sources_1/new/tb_riscv_cpu.sv risc-v.srcs/sources_1/new/cpu.sv risc-v.srcs/sources_1/new/clk_wiz_0_stub.sv

# Build program/main_prog.hex from program/source/main.S with comments
.PHONY: mainhex
mainhex: program/main_prog.hex

program/hex/%_prog.hex: program/source/%.S scripts/asm_to_hex.py
	python3 scripts/asm_to_hex.py --input $< --output $@

test: all
	make build-hex-all
	make test-all

clean:
	rm -f simv
	rm -f program/hex/*_prog.hex

# Parametric single test run: make run TEST=<name>
# expects program/<name>_prog.hex and optional program/<name>.exp
# will build the program if it doesn't exist
run:
	make all
	make program/hex/$(TEST)_prog.hex
	vvp ./simv +HEX=program/hex/$(TEST)_prog.hex +EXP=program/exp/$(TEST).exp +CASE=$(TEST)

# Run all tests that have *_prog.hex in program/ and matching .exp files if present
test-all:
	@set -e; for f in program/hex/*_prog.hex; do \
	  n=$${f##*/}; n=$${n%_prog.hex}; \
	  echo "== $$n =="; \
	  make run TEST=$$n; \
	done

build-hex-all:
	@set -e; for f in program/source/*.S; do \
	  n=$${f##*/}; n=$${n%.S}; \
	  echo "== $$n =="; \
	  make program/hex/$${n}_prog.hex; \
	done
