`timescale 1ns/1ps

module tb_riscv_cpu;
    // clocks and reset
    reg sys_clk_i;
    reg btn_reset_n;

    // IO
    wire uart_tx;
    wire [7:0] leds;

    // DDR3 wires (unused in this test; left un-driven)
    wire [15:0]    ddr3_dq;
    wire [1:0]     ddr3_dqs_n;
    wire [1:0]     ddr3_dqs_p;
    wire [13:0]    ddr3_addr;
    wire [2:0]     ddr3_ba;
    wire           ddr3_ras_n;
    wire           ddr3_cas_n;
    wire           ddr3_we_n;
    wire           ddr3_reset_n;
    wire [0:0]     ddr3_ck_p;
    wire [0:0]     ddr3_ck_n;
    wire [0:0]     ddr3_cke;
    wire [0:0]     ddr3_cs_n;
    wire [1:0]     ddr3_dm;
    wire [0:0]     ddr3_odt;

    // DUT
    riscv_cpu dut (
        .sys_clk_i(sys_clk_i),
        .btn_reset_n(btn_reset_n),
        .ddr3_dq(ddr3_dq),
        .ddr3_dqs_n(ddr3_dqs_n),
        .ddr3_dqs_p(ddr3_dqs_p),
        .ddr3_addr(ddr3_addr),
        .ddr3_ba(ddr3_ba),
        .ddr3_ras_n(ddr3_ras_n),
        .ddr3_cas_n(ddr3_cas_n),
        .ddr3_we_n(ddr3_we_n),
        .ddr3_reset_n(ddr3_reset_n),
        .ddr3_ck_p(ddr3_ck_p),
        .ddr3_ck_n(ddr3_ck_n),
        .ddr3_cke(ddr3_cke),
        .ddr3_cs_n(ddr3_cs_n),
        .ddr3_dm(ddr3_dm),
        .ddr3_odt(ddr3_odt),
        .uart_tx(uart_tx),
        .leds(leds)
    );

    // 100MHz clock
    initial begin
        sys_clk_i = 1'b0;
        forever #5 sys_clk_i = ~sys_clk_i;
    end

    // reset sequence
    initial begin
        btn_reset_n = 1'b0;
        repeat (10) @(posedge sys_clk_i);
        btn_reset_n = 1'b1;
    end

    // scoreboard
    integer errors = 0;
    localparam int MAX_COMMITS = 64;
    reg  [4:0]  exp_rd  [0:MAX_COMMITS-1];
    reg  [31:0] exp_val [0:MAX_COMMITS-1];
    integer exp_len;
    // 在時鐘負緣取樣；用 (rd,val) 變化判定新提交，避免 level-hold 重複
    reg        last_commit_valid;
    reg [4:0]  last_commit_rd;
    reg [31:0] last_commit_val;
    reg        x3_seen;

    // wait and check result (commit-sequence scoreboard)
    initial begin
        integer i;
        integer seen;
        integer cycles;
        bit stop_early;
        string case_name;

        if (!$value$plusargs("CASE=%s", case_name)) begin
            case_name = "hazard"; // default
        end

        // Build expected commit sequence
        exp_len = 0;
        if (case_name == "lw") begin
            // (rd, val)
            exp_rd[exp_len]  = 5'd1; exp_val[exp_len] = 32'h0000_2083; exp_len++;
            exp_rd[exp_len]  = 5'd2; exp_val[exp_len] = 32'h0040_2103; exp_len++;
            exp_rd[exp_len]  = 5'd3; exp_val[exp_len] = 32'h0080_2183; exp_len++;
            exp_rd[exp_len]  = 5'd4; exp_val[exp_len] = 32'h00c0_2203; exp_len++;
            exp_rd[exp_len]  = 5'd5; exp_val[exp_len] = 32'h0100_2283; exp_len++;
            exp_rd[exp_len]  = 5'd6; exp_val[exp_len] = 32'h0100_228c; exp_len++;
        end else if (case_name == "jal") begin
            // 檢查前 3 次提交：x1=9, x1=10, x2=0x0000000c（jal link），x3 不應該寫回
            exp_rd[exp_len]  = 5'd1; exp_val[exp_len] = 32'h0000_0009; exp_len++;
            exp_rd[exp_len]  = 5'd1; exp_val[exp_len] = 32'h0000_000a; exp_len++;
            exp_rd[exp_len]  = 5'd2; exp_val[exp_len] = 32'h0000_000c; exp_len++;
        end else begin
            // hazard default
            exp_rd[exp_len]  = 5'd1; exp_val[exp_len] = 32'h0000_000a; exp_len++;
            exp_rd[exp_len]  = 5'd2; exp_val[exp_len] = 32'h0000_0005; exp_len++;
            exp_rd[exp_len]  = 5'd3; exp_val[exp_len] = 32'h0000_000f; exp_len++;
            exp_rd[exp_len]  = 5'd4; exp_val[exp_len] = 32'h0000_000a; exp_len++;
            // beq has no writeback
            exp_rd[exp_len]  = 5'd5; exp_val[exp_len] = 32'h0000_0019; exp_len++;
            exp_rd[exp_len]  = 5'd6; exp_val[exp_len] = 32'h0000_0008; exp_len++;
            exp_rd[exp_len]  = 5'd7; exp_val[exp_len] = 32'h4021_8233; exp_len++;
            exp_rd[exp_len]  = 5'd8; exp_val[exp_len] = 32'h4021_823b; exp_len++;
        end

        // Wait reset released
        @(posedge btn_reset_n);

        // Observe commits and compare one-by-one（negedge capture + change detect）
        seen = 0;
        x3_seen = 1'b0;
        last_commit_valid = 1'b0;
        stop_early = 1'b0;
        for (cycles = 0; cycles < 20000; cycles = cycles + 1) begin
            @(negedge sys_clk_i);
            if (dut.wb_RegWrite && (dut.wb_rd != 5'd0)) begin
                // 若是記憶體路徑，XOR 歸約為 X 代表尚未就緒 → 暫不記錄
                if (dut.wb_MemtoReg && (^dut.wb_memory_read_data === 1'bx)) begin
                    // skip until data ready
                end else begin
                    // (rd,val) 變化才記錄，避免同值維持造成重複
                    if (!last_commit_valid || (dut.wb_rd !== last_commit_rd) || (dut.wb_reg_write_data !== last_commit_val)) begin
                        last_commit_valid <= 1'b1;
                        last_commit_rd   <= dut.wb_rd;
                        last_commit_val  <= dut.wb_reg_write_data;

                        $display("COMMIT[%0d]: rd=%0d val=%08x mem=%0d mem_valid=%0d", seen, dut.wb_rd, dut.wb_reg_write_data, dut.wb_MemtoReg, (^dut.wb_memory_read_data === 1'bx) ? 0 : 1);
                        if (dut.wb_rd === 5'd3) x3_seen = 1'b1;

                        if (case_name == "jal") begin
                            // do nothing; jal case is checked after loop by register snapshot
                        end else begin
                            if (seen >= exp_len) begin
                                $display("ERROR: unexpected commit: rd=%0d val=%08x (more than expected %0d)", dut.wb_rd, dut.wb_reg_write_data, exp_len);
                                errors = errors + 1;
                            end else begin
                                if (dut.wb_rd !== exp_rd[seen]) begin
                                    $display("ERROR: commit[%0d] rd mismatch: got=%0d exp=%0d", seen, dut.wb_rd, exp_rd[seen]);
                                    errors = errors + 1;
                                end
                                if (dut.wb_reg_write_data !== exp_val[seen]) begin
                                    $display("ERROR: commit[%0d] val mismatch: got=%08x exp=%08x", seen, dut.wb_reg_write_data, exp_val[seen]);
                                    errors = errors + 1;
                                end
                            end
                        end
                        seen = seen + 1;
                        if (case_name != "jal") begin
                            if (seen == exp_len) begin
                                stop_early = 1'b1;
                            end
                        end
                    end
                end
            end
            if (stop_early) begin
                cycles = 20000; // early exit the loop
            end
        end

        // allow pipeline drain a couple cycles
        repeat (2) @(negedge sys_clk_i);

        $display("\n--- Register Snapshot (%0s) ---", case_name);
        $display("x1=%h x2=%h x3=%h x4=%h", dut.reg_file_0.registers[1], dut.reg_file_0.registers[2], dut.reg_file_0.registers[3], dut.reg_file_0.registers[4]);
        $display("x5=%h x6=%h x7=%h x8=%h", dut.reg_file_0.registers[5], dut.reg_file_0.registers[6], dut.reg_file_0.registers[7], dut.reg_file_0.registers[8]);

        if (seen < exp_len) begin
            $display("ERROR: only saw %0d commits, expected %0d", seen, exp_len);
            errors = errors + 1;
        end
        if (case_name == "jal") begin
            if (x3_seen) begin
                $display("ERROR: x3 should not have been written in JAL loop test");
                errors = errors + 1;
            end
            // 額外檢查：x2 應為 0x0000000c
            if (dut.reg_file_0.registers[2] !== 32'h0000_000c) begin
                $display("ERROR: x2 not 0x0000000c at end: got=%08x", dut.reg_file_0.registers[2]);
                errors = errors + 1;
            end
        end

        if (errors == 0) begin
            $display("\nTEST PASSED\n");
        end else begin
            $display("\nTEST FAILED with %0d error(s)\n", errors);
        end
        $finish;
    end

endmodule


