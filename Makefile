.PHONY: all
all: simv

SIMV_SRCS = \
	risc-v.srcs/sources_1/new/tb_riscv_cpu.sv \
	risc-v.srcs/sources_1/new/cpu.sv \
	risc-v.srcs/sources_1/new/clk_wiz_0_stub.sv

SIMV_DEPS = $(SIMV_SRCS) risc-v.srcs/sources_1/new/axi_uartlite_simple.sv

simv: $(SIMV_DEPS)
	iverilog -g2012 -Wall -DIVERILOG -I risc-v.srcs/sources_1/new -o $@ $(SIMV_SRCS)

# Build program/main_prog.hex from program/source/main.S with comments
.PHONY: mainhex
mainhex: program/main_prog.hex

program/hex/%_prog.hex: program/source/%.S scripts/asm_to_hex.py
	python3 scripts/asm_to_hex.py --input $< --output $@

# -------------------------------------------------------------------
# Build simple "tohost" ELFs from program/source/*_elf.S for Spike-compare flow
# -------------------------------------------------------------------
# Keep disassembly dumps (GNU make may otherwise treat them as intermediate and delete them)
.PRECIOUS: build/asm-elf/%.dump

build/asm-elf/%.elf: program/source/%_elf.S
	@mkdir -p build/asm-elf
	/opt/riscv/bin/riscv64-unknown-elf-gcc \
	  -march=rv32i_zicsr_zifencei -mabi=ilp32 \
	  -nostdlib -nostartfiles \
	  -Wl,--no-relax -Wl,-e,_start -Wl,-Tprogram/riscv_test.ld \
	  -o $@ $<

build/asm-elf/%.dump: build/asm-elf/%.elf
	/opt/riscv/bin/riscv64-unknown-elf-objdump -d -s -j .text -j .data -M numeric $< > $@

# Generic rules for self-tests (matches hazard-elf, load-elf, etc.)
%-elf: build/asm-elf/%.elf build/asm-elf/%.dump
	@:

%-spike: %-elf
	$(MAKE) riscv-test ELF=build/asm-elf/$*.elf

