# update_xsim_coe.tcl - Update COE for blk_mem_gen_0 (bootrom) and regenerate IP outputs
# Usage:
#   vivado -mode batch -nojournal -nolog -source scripts/update_xsim_coe.tcl -tclargs <coe_file>
#
# This script intentionally does NOT export simulation scripts. It is meant to be fast and
# used for running a suite where the exported xsim scripts already exist.

if { $argc < 1 } {
    puts "ERROR: Missing COE file argument"
    puts "Usage: vivado -mode batch -source scripts/update_xsim_coe.tcl -tclargs <coe_file>"
    exit 1
}

set coe_file [lindex $argv 0]
puts "=== Updating XSim COE file: $coe_file ==="

if { ![file exists $coe_file] } {
    puts "ERROR: COE file not found: $coe_file"
    exit 1
}

open_project risc-v.xpr

set coe_abs_path [file normalize $coe_file]
set ip_coe_path [get_property IP_DIR [get_ips blk_mem_gen_0]]/[file tail $coe_file]
file copy -force $coe_abs_path $ip_coe_path
puts "Copied COE file to: $ip_coe_path"

puts "=== Updating blk_mem_gen_0 COE file ==="
set_property -dict [list \
    CONFIG.Load_Init_File {true} \
    CONFIG.Coe_File [file tail $coe_file] \
] [get_ips blk_mem_gen_0]

puts "=== Regenerating blk_mem_gen_0 ==="
reset_target all [get_ips blk_mem_gen_0]
generate_target all [get_ips blk_mem_gen_0] -force

puts "=== Regenerating blk_mem_gen_4k (best-effort) ==="
catch {
    set_property -dict [list \
        CONFIG.Load_Init_File {true} \
        CONFIG.Coe_File [file tail $coe_file] \
    ] [get_ips blk_mem_gen_4k]
    reset_target all [get_ips blk_mem_gen_4k]
    generate_target all [get_ips blk_mem_gen_4k] -force
}

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

close_project
puts "=== COE update complete (no export_simulation) ==="
exit

