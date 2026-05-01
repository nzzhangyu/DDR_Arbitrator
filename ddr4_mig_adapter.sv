`timescale 1ns/1ps

module ddr4_mig_adapter #(
   parameter int AXI_ADDR_WIDTH = 32,
   parameter int AXI_ID_WIDTH   = 1,
   parameter int FAST_MEM_WORDS = 1048576
) (
   output logic                  c0_init_calib_complete,
   output logic                  c0_ddr4_ui_clk,
   output logic                  c0_ddr4_ui_clk_sync_rst,
   output logic [511:0]          dbg_bus,
   output logic                  dbg_clk,

   output logic [16:0]           c0_ddr4_adr,
   output logic                  c0_ddr4_act_n,
   output logic [1:0]            c0_ddr4_ba,
   output logic [1:0]            c0_ddr4_bg,
   output logic [0:0]            c0_ddr4_cke,
   output logic [0:0]            c0_ddr4_odt,
   output logic [0:0]            c0_ddr4_cs_n,
   output logic [0:0]            c0_ddr4_ck_t,
   output logic [0:0]            c0_ddr4_ck_c,
   output logic                  c0_ddr4_reset_n,
   inout  wire  [1:0]            c0_ddr4_dm_dbi_n,
   inout  wire  [15:0]           c0_ddr4_dq,
   inout  wire  [1:0]            c0_ddr4_dqs_c,
   inout  wire  [1:0]            c0_ddr4_dqs_t,

   input  logic                  sys_rst,
   input  logic                  c0_sys_clk_p,
   input  logic                  c0_sys_clk_n,

   input  logic [AXI_ID_WIDTH-1:0]   c0_ddr4_s_axi_awid,
   input  logic [AXI_ADDR_WIDTH-1:0] c0_ddr4_s_axi_awaddr,
   input  logic [7:0]                c0_ddr4_s_axi_awlen,
   input  logic [2:0]                c0_ddr4_s_axi_awsize,
   input  logic [1:0]                c0_ddr4_s_axi_awburst,
   input  logic                      c0_ddr4_s_axi_awlock,
   input  logic [3:0]                c0_ddr4_s_axi_awcache,
   input  logic [2:0]                c0_ddr4_s_axi_awprot,
   input  logic [3:0]                c0_ddr4_s_axi_awqos,
   input  logic                      c0_ddr4_s_axi_awvalid,
   output logic                      c0_ddr4_s_axi_awready,
   input  logic [127:0]              c0_ddr4_s_axi_wdata,
   input  logic [15:0]               c0_ddr4_s_axi_wstrb,
   input  logic                      c0_ddr4_s_axi_wlast,
   input  logic                      c0_ddr4_s_axi_wvalid,
   output logic                      c0_ddr4_s_axi_wready,
   output logic [AXI_ID_WIDTH-1:0]   c0_ddr4_s_axi_bid,
   output logic [1:0]                c0_ddr4_s_axi_bresp,
   output logic                      c0_ddr4_s_axi_bvalid,
   input  logic                      c0_ddr4_s_axi_bready,
   input  logic [AXI_ID_WIDTH-1:0]   c0_ddr4_s_axi_arid,
   input  logic [AXI_ADDR_WIDTH-1:0] c0_ddr4_s_axi_araddr,
   input  logic [7:0]                c0_ddr4_s_axi_arlen,
   input  logic [2:0]                c0_ddr4_s_axi_arsize,
   input  logic [1:0]                c0_ddr4_s_axi_arburst,
   input  logic                      c0_ddr4_s_axi_arlock,
   input  logic [3:0]                c0_ddr4_s_axi_arcache,
   input  logic [2:0]                c0_ddr4_s_axi_arprot,
   input  logic [3:0]                c0_ddr4_s_axi_arqos,
   input  logic                      c0_ddr4_s_axi_arvalid,
   output logic                      c0_ddr4_s_axi_arready,
   output logic [AXI_ID_WIDTH-1:0]   c0_ddr4_s_axi_rid,
   output logic [127:0]              c0_ddr4_s_axi_rdata,
   output logic [1:0]                c0_ddr4_s_axi_rresp,
   output logic                      c0_ddr4_s_axi_rlast,
   output logic                      c0_ddr4_s_axi_rvalid,
   input  logic                      c0_ddr4_s_axi_rready
);

`ifdef USE_REAL_MIG
   logic c0_ddr4_aresetn;

   always_ff @(posedge c0_ddr4_ui_clk or posedge sys_rst) begin
      if (sys_rst) begin
         c0_ddr4_aresetn <= 1'b0;
      end else begin
         c0_ddr4_aresetn <= ~c0_ddr4_ui_clk_sync_rst;
      end
   end

   ddr4_1200m ddr4_mig_uut (
      .c0_init_calib_complete  (c0_init_calib_complete),
      .c0_ddr4_ui_clk          (c0_ddr4_ui_clk),
      .c0_ddr4_ui_clk_sync_rst (c0_ddr4_ui_clk_sync_rst),
      .dbg_bus                 (dbg_bus),
      .dbg_clk                 (dbg_clk),
      .c0_ddr4_adr             (c0_ddr4_adr),
      .c0_ddr4_act_n           (c0_ddr4_act_n),
      .c0_ddr4_ba              (c0_ddr4_ba),
      .c0_ddr4_bg              (c0_ddr4_bg),
      .c0_ddr4_cke             (c0_ddr4_cke),
      .c0_ddr4_odt             (c0_ddr4_odt),
      .c0_ddr4_cs_n            (c0_ddr4_cs_n),
      .c0_ddr4_ck_t            (c0_ddr4_ck_t),
      .c0_ddr4_ck_c            (c0_ddr4_ck_c),
      .c0_ddr4_reset_n         (c0_ddr4_reset_n),
      .c0_ddr4_dm_dbi_n        (c0_ddr4_dm_dbi_n),
      .c0_ddr4_dq              (c0_ddr4_dq),
      .c0_ddr4_dqs_c           (c0_ddr4_dqs_c),
      .c0_ddr4_dqs_t           (c0_ddr4_dqs_t),
      .sys_rst                 (sys_rst),
      .c0_sys_clk_p            (c0_sys_clk_p),
      .c0_sys_clk_n            (c0_sys_clk_n),
      .c0_ddr4_aresetn         (c0_ddr4_aresetn),
      .c0_ddr4_s_axi_awid      (c0_ddr4_s_axi_awid),
      .c0_ddr4_s_axi_awaddr    (c0_ddr4_s_axi_awaddr),
      .c0_ddr4_s_axi_awlen     (c0_ddr4_s_axi_awlen),
      .c0_ddr4_s_axi_awsize    (c0_ddr4_s_axi_awsize),
      .c0_ddr4_s_axi_awburst   (c0_ddr4_s_axi_awburst),
      .c0_ddr4_s_axi_awlock    (c0_ddr4_s_axi_awlock),
      .c0_ddr4_s_axi_awcache   (c0_ddr4_s_axi_awcache),
      .c0_ddr4_s_axi_awprot    (c0_ddr4_s_axi_awprot),
      .c0_ddr4_s_axi_awqos     (c0_ddr4_s_axi_awqos),
      .c0_ddr4_s_axi_awvalid   (c0_ddr4_s_axi_awvalid),
      .c0_ddr4_s_axi_awready   (c0_ddr4_s_axi_awready),
      .c0_ddr4_s_axi_wdata     (c0_ddr4_s_axi_wdata),
      .c0_ddr4_s_axi_wstrb     (c0_ddr4_s_axi_wstrb),
      .c0_ddr4_s_axi_wlast     (c0_ddr4_s_axi_wlast),
      .c0_ddr4_s_axi_wvalid    (c0_ddr4_s_axi_wvalid),
      .c0_ddr4_s_axi_wready    (c0_ddr4_s_axi_wready),
      .c0_ddr4_s_axi_bid       (c0_ddr4_s_axi_bid),
      .c0_ddr4_s_axi_bresp     (c0_ddr4_s_axi_bresp),
      .c0_ddr4_s_axi_bvalid    (c0_ddr4_s_axi_bvalid),
      .c0_ddr4_s_axi_bready    (c0_ddr4_s_axi_bready),
      .c0_ddr4_s_axi_arid      (c0_ddr4_s_axi_arid),
      .c0_ddr4_s_axi_araddr    (c0_ddr4_s_axi_araddr),
      .c0_ddr4_s_axi_arlen     (c0_ddr4_s_axi_arlen),
      .c0_ddr4_s_axi_arsize    (c0_ddr4_s_axi_arsize),
      .c0_ddr4_s_axi_arburst   (c0_ddr4_s_axi_arburst),
      .c0_ddr4_s_axi_arlock    (c0_ddr4_s_axi_arlock),
      .c0_ddr4_s_axi_arcache   (c0_ddr4_s_axi_arcache),
      .c0_ddr4_s_axi_arprot    (c0_ddr4_s_axi_arprot),
      .c0_ddr4_s_axi_arqos     (c0_ddr4_s_axi_arqos),
      .c0_ddr4_s_axi_arvalid   (c0_ddr4_s_axi_arvalid),
      .c0_ddr4_s_axi_arready   (c0_ddr4_s_axi_arready),
      .c0_ddr4_s_axi_rid       (c0_ddr4_s_axi_rid),
      .c0_ddr4_s_axi_rdata     (c0_ddr4_s_axi_rdata),
      .c0_ddr4_s_axi_rresp     (c0_ddr4_s_axi_rresp),
      .c0_ddr4_s_axi_rlast     (c0_ddr4_s_axi_rlast),
      .c0_ddr4_s_axi_rvalid    (c0_ddr4_s_axi_rvalid),
      .c0_ddr4_s_axi_rready    (c0_ddr4_s_axi_rready)
   );