# Auto-discover all *_elf.S tests
SPIKE_SELFTESTS_SRCS := $(wildcard program/source/*_elf.S)
SPIKE_SELFTESTS := $(patsubst program/source/%_elf.S, %-elf, $(SPIKE_SELFTESTS_SRCS))

.PHONY: spike-selftests
spike-selftests: verilator $(SPIKE_SELFTESTS)
	python3 scripts/run_riscv_tests_suite.py \
	  --dir "$(PWD)/build/asm-elf" \
	  --pattern "*.elf" \
	  --outdir "$(PWD)/build/spike-selftests" \
	  --isa "rv32i" \
	  --spike-max-instructions "$${SPIKE_MAX_INSN:-200000}" \
	  --max-cycles "$${MAX_CYCLES:-200000}" \
	  $$( [ "$${FAIL_FAST:-0}" = "1" ] && echo --fail-fast ) \
	  $$( [ -n "$${LIMIT:-}" ] && echo --limit "$${LIMIT}" )

test: all
	make build-hex-all
	make test-all

.PHONY: uart-hello
uart-hello: risc-v.srcs/sources_1/ip/blk_mem_gen_0/uart-hello_prog.coe

risc-v.srcs/sources_1/ip/blk_mem_gen_0/uart-hello_prog.coe: program/source/uart-hello.S
	/opt/riscv/bin/riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -nostartfiles -Wl,-Ttext=0 -o uart-hello.elf $<
	/opt/riscv/bin/riscv64-unknown-elf-objcopy -O binary uart-hello.elf uart-hello.bin
	python3 scripts/to_coe.py uart-hello.bin > $@

clean:
	rm -f simv
	rm -f program/hex/*_prog.hex
	rm -rf build
	rm -rf obj_dir

# -------------------------------------------------------------------
# Verilator (Spike-compare) flow for riscv-tests-style ELFs
# -------------------------------------------------------------------
.PHONY: verilator
verilator:
	verilator --binary --timing -Wall -Wno-fatal -DIVERILOG -I$(PWD)/rtl \
	  --top-module tb_verilator $(PWD)/sim/tb_verilator.sv -o simv_verilator

.PHONY: riscv-test
# Usage:
#   make riscv-test ELF=rv32ui-p-add
riscv-test: verilator
	@test -n "$(ELF)" || (echo "Usage: make riscv-test ELF=<path-to-elf>"; exit 2)
	@elf_path="$(ELF)"; case "$$elf_path" in /*) ;; *) elf_path="$(PWD)/$$elf_path";; esac; \
	  outdir="$(PWD)/build/riscv-tests"; mkdir -p "$$outdir"; \
	  sections=$$(/opt/riscv/bin/riscv64-unknown-elf-objdump -h "$$elf_path" | awk '/^[[:space:]]*[0-9]+/ {print $$2}' | grep -E '^\.(text(\.init)?|data)$$'); \
	  dump_cmd="/opt/riscv/bin/riscv64-unknown-elf-objdump -d -s -M numeric"; \
	  for s in $$sections; do dump_cmd="$$dump_cmd -j $$s"; done; \
	  $$dump_cmd "$$elf_path" > "$$outdir/$$(basename "$$elf_path").dump" 2>&1 || \
	    /opt/riscv/bin/riscv64-unknown-elf-objdump -d -s -M numeric "$$elf_path" > "$$outdir/$$(basename "$$elf_path").dump"; \
	  python3 scripts/run_riscv_test_compare_spike.py --elf "$$elf_path" --outdir "$$outdir"

.PHONY: riscv-tests
# Usage:
#   make riscv-tests
#   make riscv-tests PATTERN=rv32ui-p-* DIR=/opt/riscv/target/share/riscv-tests/isa
#   make riscv-tests LIMIT=10 FAIL_FAST=1
riscv-tests: verilator
	python3 scripts/run_riscv_tests_suite.py \
	  --dir "$${DIR:-/opt/riscv/target/share/riscv-tests/isa}" \
	  --pattern "$${PATTERN:-rv32ui-p-*}" \
	  --outdir "$(PWD)/build/riscv-tests" \
	  --isa "$${ISA:-rv32i}" \
	  --spike-max-instructions "$${SPIKE_MAX_INSN:-200000}" \
	  --max-cycles "$${MAX_CYCLES:-200000}" \
	  $$( [ "$${FAIL_FAST:-0}" = "1" ] && echo --fail-fast ) \
	  $$( [ -n "$${LIMIT:-}" ] && echo --limit "$${LIMIT}" )

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

.PHONY: run-uart
run-uart:
	make -s all
	make -s program/hex/$(TEST)_prog.hex
	vvp ./simv +HEX=program/hex/$(TEST)_prog.hex +EXP=program/exp/$(TEST).exp +CASE=$(TEST) +QUIET +SUMMARY

# Run all tests and print per-test PASS/FAIL summary
.PHONY: test-summary
test-summary: all build-hex-all
	@pass=0; fail=0; without_exp=0; \
	for f in program/hex/*_prog.hex; do \
	  n=$${f##*/}; n=$${n%_prog.hex}; \
	  res=$$(make -s run-quiet TEST=$$n || true); \
	  echo "$$res"; \
	  if echo "$$res" | grep -q "PASS"; then \
	    pass=$$((pass+1)); \
	  elif echo "$$res" | grep -q "without exp file"; then \
	    without_exp=$$((without_exp+1)); \
	  else \
	    fail=$$((fail+1)); \
	  fi; \
	done; \
	echo ""; \
	echo "Summary: PASS=$$pass FAIL=$$fail WITHOUT_EXP=$$without_exp TOTAL=$$((pass+fail+without_exp))"; \
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
