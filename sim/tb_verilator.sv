`timescale 1ns/1ps

`include "cpu.sv"

// Spike-like logging testbench:
// - Loads a program hex (one 32-bit word per line) into instruction/data memories
// - Runs the RTL in rtl/cpu.sv (top: riscv_cpu)
// - Emits a Spike-like commit log to log.txt (format first; values may differ)
module tb_verilator;
    // ----------------------------
    // Clock / Reset
    // ----------------------------
    logic clk = 1'b0;
    logic btn_reset_n = 1'b0;

    // 100MHz-ish clock for convenience
    always #5 clk = ~clk;

    // Deassert external reset after a few cycles.
    initial begin
        btn_reset_n = 1'b0;
        repeat (5) @(posedge clk);
        btn_reset_n = 1'b1;
    end

    // ----------------------------
    // DUT ports
    // ----------------------------
    logic [31:0] m_axi_awaddr;
    logic [2:0]  m_axi_awprot;
    logic        m_axi_awvalid;
    logic        m_axi_awready;

    logic [31:0] m_axi_wdata;
    logic [3:0]  m_axi_wstrb;
    logic        m_axi_wvalid;
    logic        m_axi_wready;

    logic [1:0]  m_axi_bresp;
    logic        m_axi_bvalid;
    logic        m_axi_bready;

    logic [31:0] m_axi_araddr;
    logic        m_axi_arvalid;
    logic        m_axi_arready;

    logic [31:0] m_axi_rdata;
    logic [1:0]  m_axi_rresp;
    logic        m_axi_rvalid;
    logic        m_axi_rready;

    logic [7:0]  leds;

    // Start directly at program entry (default: 0x8000_0000 for riscv-tests)
    // Override at compile time with -GRESET_PC=... if needed.
    riscv_cpu #(.RESET_PC(64'h0000_0000_8000_0000)) dut (
        .clk(clk),
        .btn_reset_n(btn_reset_n),

        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awprot(m_axi_awprot),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),

        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),

        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),

        .m_axi_araddr(m_axi_araddr),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),

        .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready),

        .leds(leds)
    );

    // ------------------------------------------------------------------------
    // Minimal AXI4-Lite "UART" slave model (prevents dead-stall if DUT touches UART)
    //
    // NOTE: rtl/uart.sv includes axi_uartlite_simple.sv when -DIVERILOG is set.
    // We connect only the low nibble of addresses (UARTLite register offsets).
    // ------------------------------------------------------------------------
`ifdef IVERILOG
    axi_uartlite_simple uartlite_slave_0 (
        .s_axi_aclk   (clk),
        .s_axi_aresetn(btn_reset_n),

        .s_axi_awaddr (m_axi_awaddr[3:0]),
        .s_axi_awvalid(m_axi_awvalid),
        .s_axi_awready(m_axi_awready),

        .s_axi_wdata  (m_axi_wdata),
        .s_axi_wstrb  (m_axi_wstrb),
        .s_axi_wvalid (m_axi_wvalid),
        .s_axi_wready (m_axi_wready),

        .s_axi_bresp  (m_axi_bresp),
        .s_axi_bvalid (m_axi_bvalid),
        .s_axi_bready (m_axi_bready),

        .s_axi_araddr (m_axi_araddr[3:0]),
        .s_axi_arvalid(m_axi_arvalid),
        .s_axi_arready(m_axi_arready),

        .s_axi_rdata  (m_axi_rdata),
        .s_axi_rresp  (m_axi_rresp),
        .s_axi_rvalid (m_axi_rvalid),
        .s_axi_rready (m_axi_rready),

        .tx(),
        .rx(1'b1),
        .interrupt()
    );
`else
    // If someone builds without -DIVERILOG, at least avoid X-propagation on AXI inputs.
    initial begin
        m_axi_awready = 1'b0;
        m_axi_wready  = 1'b0;
        m_axi_bresp   = 2'b00;
        m_axi_bvalid  = 1'b0;
        m_axi_arready = 1'b0;
        m_axi_rdata   = 32'h0;
        m_axi_rresp   = 2'b00;
        m_axi_rvalid  = 1'b0;
    end