`else
   assign dbg_bus           = '0;
   assign c0_ddr4_adr       = '0;
   assign c0_ddr4_act_n     = 1'b1;
   assign c0_ddr4_ba        = '0;
   assign c0_ddr4_bg        = '0;
   assign c0_ddr4_cke       = '0;
   assign c0_ddr4_odt       = '0;
   assign c0_ddr4_cs_n      = '1;
   assign c0_ddr4_ck_t      = '0;
   assign c0_ddr4_ck_c      = '0;
   assign c0_ddr4_reset_n   = ~sys_rst;
   assign c0_ddr4_dm_dbi_n  = 'z;
   assign c0_ddr4_dq        = 'z;
   assign c0_ddr4_dqs_c     = 'z;
   assign c0_ddr4_dqs_t     = 'z;

   ddr4_fast_mock #(
      .AXI_ADDR_WIDTH      (AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH        (AXI_ID_WIDTH),
      .MEM_WORDS           (FAST_MEM_WORDS),
      .CALIB_DELAY_CYCLES  (16),
      .READ_LATENCY_CYCLES (3)
   ) fast_mock_u (
      .clk_in              (c0_sys_clk_p),
      .RESET               (sys_rst),
      .ui_clk              (c0_ddr4_ui_clk),
      .ui_clk_sync_rst     (c0_ddr4_ui_clk_sync_rst),
      .init_calib_complete (c0_init_calib_complete),
      .dbg_clk             (dbg_clk),
      .axi_awid            (c0_ddr4_s_axi_awid),
      .axi_awaddr          (c0_ddr4_s_axi_awaddr),
      .axi_awlen           (c0_ddr4_s_axi_awlen),
      .axi_awsize          (c0_ddr4_s_axi_awsize),
      .axi_awburst         (c0_ddr4_s_axi_awburst),
      .axi_awlock          (c0_ddr4_s_axi_awlock),
      .axi_awcache         (c0_ddr4_s_axi_awcache),
      .axi_awprot          (c0_ddr4_s_axi_awprot),
      .axi_awqos           (c0_ddr4_s_axi_awqos),
      .axi_awvalid         (c0_ddr4_s_axi_awvalid),
      .axi_awready         (c0_ddr4_s_axi_awready),
      .axi_wdata           (c0_ddr4_s_axi_wdata),
      .axi_wstrb           (c0_ddr4_s_axi_wstrb),
      .axi_wlast           (c0_ddr4_s_axi_wlast),
      .axi_wvalid          (c0_ddr4_s_axi_wvalid),
      .axi_wready          (c0_ddr4_s_axi_wready),
      .axi_bid             (c0_ddr4_s_axi_bid),
      .axi_bresp           (c0_ddr4_s_axi_bresp),
      .axi_bvalid          (c0_ddr4_s_axi_bvalid),
      .axi_bready          (c0_ddr4_s_axi_bready),
      .axi_arid            (c0_ddr4_s_axi_arid),
      .axi_araddr          (c0_ddr4_s_axi_araddr),
      .axi_arlen           (c0_ddr4_s_axi_arlen),
      .axi_arsize          (c0_ddr4_s_axi_arsize),
      .axi_arburst         (c0_ddr4_s_axi_arburst),
      .axi_arlock          (c0_ddr4_s_axi_arlock),
      .axi_arcache         (c0_ddr4_s_axi_arcache),
      .axi_arprot          (c0_ddr4_s_axi_arprot),
      .axi_arqos           (c0_ddr4_s_axi_arqos),
      .axi_arvalid         (c0_ddr4_s_axi_arvalid),
      .axi_arready         (c0_ddr4_s_axi_arready),
      .axi_rid             (c0_ddr4_s_axi_rid),
      .axi_rdata           (c0_ddr4_s_axi_rdata),
      .axi_rresp           (c0_ddr4_s_axi_rresp),
      .axi_rlast           (c0_ddr4_s_axi_rlast),
      .axi_rvalid          (c0_ddr4_s_axi_rvalid),
      .axi_rready          (c0_ddr4_s_axi_rready)
   );
`endif

endmodule
