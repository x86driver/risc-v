#!/usr/bin/env bash
#
# Script to run tb_bram testbench with true_dual_port_bram using Vivado XSim
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VIVADO_PATH="${HOME}/tools/Xilinx/2025.2/Vivado"

# Add Vivado to PATH
export PATH="${VIVADO_PATH}/bin:$PATH"

# Source files
TB_FILE="${PROJECT_DIR}/sim/tb_bram.sv"
DUT_FILE="${PROJECT_DIR}/rtl/true_dual_port_bram.sv"

# Verify source files exist
if [ ! -f "$TB_FILE" ]; then
    echo "ERROR: Testbench not found: $TB_FILE"
    exit 1
fi
if [ ! -f "$DUT_FILE" ]; then
    echo "ERROR: DUT not found: $DUT_FILE"
    exit 1
fi

# Create working directory
WORK_DIR="${PROJECT_DIR}/build/tb_true_dual_port_bram"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo "=== Compiling true_dual_port_bram testbench ==="
echo "  Testbench: $TB_FILE"
echo "  DUT:       $DUT_FILE"
echo ""

# Create xvlog project file
cat > vlog.prj <<EOF
sv work "$DUT_FILE"
sv work "$TB_FILE"
EOF

# Compile
echo "--- Analyzing design ---"
xvlog --incr --relax -prj vlog.prj 2>&1 | tee compile.log
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "ERROR: Compilation failed!"
    exit 1
fi

# Elaborate
echo ""
echo "--- Elaborating ---"
xelab --incr --debug typical --relax --mt auto \
    --snapshot tb_bram_snap work.tb_bram \
    -log elaborate.log 2>&1 | tee -a elaborate.log
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "ERROR: Elaboration failed!"
    exit 1
fi

# Run simulation
echo ""
echo "--- Running simulation ---"
cat > run.tcl <<EOF
run all
quit
EOF

xsim tb_bram_snap -tclbatch run.tcl -log simulate.log 2>&1 | tee simulate_output.log

echo ""
echo "=== Simulation Complete ==="
echo "Logs saved in: $WORK_DIR"
