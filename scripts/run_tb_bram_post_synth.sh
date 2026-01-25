#!/usr/bin/env bash
#
# Run tb_bram testbench with post-synthesis simulation
# This will show the actual timing behavior of the BRAM
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VIVADO_PATH="${HOME}/tools/Xilinx/2025.2/Vivado"

# Add Vivado to PATH
export PATH="${VIVADO_PATH}/bin:$PATH"

# Create working directory
WORK_DIR="${PROJECT_DIR}/build/tb_bram_post_synth"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo "=== Step 1: Synthesizing BRAM IP ==="

# Create TCL script for synthesis
cat > synth_bram.tcl <<'EOF'
# Open project
open_project /home/shane/pro/fpga/risc-v/risc-v.xpr

# Reset and re-run synthesis for blk_mem_gen_0
reset_run blk_mem_gen_0_synth_1 -quiet
launch_runs blk_mem_gen_0_synth_1 -jobs 24
wait_on_run blk_mem_gen_0_synth_1

# Export post-synthesis simulation netlist
open_run blk_mem_gen_0_synth_1
write_verilog -force -mode funcsim post_synth_blk_mem_gen_0.v

close_project
EOF

# Check if post-synth netlist already exists
if [ ! -f "post_synth_blk_mem_gen_0.v" ]; then
    echo "Running Vivado synthesis..."
    vivado -mode batch -nojournal -nolog -source synth_bram.tcl
else
    echo "Post-synthesis netlist already exists, skipping synthesis"
fi

echo ""
echo "=== Step 2: Compiling for XSim ==="

# Get the simulation libraries path
VERILOG_SRC="${VIVADO_PATH}/data/verilog/src"

# Create project file for post-synth simulation
cat > vlog.prj <<EOF
sv xil_defaultlib "${PROJECT_DIR}/sim/tb_bram.sv"
verilog xil_defaultlib "post_synth_blk_mem_gen_0.v"
verilog xil_defaultlib "${VERILOG_SRC}/glbl.v"
EOF

# Compile with timing information
xvlog --incr --relax -prj vlog.prj 2>&1 | tee compile.log
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "ERROR: Compilation failed!"
    exit 1
fi

echo ""
echo "=== Step 3: Elaborating ==="

xelab --incr --debug typical --relax --mt 24 \
    -L xil_defaultlib -L unisims_ver -L unimacro_ver -L secureip \
    --snapshot tb_bram_post_synth \
    xil_defaultlib.tb_bram xil_defaultlib.glbl \
    -log elaborate.log 2>&1 | tee -a elaborate.log

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "ERROR: Elaboration failed!"
    exit 1
fi

echo ""
echo "=== Step 4: Running Post-Synthesis Simulation ==="

# Create tcl command file
cat > cmd.tcl <<EOF
run all
quit
EOF

xsim tb_bram_post_synth -tclbatch cmd.tcl -log simulate.log 2>&1 | tee simulate_output.log

echo ""
echo "=== Post-Synthesis Simulation Complete ==="
echo "Logs saved in: $WORK_DIR"
