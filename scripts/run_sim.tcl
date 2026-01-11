# run_sim.tcl - Run behavioral simulation in batch mode
# Usage: vivado -mode batch -source scripts/run_sim.tcl -tclargs <sim_time>
# Example: vivado -mode batch -source scripts/run_sim.tcl -tclargs 5000ns

# Get simulation time from command line args (default: 1000ns)
if { $argc > 0 } {
    set sim_time [lindex $argv 0]
} else {
    set sim_time "1000ns"
}

puts "=== Starting Vivado Simulation ==="
puts "Simulation time: $sim_time"

# Open the project
open_project risc-v.xpr

# Set simulation set
set_property target_sim_set sim_1 [current_project]

# Launch simulation
launch_simulation -mode behavioral

# Run simulation for specified time
run $sim_time

# Print simulation status
puts "=== Simulation completed ==="
puts "Simulated $sim_time"

# Optional: Save waveform database
# write_wave_config risc-v.sim/sim_1/behav/xsim/tb_design_1_behav.wcfg

# Close simulation and project
close_sim
close_project

exit
