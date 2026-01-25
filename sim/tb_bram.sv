`timescale 1ns / 1ps

module tb_bram;

    // Clock and signals for Port A
    logic        clka;
    logic [3:0]  wea;
    logic [13:0] addra;
    logic [31:0] dina;
    logic [31:0] douta;

    // Clock and signals for Port B
    logic        clkb;
    logic [3:0]  web;
    logic [13:0] addrb;
    logic [31:0] dinb;
    logic [31:0] doutb;

    // Instantiate BRAM
    //blk_mem_gen_0 uut (
    true_dual_port_bram uut (
        .clka(clka),
        .wea(wea),
        .addra(addra),
        .dina(dina),
        .douta(douta),
        .clkb(clkb),
        .web(web),
        .addrb(addrb),
        .dinb(dinb),
        .doutb(doutb)
    );

    // Clock generation (100MHz, period = 10ns)
    initial clka = 0;
    initial clkb = 0;
    always #5 clka = ~clka;
    always #5 clkb = ~clkb;

    // Test sequence
    initial begin
        // Initialize all signals
        wea   = 4'b0000;
        addra = 14'd0;
        dina  = 32'd0;
        web   = 4'b0000;
        addrb = 14'd0;
        dinb  = 32'd0;

        // Wait for BRAM initialization to complete
        repeat(10) @(posedge clka);

        // ===== Latency Measurement Test (Strict) =====
        $display("=== Read Latency Measurement (Address Change Test) ===");

        // Write two different values to two different addresses
        // Address 6000 = 0x11111111
        @(negedge clka);
        addra = 14'd6000;
        dina  = 32'h11111111;
        wea   = 4'b1111;
        @(negedge clka);
        wea   = 4'b0000;
        @(posedge clka);

        // Address 6001 = 0x22222222
        @(negedge clka);
        addra = 14'd6001;
        dina  = 32'h22222222;
        wea   = 4'b1111;
        @(negedge clka);
        wea   = 4'b0000;
        @(posedge clka);

        // Now: Start reading from address 6000, then switch to 6001
        // This will show exactly when the data changes

        // First, set address to something else (6002) to clear any cached output
        @(negedge clka);
        addra = 14'd6002;
        @(posedge clka);
        @(posedge clka);  // Wait for output to stabilize

        $display("");
        $display("--- Starting address change test ---");
        $display("Expecting: 0x11111111 at addr 6000, 0x22222222 at addr 6001");
        $display("");

        // Now read from 6000
        @(negedge clka);
        addra = 14'd6000;
        $display("T=%0t: Address changed to 6000 (at negedge)", $time);

        @(posedge clka);  // posedge 1
        #1;
        $display("T=%0t: After posedge 1, douta = 0x%08X %s", $time, douta,
                 (douta == 32'h11111111) ? "<-- ADDR 6000 DATA" : 
                 (douta == 32'h22222222) ? "<-- ADDR 6001 DATA" : "");

        // Immediately change to 6001 (without waiting)
        @(negedge clka);
        addra = 14'd6001;
        $display("T=%0t: Address changed to 6001 (at negedge)", $time);

        @(posedge clka);  // posedge 2 for addr 6000, posedge 1 for addr 6001
        #1;
        $display("T=%0t: After posedge 2, douta = 0x%08X %s", $time, douta,
                 (douta == 32'h11111111) ? "<-- ADDR 6000 DATA" : 
                 (douta == 32'h22222222) ? "<-- ADDR 6001 DATA" : "");

        @(posedge clka);  // posedge 3 for addr 6000, posedge 2 for addr 6001
        #1;
        $display("T=%0t: After posedge 3, douta = 0x%08X %s", $time, douta,
                 (douta == 32'h11111111) ? "<-- ADDR 6000 DATA" : 
                 (douta == 32'h22222222) ? "<-- ADDR 6001 DATA" : "");

        @(posedge clka);  // posedge 4
        #1;
        $display("T=%0t: After posedge 4, douta = 0x%08X %s", $time, douta,
                 (douta == 32'h11111111) ? "<-- ADDR 6000 DATA" : 
                 (douta == 32'h22222222) ? "<-- ADDR 6001 DATA" : "");
        $display("");

        // ===== Test 1: Write via Port A, Read via Port B =====
        $display("=== Test 1: Write via Port A, Read via Port B ===");

        // Write 0xDEADBEEF to address 1000
        @(negedge clka);  // Setup signals at negedge
        addra = 14'd1000;
        dina  = 32'hDEADBEEF;
        wea   = 4'b1111;

        @(negedge clka);  // Write completes at this posedge
        wea   = 4'b0000;

        // Read from address 1000 via Port B
        @(negedge clkb);  // Setup read address at negedge
        addrb = 14'd1000;

        @(posedge clkb);  // Address sampled at posedge
        @(posedge clkb);  // Data available after 1 cycle latency

        #1;  // Small delay to sample after clock edge
        if (doutb == 32'hDEADBEEF)
            $display("PASS: Read 0x%08X from addr 1000", doutb);
        else
            $display("FAIL: Expected 0xDEADBEEF, got 0x%08X", doutb);

        // ===== Test 2: Byte Write Enable =====
        $display("=== Test 2: Byte Write Enable ===");

        // First, write a known value to address 100
        @(negedge clka);
        addra = 14'd100;
        dina  = 32'hAAAAAAAA;
        wea   = 4'b1111;

        @(negedge clka);
        wea   = 4'b0000;

        // Now write only byte 1 (bits [15:8]) with value 0xFF
        @(negedge clka);
        addra = 14'd100;
        dina  = 32'h0000FF00;
        wea   = 4'b0010;  // Only write byte 1

        @(negedge clka);
        wea   = 4'b0000;

        // Read from address 100 via Port B
        @(negedge clkb);
        addrb = 14'd100;

        @(posedge clkb);  // Address sampled
        @(posedge clkb);  // Data available

        #1;
        // Expected: 0xAAAAFFAA (only byte 1 [bits 15:8] changed to FF)
        if (doutb == 32'hAAAAFFAA)
            $display("PASS: Read 0x%08X (byte write OK)", doutb);
        else
            $display("FAIL: Expected 0xAAAAFFAA, got 0x%08X", doutb);

        // ===== Test 3: Write via Port B, Read via Port A =====
        $display("=== Test 3: Write via Port B, Read via Port A ===");

        // Write 0x12345678 to address 200 via Port B
        @(negedge clkb);
        addrb = 14'd200;
        dinb  = 32'h12345678;
        web   = 4'b1111;

        @(negedge clkb);
        web   = 4'b0000;

        // Read from address 200 via Port A
        @(negedge clka);
        addra = 14'd200;

        @(posedge clka);  // Address sampled
        @(posedge clka);  // Data available

        #1;
        if (douta == 32'h12345678)
            $display("PASS: Read 0x%08X from addr 200", douta);
        else
            $display("FAIL: Expected 0x12345678, got 0x%08X", douta);

        // Done
        repeat(5) @(posedge clka);
        $display("=== Test Complete ===");
        $finish;
    end

    // Timeout
    initial begin
        #10000;
        $display("TIMEOUT!");
        $finish;
    end

endmodule
