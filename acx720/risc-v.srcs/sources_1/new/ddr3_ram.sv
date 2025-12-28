`timescale 1ps / 1ps
// Create Date: 03/07/2025 12:56:14 PM

parameter DQ_WIDTH              = 16;
parameter DQS_WIDTH             = 2;
parameter ROW_WIDTH             = 14;
parameter CS_WIDTH              = 1;
parameter DM_WIDTH              = 2;
parameter ODT_WIDTH             = 1;

module ddr3_ram(
    input logic clk_50,
    input logic clk_200,
    input logic pll_locked,
    input logic rst_n,
    input logic MemRead,
    input logic MemWrite,
    input logic [31:0] address,
    input logic [31:0] write_data,
    output logic read_data_valid,
    output logic [31:0] read_data,
    output logic write_done,
    output logic init_calib_complete,

    inout [15:0]    ddr3_dq,
    inout [1:0]     ddr3_dqs_n,
    inout [1:0]     ddr3_dqs_p,
    output [13:0]   ddr3_addr,
    output [2:0]    ddr3_ba,
    output          ddr3_ras_n,
    output          ddr3_cas_n,
    output          ddr3_we_n,
    output          ddr3_reset_n,
    output [0:0]    ddr3_ck_p,
    output [0:0]    ddr3_ck_n,
    output [0:0]    ddr3_cke,
    output [0:0]    ddr3_cs_n,
    output [1:0]    ddr3_dm,
    output [0:0]    ddr3_odt
);

    parameter nCK_PER_CLK            = 4;
    parameter C_S_AXI_ID_WIDTH       = 4;
    parameter C_S_AXI_ADDR_WIDTH     = 28;
    parameter C_S_AXI_DATA_WIDTH     = 128;
    localparam DATA_WIDTH            = 16;
    localparam PAYLOAD_WIDTH         = DATA_WIDTH;
    localparam APP_DATA_WIDTH        = 2 * nCK_PER_CLK * PAYLOAD_WIDTH;

    wire         ui_clk;
    wire         ui_clk_sync_rst;  // MIG內部reset

    reg rstn_50  = 1'b0;
    reg rstn_200 = 1'b0;
    always @(posedge clk_50 or negedge rst_n) begin
        if (!rst_n)
            rstn_50 <= 1'b0;
        else
            rstn_50 <= pll_locked;  // locked後才解除reset
    end

    always @(posedge clk_200 or negedge rst_n) begin
        if (!rst_n)
            rstn_200 <= 1'b0;
        else
            rstn_200 <= pll_locked;
    end

    // clk_wiz_0 u_clk_wiz_0 (
    //     .clk_out1(clk_200),
    //     .resetn(rst_n),
    //     .locked(pll_locked),
    //     .clk_in1(clk)
    // );

  // Slave Interface Write Address Ports
  wire [C_S_AXI_ID_WIDTH-1:0]       s_axi_awid;
  wire [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_awaddr;
  wire [7:0]                        s_axi_awlen;
  wire [2:0]                        s_axi_awsize;
  wire [1:0]                        s_axi_awburst;
  wire [0:0]                        s_axi_awlock;
  wire [3:0]                        s_axi_awcache;
  wire [2:0]                        s_axi_awprot;
  wire                              s_axi_awvalid;
  wire                              s_axi_awready;
   // Slave Interface Write Data Ports
  wire [C_S_AXI_DATA_WIDTH-1:0]     s_axi_wdata;
  wire [(C_S_AXI_DATA_WIDTH/8)-1:0]   s_axi_wstrb;
  wire                              s_axi_wlast;
  wire                              s_axi_wvalid;
  wire                              s_axi_wready;
   // Slave Interface Write Response Ports
  wire                              s_axi_bready;
  wire [C_S_AXI_ID_WIDTH-1:0]       s_axi_bid;
  wire [1:0]                        s_axi_bresp;
  wire                              s_axi_bvalid;
   // Slave Interface Read Address Ports
  wire [C_S_AXI_ID_WIDTH-1:0]       s_axi_arid;
  wire [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_araddr;
  wire [7:0]                        s_axi_arlen;
  wire [2:0]                        s_axi_arsize;
  wire [1:0]                        s_axi_arburst;
  wire [0:0]                        s_axi_arlock;
  wire [3:0]                        s_axi_arcache;
  wire [2:0]                        s_axi_arprot;
  wire                              s_axi_arvalid;
  wire                              s_axi_arready;
   // Slave Interface Read Data Ports
  wire                              s_axi_rready;
  wire [C_S_AXI_ID_WIDTH-1:0]       s_axi_rid;
  wire [C_S_AXI_DATA_WIDTH-1:0]     s_axi_rdata;
  wire [1:0]                        s_axi_rresp;
  wire                              s_axi_rlast;
  wire                              s_axi_rvalid;

  wire [11:0]                       device_temp;

  // AXI signals between clock converter and MIG
  wire [C_S_AXI_ID_WIDTH-1:0]       axi_cc_to_mig_awid;
  wire [C_S_AXI_ADDR_WIDTH-1:0]     axi_cc_to_mig_awaddr;
  wire [7:0]                        axi_cc_to_mig_awlen;
  wire [2:0]                        axi_cc_to_mig_awsize;
  wire [1:0]                        axi_cc_to_mig_awburst;
  wire [0:0]                        axi_cc_to_mig_awlock;
  wire [3:0]                        axi_cc_to_mig_awcache;
  wire [2:0]                        axi_cc_to_mig_awprot;
  wire                              axi_cc_to_mig_awvalid;
  wire                              axi_cc_to_mig_awready;

  wire [C_S_AXI_DATA_WIDTH-1:0]     axi_cc_to_mig_wdata;
  wire [(C_S_AXI_DATA_WIDTH/8)-1:0] axi_cc_to_mig_wstrb;
  wire                              axi_cc_to_mig_wlast;
  wire                              axi_cc_to_mig_wvalid;
  wire                              axi_cc_to_mig_wready;

  wire [C_S_AXI_ID_WIDTH-1:0]       axi_cc_to_mig_bid;
  wire [1:0]                        axi_cc_to_mig_bresp;
  wire                              axi_cc_to_mig_bvalid;
  wire                              axi_cc_to_mig_bready;

  wire [C_S_AXI_ID_WIDTH-1:0]       axi_cc_to_mig_arid;
  wire [C_S_AXI_ADDR_WIDTH-1:0]     axi_cc_to_mig_araddr;
  wire [7:0]                        axi_cc_to_mig_arlen;
  wire [2:0]                        axi_cc_to_mig_arsize;
  wire [1:0]                        axi_cc_to_mig_arburst;
  wire [0:0]                        axi_cc_to_mig_arlock;
  wire [3:0]                        axi_cc_to_mig_arcache;
  wire [2:0]                        axi_cc_to_mig_arprot;
  wire                              axi_cc_to_mig_arvalid;
  wire                              axi_cc_to_mig_arready;

  wire [C_S_AXI_ID_WIDTH-1:0]       axi_cc_to_mig_rid;
  wire [C_S_AXI_DATA_WIDTH-1:0]     axi_cc_to_mig_rdata;
  wire [1:0]                        axi_cc_to_mig_rresp;
  wire                              axi_cc_to_mig_rlast;
  wire                              axi_cc_to_mig_rvalid;
  wire                              axi_cc_to_mig_rready;

  // AXI Clock Converter instance
  axi_clock_converter_0 u_axi_clock_converter_0 (
    .s_axi_aclk(clk_50),                    // 输入时钟 (TG 侧)
    .s_axi_aresetn(rstn_50),             // 输入复位 (TG 侧)
    .m_axi_aclk(ui_clk),                    // 输出时钟 (MIG 侧) - 现在与输入相同
    .m_axi_aresetn(~ui_clk_sync_rst),             // 输出复位 (MIG 侧) - 现在与输入相同
    
    // 从 TG 到 Clock Converter 的 AXI 写地址通道
    .s_axi_awid(s_axi_awid),
    .s_axi_awaddr(s_axi_awaddr),
    .s_axi_awlen(s_axi_awlen),
    .s_axi_awsize(s_axi_awsize),
    .s_axi_awburst(s_axi_awburst),
    .s_axi_awlock(s_axi_awlock),
    .s_axi_awcache(s_axi_awcache),
    .s_axi_awprot(s_axi_awprot),
    .s_axi_awqos(4'h0),                  // 不使用 QoS
    .s_axi_awvalid(s_axi_awvalid),
    .s_axi_awready(s_axi_awready),
    
    // 从 TG 到 Clock Converter 的 AXI 写数据通道
    .s_axi_wdata(s_axi_wdata),
    .s_axi_wstrb(s_axi_wstrb),
    .s_axi_wlast(s_axi_wlast),
    .s_axi_wvalid(s_axi_wvalid),
    .s_axi_wready(s_axi_wready),
    
    // 从 Clock Converter 到 TG 的 AXI 写响应通道
    .s_axi_bid(s_axi_bid),
    .s_axi_bresp(s_axi_bresp),
    .s_axi_bvalid(s_axi_bvalid),
    .s_axi_bready(s_axi_bready),
    
    // 从 TG 到 Clock Converter 的 AXI 读地址通道
    .s_axi_arid(s_axi_arid),
    .s_axi_araddr(s_axi_araddr),
    .s_axi_arlen(s_axi_arlen),
    .s_axi_arsize(s_axi_arsize),
    .s_axi_arburst(s_axi_arburst),
    .s_axi_arlock(s_axi_arlock),
    .s_axi_arcache(s_axi_arcache),
    .s_axi_arprot(s_axi_arprot),
    .s_axi_arqos(4'h0),                  // 不使用 QoS
    .s_axi_arvalid(s_axi_arvalid),
    .s_axi_arready(s_axi_arready),
    
    // 从 Clock Converter 到 TG 的 AXI 读数据通道
    .s_axi_rid(s_axi_rid),
    .s_axi_rdata(s_axi_rdata),
    .s_axi_rresp(s_axi_rresp),
    .s_axi_rlast(s_axi_rlast),
    .s_axi_rvalid(s_axi_rvalid),
    .s_axi_rready(s_axi_rready),
    
    // 从 Clock Converter 到 MIG 的 AXI 写地址通道
    .m_axi_awid(axi_cc_to_mig_awid),
    .m_axi_awaddr(axi_cc_to_mig_awaddr),
    .m_axi_awlen(axi_cc_to_mig_awlen),
    .m_axi_awsize(axi_cc_to_mig_awsize),
    .m_axi_awburst(axi_cc_to_mig_awburst),
    .m_axi_awlock(axi_cc_to_mig_awlock),
    .m_axi_awcache(axi_cc_to_mig_awcache),
    .m_axi_awprot(axi_cc_to_mig_awprot),
    //.m_axi_awqos(4'h0),                  // 不使用 QoS
    .m_axi_awvalid(axi_cc_to_mig_awvalid),
    .m_axi_awready(axi_cc_to_mig_awready),
    
    // 从 Clock Converter 到 MIG 的 AXI 写数据通道
    .m_axi_wdata(axi_cc_to_mig_wdata),
    .m_axi_wstrb(axi_cc_to_mig_wstrb),
    .m_axi_wlast(axi_cc_to_mig_wlast),
    .m_axi_wvalid(axi_cc_to_mig_wvalid),
    .m_axi_wready(axi_cc_to_mig_wready),
    
    // 从 MIG 到 Clock Converter 的 AXI 写响应通道
    .m_axi_bid(axi_cc_to_mig_bid),
    .m_axi_bresp(axi_cc_to_mig_bresp),
    .m_axi_bvalid(axi_cc_to_mig_bvalid),
    .m_axi_bready(axi_cc_to_mig_bready),
    
    // 从 Clock Converter 到 MIG 的 AXI 读地址通道
    .m_axi_arid(axi_cc_to_mig_arid),
    .m_axi_araddr(axi_cc_to_mig_araddr),
    .m_axi_arlen(axi_cc_to_mig_arlen),
    .m_axi_arsize(axi_cc_to_mig_arsize),
    .m_axi_arburst(axi_cc_to_mig_arburst),
    .m_axi_arlock(axi_cc_to_mig_arlock),
    .m_axi_arcache(axi_cc_to_mig_arcache),
    .m_axi_arprot(axi_cc_to_mig_arprot),
    //.m_axi_arqos(4'h0),                  // 不使用 QoS
    .m_axi_arvalid(axi_cc_to_mig_arvalid),
    .m_axi_arready(axi_cc_to_mig_arready),
    
    // 从 MIG 到 Clock Converter 的 AXI 读数据通道
    .m_axi_rid(axi_cc_to_mig_rid),
    .m_axi_rdata(axi_cc_to_mig_rdata),
    .m_axi_rresp(axi_cc_to_mig_rresp),
    .m_axi_rlast(axi_cc_to_mig_rlast),
    .m_axi_rvalid(axi_cc_to_mig_rvalid),
    .m_axi_rready(axi_cc_to_mig_rready)
  );

  mig_7series_0 u_mig_7series_0
      (
       
       
// Memory interface ports
       .ddr3_addr                      (ddr3_addr),
       .ddr3_ba                        (ddr3_ba),
       .ddr3_cas_n                     (ddr3_cas_n),
       .ddr3_ck_n                      (ddr3_ck_n),
       .ddr3_ck_p                      (ddr3_ck_p),
       .ddr3_cke                       (ddr3_cke),
       .ddr3_ras_n                     (ddr3_ras_n),
       .ddr3_we_n                      (ddr3_we_n),
       .ddr3_dq                        (ddr3_dq),
       .ddr3_dqs_n                     (ddr3_dqs_n),
       .ddr3_dqs_p                     (ddr3_dqs_p),
       .ddr3_reset_n                   (ddr3_reset_n),
       .init_calib_complete            (init_calib_complete),
      
       .ddr3_cs_n                      (ddr3_cs_n),
       .ddr3_dm                        (ddr3_dm),
       .ddr3_odt                       (ddr3_odt),
// Application interface ports
       .ui_clk                         (ui_clk),
       .ui_clk_sync_rst                (ui_clk_sync_rst),

       .mmcm_locked                    (mmcm_locked),
       .aresetn                        (rstn_200),
       .app_sr_req                     (1'b0),
       .app_ref_req                    (1'b0),
       .app_zq_req                     (1'b0),
       .app_sr_active                  (app_sr_active),
       .app_ref_ack                    (app_ref_ack),
       .app_zq_ack                     (app_zq_ack),

// Slave Interface Write Address Ports
       .s_axi_awid                     (axi_cc_to_mig_awid),
       .s_axi_awaddr                   (axi_cc_to_mig_awaddr),
       .s_axi_awlen                    (axi_cc_to_mig_awlen),
       .s_axi_awsize                   (axi_cc_to_mig_awsize),
       .s_axi_awburst                  (axi_cc_to_mig_awburst),
       .s_axi_awlock                   (axi_cc_to_mig_awlock),
       .s_axi_awcache                  (axi_cc_to_mig_awcache),
       .s_axi_awprot                   (axi_cc_to_mig_awprot),
       .s_axi_awqos                    (4'h0),
       .s_axi_awvalid                  (axi_cc_to_mig_awvalid),
       .s_axi_awready                  (axi_cc_to_mig_awready),
// Slave Interface Write Data Ports
       .s_axi_wdata                    (axi_cc_to_mig_wdata),
       .s_axi_wstrb                    (axi_cc_to_mig_wstrb),
       .s_axi_wlast                    (axi_cc_to_mig_wlast),
       .s_axi_wvalid                   (axi_cc_to_mig_wvalid),
       .s_axi_wready                   (axi_cc_to_mig_wready),
// Slave Interface Write Response Ports
       .s_axi_bid                      (axi_cc_to_mig_bid),
       .s_axi_bresp                    (axi_cc_to_mig_bresp),
       .s_axi_bvalid                   (axi_cc_to_mig_bvalid),
       .s_axi_bready                   (axi_cc_to_mig_bready),
// Slave Interface Read Address Ports
       .s_axi_arid                     (axi_cc_to_mig_arid),
       .s_axi_araddr                   (axi_cc_to_mig_araddr),
       .s_axi_arlen                    (axi_cc_to_mig_arlen),
       .s_axi_arsize                   (axi_cc_to_mig_arsize),
       .s_axi_arburst                  (axi_cc_to_mig_arburst),
       .s_axi_arlock                   (axi_cc_to_mig_arlock),
       .s_axi_arcache                  (axi_cc_to_mig_arcache),
       .s_axi_arprot                   (axi_cc_to_mig_arprot),
       .s_axi_arqos                    (4'h0),
       .s_axi_arvalid                  (axi_cc_to_mig_arvalid),
       .s_axi_arready                  (axi_cc_to_mig_arready),
// Slave Interface Read Data Ports
       .s_axi_rid                      (axi_cc_to_mig_rid),
       .s_axi_rdata                    (axi_cc_to_mig_rdata),
       .s_axi_rresp                    (axi_cc_to_mig_rresp),
       .s_axi_rlast                    (axi_cc_to_mig_rlast),
       .s_axi_rvalid                   (axi_cc_to_mig_rvalid),
       .s_axi_rready                   (axi_cc_to_mig_rready),

      
       
// System Clock Ports
       .sys_clk_i                       (clk_200),
       .device_temp            (device_temp),
      
       .sys_rst                        (rstn_200)
       );

  axi4_master_ctrl u_axi4_master_ctrl
   (
     .clk                             (clk_50),
     .rst_n                          (rstn_50),
     .init_calib_complete(init_calib_complete),

// AXI write address channel signals
     .s_axi_awready                       (s_axi_awready),
     .s_axi_awid                          (s_axi_awid),
     .s_axi_awaddr                        (s_axi_awaddr),
     .s_axi_awlen                         (s_axi_awlen),
     .s_axi_awsize                        (s_axi_awsize),
     .s_axi_awburst                       (s_axi_awburst),
     .s_axi_awlock                        (s_axi_awlock),
     .s_axi_awcache                       (s_axi_awcache),
     .s_axi_awprot                        (s_axi_awprot),
     .s_axi_awvalid                       (s_axi_awvalid),

// AXI write data channel signals
     .s_axi_wready                    (s_axi_wready),
     .s_axi_wdata                      (s_axi_wdata),
     .s_axi_wstrb                      (s_axi_wstrb),
     .s_axi_wlast                      (s_axi_wlast),
     .s_axi_wvalid                     (s_axi_wvalid),

// AXI write response channel signals
     .s_axi_bid                       (s_axi_bid),
     .s_axi_bresp                     (s_axi_bresp),
     .s_axi_bvalid                    (s_axi_bvalid),
     .s_axi_bready                    (s_axi_bready),

// AXI read address channel signals
     .s_axi_arready                       (s_axi_arready),
     .s_axi_arid                          (s_axi_arid),
     .s_axi_araddr                        (s_axi_araddr),
     .s_axi_arlen                         (s_axi_arlen),
     .s_axi_arsize                        (s_axi_arsize),
     .s_axi_arburst                       (s_axi_arburst),
     .s_axi_arlock                        (s_axi_arlock),
     .s_axi_arcache                       (s_axi_arcache),
     .s_axi_arprot                        (s_axi_arprot),
     .s_axi_arvalid                       (s_axi_arvalid),

// AXI read data channel signals
     .s_axi_rid                       (s_axi_rid),
     .s_axi_rresp                     (s_axi_rresp),
     .s_axi_rvalid                    (s_axi_rvalid),
     .s_axi_rdata                      (s_axi_rdata),
     .s_axi_rlast                      (s_axi_rlast),
     .s_axi_rready                    (s_axi_rready),

     .read_enable(MemRead),
     .read_address(address),
     .read_data_valid(read_data_valid),
     .read_data_out(read_data),
     .write_enable(MemWrite),
     .write_address(address),
     .write_data(write_data),
     .write_done(write_done)
    );

endmodule