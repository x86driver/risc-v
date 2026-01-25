`timescale 1ps / 1ps
// Create Date: 01/25/2026 07:11:59 AM
//
// True Dual-Port BRAM with byte-write enables
// Supports two initialization methods:
//   1. Simulation: Testbench uses $readmemh() on the `ram` array via hierarchy (e.g., dut.imem.ram)
//   2. Synthesis:  Set INIT_FILE parameter to a .hex file path (or leave empty for zero-init)

module true_dual_port_bram #(
    parameter ADDR_WIDTH = 14,
    parameter INIT_FILE  = "bootrom.hex"
)(
    input  logic clka,
    input  logic [3:0] wea,
    input  logic [13:0] addra,
    input  logic [31:0] dina,
    output logic [31:0] douta,
    input  logic clkb,
    input  logic [3:0] web,
    input  logic [13:0] addrb,
    input  logic [31:0] dinb,
    output logic [31:0] doutb
);

`ifdef BRAM_DEBUG
    initial begin
        integer i;
        logic [13:0] prev_addr;
        $display("[BRAM] DEBUG: initial block started, $time=%0t", $time);
        prev_addr = 14'h3FFF;
        i = 0;
        forever begin
            @(posedge clka);
            if (i < 10 && addra !== prev_addr) begin
                $display("[BRAM] T=%0t: address 0x%08X -> 0x%08X, douta=0x%08X", 
                        $time, prev_addr, addra, douta);
                prev_addr = addra;
                ++i;
            end
        end
    end
`endif

    (* ram_style = "block" *) logic [31:0] ram[0:(1<<ADDR_WIDTH)-1];

    generate
        if (INIT_FILE != "") begin : gen_init
            initial begin
                $readmemh(INIT_FILE, ram);
                $display("Read bootrom: %0s", INIT_FILE);
            end
        end else begin
            initial begin
                $display("NO bootrom available!");
            end
        end
    endgenerate

    always_ff @(posedge clka) begin
        if (wea[0]) ram[addra][ 7: 0] <= dina[ 7: 0];
        if (wea[1]) ram[addra][15: 8] <= dina[15: 8];
        if (wea[2]) ram[addra][23:16] <= dina[23:16];
        if (wea[3]) ram[addra][31:24] <= dina[31:24];

        // read first
        douta <= ram[addra];
    end

    always_ff @(posedge clkb) begin
        if (web[0]) ram[addrb][ 7: 0] <= dinb[ 7: 0];
        if (web[1]) ram[addrb][15: 8] <= dinb[15: 8];
        if (web[2]) ram[addrb][23:16] <= dinb[23:16];
        if (web[3]) ram[addrb][31:24] <= dinb[31:24];

        // read first
        doutb <= ram[addrb];
    end

endmodule