`endif

    // ----------------------------
    // Program load (+HEX=...)
    // ----------------------------
    initial begin
        string hexfile;
        if ($value$plusargs("HEX=%s", hexfile)) begin
            // Hex file has one 32-bit word per line.
            // BRAM entries are 64-bit, so we pack two words per entry (little-endian):
            //   ram[i] = { word[2*i+1], word[2*i] }
            //   word[2*i]   -> ram[i][31: 0]  (lower address)
            //   word[2*i+1] -> ram[i][63:32]  (higher address)
            automatic logic [31:0] tmp_mem [0:(1<<15)-1];
            automatic int num_entries;
            $display("[tb_verilator] Loading program from %0s", hexfile);

            // Zero-init temp array, then load hex into it
            for (int i = 0; i < (1<<15); i++) tmp_mem[i] = 32'h0;
            $readmemh(hexfile, tmp_mem);

            // Pack pairs of 32-bit words into 64-bit BRAM entries
            num_entries = (1 << 14);  // BRAM depth
            for (int i = 0; i < num_entries; i++) begin
                dut.unified_mem_multicycle_0.uram.ram[i] = {tmp_mem[2*i+1], tmp_mem[2*i]};
            end

            // No boot ROM patch needed - CPU starts directly at RESET_PC (0x8000_0000).
        end else begin
            $display("[tb_verilator] ERROR: missing +HEX=<path-to-hex>");
            $finish;
        end
    end

    // ----------------------------
    // Spike-like log writer
    // ----------------------------
    integer log_fd;
    string  logfile;

    function string csr_name(input int csr);
        case (csr[11:0])
            12'h300: csr_name = "mstatus";
            12'h302: csr_name = "medeleg";
            12'h303: csr_name = "mideleg";
            12'h304: csr_name = "mie";
            12'h305: csr_name = "mtvec";
            12'h105: csr_name = "stvec";
            12'h180: csr_name = "satp";
            12'h341: csr_name = "mepc";
            12'h342: csr_name = "mcause";
            12'h343: csr_name = "mtval";
            12'h3a0: csr_name = "pmpcfg0";
            12'h3b0: csr_name = "pmpaddr0";
            12'h744: csr_name = "mnstatus";
            12'hf14: csr_name = "mhartid";
            default: csr_name = "csr";
        endcase
    endfunction

    // Return the *architectural* CSR value after the instruction commits.
    // NOTE: 我們在 negedge 寫 log，而 CSR 暫存器是在 posedge 才更新；
    //       因此要印「commit 後的最終值」應該讀 csr_file 的 *_n（next-state）。
    function automatic logic [63:0] csr_final_value(input int csr);
        unique case (csr[11:0])
            12'h300: csr_final_value = dut.csr_file_0.mstatus_n;
            12'h302: csr_final_value = dut.csr_file_0.medeleg_n;
            12'h303: csr_final_value = dut.csr_file_0.mideleg_n;
            12'h304: csr_final_value = dut.csr_file_0.mie_n;
            12'h305: csr_final_value = dut.csr_file_0.mtvec_n;
            12'h105: csr_final_value = dut.csr_file_0.stvec_n;
            12'h180: csr_final_value = dut.csr_file_0.satp_n;
            12'h341: csr_final_value = dut.csr_file_0.mepc_n;
            12'h342: csr_final_value = dut.csr_file_0.mcause_n;
            12'h343: csr_final_value = dut.csr_file_0.mtval_n;
            12'h3a0: csr_final_value = dut.csr_file_0.pmpcfg0_n;
            12'h3b0: csr_final_value = dut.csr_file_0.pmpaddr0_n;
            12'hf14: csr_final_value = dut.csr_file_0.mhartid;
            default: csr_final_value = dut.wb_reg_write_data; // fallback
        endcase
    endfunction

    initial begin
        if (!$value$plusargs("LOG=%s", logfile)) begin
            logfile = "log.txt";
        end
        log_fd = $fopen(logfile, "w");
        if (log_fd == 0) begin
            $display("[tb_verilator] ERROR: cannot open log file %0s", logfile);
            $finish;
        end
        $display("[tb_verilator] Writing Spike-like log to %0s", logfile);
    end

    // ----------------------------
    // tohost / signature controls
    // ----------------------------
    logic [63:0] tohost_addr;
    logic [63:0] begin_sig;
    logic [63:0] end_sig;
    string       sigfile;
    logic        done;
    logic [63:0] tohost_val;

    initial begin
        tohost_addr = 64'h0000_0000_8000_1000;
        void'($value$plusargs("TOHOST=%h", tohost_addr));

        begin_sig = 64'h0;
        end_sig   = 64'h0;
        void'($value$plusargs("BEGIN_SIG=%h", begin_sig));
        void'($value$plusargs("END_SIG=%h", end_sig));

        if (!$value$plusargs("SIG=%s", sigfile)) begin
            sigfile = "signature.txt";
        end

        done = 1'b0;
        tohost_val = 64'h0;
    end

    task automatic dump_signature();
        integer fd;
        logic [63:0] addr;
        int unsigned idx;
        if (begin_sig >= end_sig) begin
            // No signature region for this test: still create an empty file for tooling.
            fd = $fopen(sigfile, "w");
            if (fd != 0) begin
                $fclose(fd);
            end
            return;
        end
        fd = $fopen(sigfile, "w");
        if (fd == 0) begin
            $display("[tb_verilator] ERROR: cannot open signature file %0s", sigfile);
            return;
        end
        for (addr = begin_sig; addr < end_sig; addr += 4) begin
            // BRAM entries are 64-bit; index by addr[15:3], select upper/lower 32 bits by addr[2].
            idx = ((addr & 64'h0000_FFFF) >> 3);
            if (addr[2])
                $fwrite(fd, "%08x\n", dut.unified_mem_multicycle_0.uram.ram[idx][63:32]);
            else
                $fwrite(fd, "%08x\n", dut.unified_mem_multicycle_0.uram.ram[idx][31:0]);
        end
        $fclose(fd);
        $display("[tb_verilator] Wrote signature: %0s (0x%016x..0x%016x)", sigfile, begin_sig, end_sig);
    endtask

    // Stop after N cycles to avoid infinite loops in early bring-up.
    longint unsigned cycles;
    longint unsigned max_cycles;
    initial begin
        cycles = 0;
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles)) begin
            max_cycles = 20000;
        end
        forever begin
            @(posedge clk);
            cycles++;
            if (cycles >= max_cycles) begin
                $display("[tb_verilator] Reached MAX_CYCLES=%0d, stopping.", max_cycles);
                $finish;
            end
        end
    end

    // Emit one line per retired instruction, Spike-like format.
    // Sample at negedge to observe post-NBA updated pipeline registers.
    logic        last_valid;
    logic [63:0] last_pc;
    logic [31:0] last_inst;
    initial begin
        last_valid = 1'b0;
        last_pc    = 64'h0;
        last_inst  = 32'h0;
    end

    always_ff @(negedge clk) begin
        bit printed;
        int csr_dec;
        logic [6:0] opcode;

        if (done) begin
            // do nothing
        end else if (dut.rst_n && dut.wb_stage_valid && dut.mem_wb_Write) begin
            // Avoid duplicate printing if WB is held/stalled.
            if (!last_valid || (dut.wb_pc != last_pc) || (dut.wb_inst != last_inst)) begin
                last_valid <= 1'b1;
                last_pc    <= dut.wb_pc;
                last_inst  <= dut.wb_inst;

            printed = 1'b0;
            opcode  = dut.wb_inst[6:0];

            // Prefix: PC + INST (Spike-like)
            $fwrite(log_fd, "0x%016x (0x%08x) ", dut.wb_pc, dut.wb_inst);

            // Special: mret has implicit mstatus side-effects in Spike logs
            if (dut.wb_inst == 32'h3020_0073) begin
                // Match the (slightly trimmed) format in log-spike.txt:
                $fwrite(log_fd, "c768_mstatus 0x%016x \n", dut.csr_file_0.mstatus);
                printed = 1'b1;
            end else if (opcode == 7'b0100011) begin
                // Store: "mem <addr> <data>"
                // Spike prints store data width based on size:
                // - sb: 0x0 .. 0xff   (no zero-padding)
                // - sh: 0x0 .. 0xffff (no zero-padding)
                // - sw: 0x00000000 .. 0xffffffff (8-hex-digit zero-padded)
                unique case (dut.wb_inst[14:12])
                    // IMPORTANT: pass an 8/16-bit value so %x prints the same width as Spike
                    3'b000: $fwrite(log_fd, "mem 0x%016x 0x%x\n", dut.wb_alu_out, dut.wb_store_data[7:0]);     // sb
                    3'b001: $fwrite(log_fd, "mem 0x%016x 0x%x\n", dut.wb_alu_out, dut.wb_store_data[15:0]);    // sh
                    3'b010: $fwrite(log_fd, "mem 0x%016x 0x%08x\n", dut.wb_alu_out, dut.wb_store_data[31:0]);  // sw
                    3'b011: $fwrite(log_fd, "mem 0x%016x 0x%016x\n", dut.wb_alu_out, dut.wb_store_data[63:0]); // sd
                    default: $fwrite(log_fd, "mem 0x%016x 0x%016x\n", dut.wb_alu_out, dut.wb_store_data[63:0]);
                endcase
                printed = 1'b1;

                // Stop condition: first non-zero write to tohost[0] means PASS/FAIL.
                if ((dut.wb_alu_out == tohost_addr) && (dut.wb_store_data != 0)) begin
                    tohost_val <= dut.wb_store_data;
                    done <= 1'b1;
                    $display("[tb_verilator] tohost write: addr=%016x data=%016x", tohost_addr, dut.wb_store_data);
                    $display("[tb_verilator] signature cfg: SIG=%0s BEGIN_SIG=%016x END_SIG=%016x", sigfile, begin_sig, end_sig);
                    dump_signature();
                    $finish;
                end
            end else begin
                bit need_trailing_space;
                need_trailing_space = 1'b0;

                // Register writeback: "x<rd> <val>"
                if (dut.wb_RegWrite && (dut.wb_rd != 0)) begin
                    if (opcode == 7'b0000011) begin
                        // Load: ends with "mem" and NO trailing space
                        $fwrite(log_fd, "x%0d 0x%016x mem", dut.wb_rd, dut.wb_mux_write_data);
                        printed = 1'b1;
                    end else begin
                        $fwrite(log_fd, "x%0d 0x%016x", dut.wb_rd, dut.wb_mux_write_data);
                        printed = 1'b1;
                        need_trailing_space = 1'b1;
                    end
                end

                // Spike 會在 load retire 時記錄記憶體存取，即使 rd=x0（無寫回）也會印 "mem".
                // （python 端會把 load 的 address trim 掉，最後只留下 "mem"）
                if (!printed && (opcode == 7'b0000011)) begin
                    $fwrite(log_fd, "mem");
                    printed = 1'b1;
                    need_trailing_space = 1'b0;
                end

                // CSR write side-effect: "c<dec>_<name> <val>" (with trailing space)
                if (dut.wb_CsrWrite) begin
                    csr_dec = dut.wb_CsrWriteImm12;
                    if (printed) $fwrite(log_fd, " ");
                    $fwrite(log_fd, "c%0d_%s 0x%016x", csr_dec, csr_name(csr_dec), csr_final_value(csr_dec));
                    printed = 1'b1;
                    need_trailing_space = 1'b1;
                end

                if (!printed) begin
                    // No side-effects: 3 spaces after ")"
                    $fwrite(log_fd, "  \n");
                end else if (need_trailing_space) begin
                    $fwrite(log_fd, " \n");
                end else begin
                    // Shouldn't happen for current cases, but keep sane formatting
                    $fwrite(log_fd, "\n");
                end
            end
            end
        end
    end

endmodule

