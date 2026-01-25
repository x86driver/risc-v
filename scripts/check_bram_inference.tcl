# check_bram_inference.tcl
# Usage: vivado -mode batch -source scripts/check_bram_inference.tcl

# Create in-memory project for synthesis only
create_project -in_memory -part xcku040-ffva1156-2-e

# Read the BRAM module
read_verilog -sv rtl/true_dual_port_bram.sv

# Run synthesis
synth_design -top true_dual_port_bram -part xcku040-ffva1156-2-e

# Report RAM utilization
puts "\n========== RAM Inference Report =========="
report_ram_utilization

# Report BRAM cells
puts "\n========== BRAM Cells =========="
set bram_cells [get_cells -hier -filter {PRIMITIVE_TYPE =~ BMEM.*}]
if {[llength $bram_cells] > 0} {
    puts "SUCCESS: Found [llength $bram_cells] BRAM cell(s):"
    foreach cell $bram_cells {
        puts "  - $cell ([get_property REF_NAME $cell])"
    }
} else {
    puts "WARNING: No BRAM cells found - memory may be using LUTs!"
}

# Show utilization summary
puts "\n========== Utilization Summary =========="
report_utilization -hierarchical -hierarchical_depth 2

# Check for any RAM-related warnings
puts "\n========== Checking for RAM Warnings =========="
