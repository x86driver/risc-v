#!/usr/bin/env bash
#
# Simple script to run tb_bram testbench in Vivado XSim
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VIVADO_PATH="${HOME}/tools/Xilinx/2025.2/Vivado"

# Add Vivado to PATH
export PATH="${VIVADO_PATH}/bin:$PATH"

# Create working directory
WORK_DIR="${PROJECT_DIR}/build/tb_bram"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo "=== Compiling BRAM testbench ==="

# Generate BRAM IP simulation model if not exists
BRAM_SIM="${PROJECT_DIR}/risc-v.gen/sources_1/ip/blk_mem_gen_0/sim/blk_mem_gen_0.v"
if [ ! -f "$BRAM_SIM" ]; then
    echo "BRAM simulation model not found. Generating IP outputs..."
    vivado -mode batch -nojournal -nolog -source - <<'EOF'
open_project /home/shane/pro/fpga/risc-v/risc-v.xpr
generate_target simulation [get_ips blk_mem_gen_0]
close_project
EOF
fi

# Copy or create mif file for BRAM initialization
MIF_SRC="${PROJECT_DIR}/risc-v.sim/sim_1/behav/xsim/xsim/blk_mem_gen_0.mif"
if [ -f "$MIF_SRC" ]; then
    cp "$MIF_SRC" "$WORK_DIR/"
    echo "Copied existing mif file"
else
    # Create empty mif file (BRAM will initialize to 0)
    echo "// Empty MIF file for simulation" > "$WORK_DIR/blk_mem_gen_0.mif"
    echo "Created empty mif file"
fi

# Create xvlog project file
cat > vlog.prj <<EOF
sv xil_defaultlib "${PROJECT_DIR}/sim/tb_bram.sv"
verilog xil_defaultlib "${PROJECT_DIR}/risc-v.gen/sources_1/ip/blk_mem_gen_0/sim/blk_mem_gen_0.v"
EOF

# Compile
xvlog --incr --relax -prj vlog.prj 2>&1 | tee compile.log
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "ERROR: Compilation failed!"
    exit 1
fi

echo "=== Elaborating ==="
xelab --incr --debug typical --relax --mt 24 \
    -L xil_defaultlib -L blk_mem_gen_v8_4_12 -L unisims_ver -L secureip \
    --snapshot tb_bram xil_defaultlib.tb_bram -log elaborate.log 2>&1 | tee -a elaborate.log
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "ERROR: Elaboration failed!"
    exit 1
fi

echo "=== Running simulation ==="
# Create tcl command file
cat > cmd.tcl <<EOF
run all
quit
EOF

xsim tb_bram -tclbatch cmd.tcl -log simulate.log 2>&1 | tee simulate_output.log

echo ""
echo "=== Simulation Complete ==="
echo "Logs saved in: $WORK_DIR"
