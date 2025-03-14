transcript off
onbreak {quit -force}
onerror {quit -force}
transcript on

vlib work
vlib riviera/xpm
vlib riviera/axi_infrastructure_v1_1_0
vlib riviera/fifo_generator_v13_2_11
vlib riviera/axi_clock_converter_v2_1_32
vlib riviera/xil_defaultlib

vmap xpm riviera/xpm
vmap axi_infrastructure_v1_1_0 riviera/axi_infrastructure_v1_1_0
vmap fifo_generator_v13_2_11 riviera/fifo_generator_v13_2_11
vmap axi_clock_converter_v2_1_32 riviera/axi_clock_converter_v2_1_32
vmap xil_defaultlib riviera/xil_defaultlib

vlog -work xpm  -incr "+incdir+../../../ipstatic/hdl" -l xpm -l axi_infrastructure_v1_1_0 -l fifo_generator_v13_2_11 -l axi_clock_converter_v2_1_32 -l xil_defaultlib \
"/xilinx/tools/Xilinx/Vivado/2024.2/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \
"/xilinx/tools/Xilinx/Vivado/2024.2/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv" \

vcom -work xpm -93  -incr \
"/xilinx/tools/Xilinx/Vivado/2024.2/data/ip/xpm/xpm_VCOMP.vhd" \

vlog -work axi_infrastructure_v1_1_0  -incr -v2k5 "+incdir+../../../ipstatic/hdl" -l xpm -l axi_infrastructure_v1_1_0 -l fifo_generator_v13_2_11 -l axi_clock_converter_v2_1_32 -l xil_defaultlib \
"../../../ipstatic/hdl/axi_infrastructure_v1_1_vl_rfs.v" \

vlog -work fifo_generator_v13_2_11  -incr -v2k5 "+incdir+../../../ipstatic/hdl" -l xpm -l axi_infrastructure_v1_1_0 -l fifo_generator_v13_2_11 -l axi_clock_converter_v2_1_32 -l xil_defaultlib \
"../../../ipstatic/simulation/fifo_generator_vlog_beh.v" \

vcom -work fifo_generator_v13_2_11 -93  -incr \
"../../../ipstatic/hdl/fifo_generator_v13_2_rfs.vhd" \

vlog -work fifo_generator_v13_2_11  -incr -v2k5 "+incdir+../../../ipstatic/hdl" -l xpm -l axi_infrastructure_v1_1_0 -l fifo_generator_v13_2_11 -l axi_clock_converter_v2_1_32 -l xil_defaultlib \
"../../../ipstatic/hdl/fifo_generator_v13_2_rfs.v" \

vlog -work axi_clock_converter_v2_1_32  -incr -v2k5 "+incdir+../../../ipstatic/hdl" -l xpm -l axi_infrastructure_v1_1_0 -l fifo_generator_v13_2_11 -l axi_clock_converter_v2_1_32 -l xil_defaultlib \
"../../../ipstatic/hdl/axi_clock_converter_v2_1_vl_rfs.v" \

vlog -work xil_defaultlib  -incr -v2k5 "+incdir+../../../ipstatic/hdl" -l xpm -l axi_infrastructure_v1_1_0 -l fifo_generator_v13_2_11 -l axi_clock_converter_v2_1_32 -l xil_defaultlib \
"../../../../risc-v.gen/sources_1/ip/axi_clock_converter_0/sim/axi_clock_converter_0.v" \

vlog -work xil_defaultlib \
"glbl.v"

