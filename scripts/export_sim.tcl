# export_sim.tcl - Export simulation scripts for XSim
# Usage: vivado -mode batch -source scripts/export_sim.tcl
#
# This script generates all necessary simulation files from scratch:
# 1. Upgrade locked IPs
# 2. Generate Block Design output products (including nested IPs)
# 3. Generate standalone IP output products
# 4. Export simulation scripts (compile.sh, elaborate.sh, simulate.sh, etc.)

# Open the project
open_project risc-v.xpr

puts "=== Checking for locked IPs ==="
# Upgrade any locked IPs
set locked_ips [get_ips -filter {IS_LOCKED == 1}]
if {[llength $locked_ips] > 0} {
    puts "Found locked IPs: $locked_ips"
    puts "Upgrading locked IPs..."
    upgrade_ip -quiet $locked_ips
} else {
    puts "No locked IPs found."
}

puts "=== Generating Block Design output products ==="
# Generate Block Design targets (this handles nested IPs automatically)
set bd_files [get_files -quiet *.bd]
if {[llength $bd_files] > 0} {
    foreach bd $bd_files {
        puts "Generating targets for: $bd"
        generate_target all $bd -force
    }
}

puts "=== Generating standalone IP output products ==="
# Generate standalone IPs (not part of Block Design)
set standalone_ips [get_ips -filter {SCOPE != ""}]
foreach ip [get_ips] {
    # Skip IPs that are part of Block Design (they were generated above)
    set ip_def [get_property IPDEF $ip]
    set ip_file [get_property IP_FILE $ip]
    if {[string match "*bd/design_1/*" $ip_file]} {
        puts "Skipping BD IP: $ip"
        continue
    }
    puts "Generating IP: $ip"
    catch {generate_target simulation [get_ips $ip] -force}
}

puts "=== Updating compile order ==="
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "=== Exporting simulation scripts ==="
# Generate simulation scripts
# This will create compile.sh, elaborate.sh, simulate.sh, and .prj files
export_simulation -simulator xsim \
    -directory risc-v.sim/sim_1/behav/xsim \
    -force

puts "=== Done ==="
puts "Simulation scripts exported to risc-v.sim/sim_1/behav/xsim/"
puts "You can now run: make xsim"

# Close project
close_project

exit
