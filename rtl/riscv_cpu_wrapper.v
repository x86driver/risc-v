`timescale 1ns / 1ps
// Create Date: 12/28/2025 10:04:56 AM

module riscv_cpu_wrapper(
    input  wire clk,
    input  wire btn_reset_n,

    // AXI4-Lite Master Interface
    // --- Address Write ---
    output wire [31:0]  m_axi_awaddr,
    output wire [2:0]   m_axi_awprot,
    output wire         m_axi_awvalid,
    input  wire         m_axi_awready,

    // --- Write Data ---
    output wire [31:0]  m_axi_wdata,
    output wire [3:0]   m_axi_wstrb,
    output wire         m_axi_wvalid,
    input  wire         m_axi_wready,

    // --- Write Response ---
    input  wire [1:0]   m_axi_bresp,
    input  wire         m_axi_bvalid,
    output wire         m_axi_bready,

    // --- Read Address Channel ---
    output wire [31:0]  m_axi_araddr,
    output wire         m_axi_arvalid,
    input  wire         m_axi_arready,

    // --- Read Data ---
    input  wire [31:0]  m_axi_rdata,
    input  wire [1:0]   m_axi_rresp,
    input  wire         m_axi_rvalid,
    output wire         m_axi_rready,

    output wire [7:0] leds
);

    riscv_cpu riscv_cpu_0(
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
endmodule
