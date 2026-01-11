# setup_xsim_test.tcl - Setup XSim simulation for a specific test
# Usage: vivado -mode batch -nojournal -nolog -source scripts/setup_xsim_test.tcl -tclargs <coe_file>
#
# This script:
# 1. Updates blk_mem_gen_0 to use the specified COE file
# 2. Regenerates IP outputs
# 3. Sets tb_xsim as the simulation top module
# 4. Exports simulation scripts

if { $argc < 1 } {
    puts "ERROR: Missing COE file argument"
    puts "Usage: vivado -mode batch -source scripts/setup_xsim_test.tcl -tclargs <coe_file>"
    exit 1
}

set coe_file [lindex $argv 0]
puts "=== Setting up XSim test with COE file: $coe_file ==="

# Verify COE file exists
if { ![file exists $coe_file] } {
    puts "ERROR: COE file not found: $coe_file"
    exit 1
}

# Open the project
open_project risc-v.xpr

# Get the absolute path and copy COE to IP directory
set coe_abs_path [file normalize $coe_file]
set ip_coe_path [get_property IP_DIR [get_ips blk_mem_gen_0]]/[file tail $coe_file]
file copy -force $coe_abs_path $ip_coe_path
puts "Copied COE file to: $ip_coe_path"

# Update blk_mem_gen_0 to use the new COE file
puts "=== Updating blk_mem_gen_0 COE file ==="
set_property -dict [list \
    CONFIG.Load_Init_File {true} \
    CONFIG.Coe_File [file tail $coe_file] \
] [get_ips blk_mem_gen_0]

# Reset and regenerate the IP
puts "=== Regenerating blk_mem_gen_0 ==="
reset_target all [get_ips blk_mem_gen_0]
generate_target all [get_ips blk_mem_gen_0] -force

# Also regenerate blk_mem_gen_4k (data memory) if it uses the same COE
# For now, we'll just regenerate it to ensure consistency
puts "=== Regenerating blk_mem_gen_4k ==="
catch {
    set_property -dict [list \
        CONFIG.Load_Init_File {true} \
        CONFIG.Coe_File [file tail $coe_file] \
    ] [get_ips blk_mem_gen_4k]
    reset_target all [get_ips blk_mem_gen_4k]
    generate_target all [get_ips blk_mem_gen_4k] -force
}

# Add tb_xsim.sv to simulation fileset if not already present
puts "=== Configuring simulation fileset ==="
set tb_xsim_file [get_files -quiet -of_objects [get_filesets sim_1] tb_xsim.sv]
if { $tb_xsim_file == "" } {
    add_files -fileset sim_1 -norecurse sim/tb_xsim.sv
    puts "Added tb_xsim.sv to sim_1 fileset"
}

# Also add axi_uartlite_simple.sv if not present
set uart_simple_file [get_files -quiet -of_objects [get_filesets sim_1] axi_uartlite_simple.sv]
if { $uart_simple_file == "" } {
    add_files -fileset sim_1 -norecurse rtl/axi_uartlite_simple.sv
    puts "Added axi_uartlite_simple.sv to sim_1 fileset"
}

# Set tb_xsim as simulation top module
set_property top tb_xsim [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
puts "Set simulation top module to: tb_xsim"

# Update compile order
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# Export simulation scripts
puts "=== Exporting simulation scripts ==="
export_simulation -simulator xsim \
    -directory risc-v.sim/sim_1/behav/xsim \
    -force

puts "=== Setup complete ==="
puts "Simulation scripts exported to risc-v.sim/sim_1/behav/xsim/"

# Close project
close_project

exit
