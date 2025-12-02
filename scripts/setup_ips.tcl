# Usage: source scripts/setup_ips.tcl

puts "========================================================"
puts "  Starting RISC-V Project IP Generation..."
puts "========================================================"

if { [current_project -quiet] eq "" } {
    puts "Error: No project open. Please open the .xpr file first."
    return
}

set my_ips [get_ips *]
if { [llength $my_ips] == 0 } {
    puts "Info: No IPs found in the project. Skipping generation."
} else {
    puts "Resetting IP targets..."
    reset_target all $my_ips
    
    puts "Generating IP output products..."
    generate_target all $my_ips
    
    # puts "Synthesizing IPs..."
    # synth_ip $my_ips
}

puts "========================================================"
puts "  IP Generation Complete. You are ready to simulate!"
puts "========================================================"
