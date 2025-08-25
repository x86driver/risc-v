.PHONY: all
all: simv

simv: risc-v.srcs/sources_1/new/tb_riscv_cpu.sv risc-v.srcs/sources_1/new/cpu.sv risc-v.srcs/sources_1/new/clk_wiz_0_stub.sv
	iverilog -g2012 -Wall -DIVERILOG -I risc-v.srcs/sources_1/new -o $@ $^

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

# Concise single test run: make run-quiet TEST=<name>
# Prints one line: "RESULT <name> PASS" or "RESULT <name> FAIL <n>"
.PHONY: run-quiet
run-quiet:
	make -s all
	make -s program/hex/$(TEST)_prog.hex
	@out=$$(vvp ./simv +HEX=program/hex/$(TEST)_prog.hex +EXP=program/exp/$(TEST).exp +CASE=$(TEST) +QUIET +SUMMARY | tail -n 2); \
	 echo "$$out" | grep "RESULT"; \
	 echo "$$out" | grep -q "RESULT $(TEST) PASS"

# Run all tests and print per-test PASS/FAIL summary
.PHONY: test-summary
test-summary: all build-hex-all
	@pass=0; fail=0; \
	for f in program/hex/*_prog.hex; do \
	  n=$${f##*/}; n=$${n%_prog.hex}; \
	  if make -s run-quiet TEST=$$n; then \
	    pass=$$((pass+1)); \
	  else \
	    fail=$$((fail+1)); \
	  fi; \
	done; \
	echo ""; \
	echo "Summary: PASS=$$pass FAIL=$$fail TOTAL=$$((pass+fail))"; \
	test $$fail -eq 0

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
	  if [ -n "$(V)" ]; then \
	    echo "== $$n =="; \
	    $(MAKE) program/hex/$${n}_prog.hex; \
	  else \
	    $(MAKE) -s program/hex/$${n}_prog.hex >/dev/null; \
	  fi; \
	done
