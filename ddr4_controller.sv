`timescale 1ns/1ps
// `include "h80_define.sv"

module ddr4_controller #(
   parameter int ADDR_WIDTH     = 28,
   parameter int AXI_ADDR_WIDTH = ADDR_WIDTH + 4,
   parameter int AXI_ID_WIDTH   = 1
) (
   output logic                  c0_ddr4_act_n,
   output logic [16:0]           c0_ddr4_adr,
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

   output logic                  dbg_clk,
   output logic                  ui_clk,
   output logic                  ui_clk_sync_rst,
   output logic                  init_calib_complete,
   output logic                  user_r_valid,
   output logic [127:0]          user_r_data,
   output logic                  user_r_empty,
   output logic                  ddr_overrun,
   output logic                  ddr_warning,
   output logic                  wr_fifo_overrun,
   output logic                  ddr_wr_fifo_empty,
   output logic                  ddr_rd_empty,
   output logic                  make_data_p_edge_ddr_clk,
   output logic                  clk_backbone,

   input  logic                  clk,
   input  logic                  RESET,
   input  logic                  c0_sys_clk_p,
   input  logic                  c0_sys_clk_n,
   input  logic                  rst_local_t_ddr_clk,
   input  logic                  data_from_ddr_en,
   input  logic [127:0]          data_from_ddr_dd,
   input  logic                  user_r_rd_en,
   input  logic                  ddr_rd_req,
   input  logic                  req_stop,
   input  logic                  rp_back_en,
   input  logic [ADDR_WIDTH-1:0] rp_back_view_addr,
   input  logic                  Fault_inject_en,
   input  logic                  make_data_on,
   input  logic                  make_data_p_edge,
   input  logic [15:0]           view_size
);

   logic fault_ddr_overrun;
   logic fault_ddr_warning;

   assign fault_ddr_overrun = Fault_inject_en;
   assign fault_ddr_warning = Fault_inject_en;
   assign clk_backbone      = '0;

   logic sys_rst;
   assign sys_rst = RESET;

   logic [AXI_ID_WIDTH-1:0]   axi_awid;
   logic [AXI_ADDR_WIDTH-1:0] axi_awaddr;
   logic [7:0]                axi_awlen;
   logic [2:0]                axi_awsize;
   logic [1:0]                axi_awburst;
   logic                      axi_awlock;
   logic [3:0]                axi_awcache;
   logic [2:0]                axi_awprot;
   logic [3:0]                axi_awqos;
   logic                      axi_awvalid;
   logic                      axi_awready;
   logic [127:0]              axi_wdata;
   logic [15:0]               axi_wstrb;
   logic                      axi_wlast;
   logic                      axi_wvalid;
   logic                      axi_wready;
   logic [AXI_ID_WIDTH-1:0]   axi_bid;
   logic [1:0]                axi_bresp;
   logic                      axi_bvalid;
   logic                      axi_bready;
   logic [AXI_ID_WIDTH-1:0]   axi_arid;
   logic [AXI_ADDR_WIDTH-1:0] axi_araddr;
   logic [7:0]                axi_arlen;
   logic [2:0]                axi_arsize;
   logic [1:0]                axi_arburst;
   logic                      axi_arlock;
   logic [3:0]                axi_arcache;
   logic [2:0]                axi_arprot;
   logic [3:0]                axi_arqos;
   logic                      axi_arvalid;
   logic                      axi_arready;
   logic [AXI_ID_WIDTH-1:0]   axi_rid;
   logic [127:0]              axi_rdata;
   logic [1:0]                axi_rresp;
   logic                      axi_rlast;
   logic                      axi_rvalid;
   logic                      axi_rready;

   // User AXI bridge.
   // This block is the user-side owner of the AXI master interface:
   // it stages write data, generates bursts, and reports DDR-side status back up.
   user_app_top #(
      .ADDR_WIDTH     (ADDR_WIDTH),
      .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH   (AXI_ID_WIDTH)
   ) user_app_top_uut (
      .m_axi_awid              (axi_awid),
      .m_axi_awaddr            (axi_awaddr),
      .m_axi_awlen             (axi_awlen),
      .m_axi_awsize            (axi_awsize),
      .m_axi_awburst           (axi_awburst),
      .m_axi_awlock            (axi_awlock),
      .m_axi_awcache           (axi_awcache),
      .m_axi_awprot            (axi_awprot),
      .m_axi_awqos             (axi_awqos),
      .m_axi_awvalid           (axi_awvalid),
      .m_axi_awready           (axi_awready),
      .m_axi_wdata             (axi_wdata),
      .m_axi_wstrb             (axi_wstrb),
      .m_axi_wlast             (axi_wlast),
      .m_axi_wvalid            (axi_wvalid),
      .m_axi_wready            (axi_wready),
      .m_axi_bid               (axi_bid),
      .m_axi_bresp             (axi_bresp),
      .m_axi_bvalid            (axi_bvalid),
      .m_axi_bready            (axi_bready),
      .m_axi_arid              (axi_arid),
      .m_axi_araddr            (axi_araddr),
      .m_axi_arlen             (axi_arlen),
      .m_axi_arsize            (axi_arsize),
      .m_axi_arburst           (axi_arburst),
      .m_axi_arlock            (axi_arlock),
      .m_axi_arcache           (axi_arcache),
      .m_axi_arprot            (axi_arprot),
      .m_axi_arqos             (axi_arqos),
      .m_axi_arvalid           (axi_arvalid),
      .m_axi_arready           (axi_arready),
      .m_axi_rid               (axi_rid),
      .m_axi_rdata             (axi_rdata),
      .m_axi_rresp             (axi_rresp),
      .m_axi_rlast             (axi_rlast),
      .m_axi_rvalid            (axi_rvalid),
      .m_axi_rready            (axi_rready),
      .user_r_data             (user_r_data),
      .user_r_valid            (user_r_valid),
      .user_r_empty            (user_r_empty),
      .ddr_overrun             (ddr_overrun),
      .ddr_warning             (ddr_warning),
      .wr_fifo_overrun         (wr_fifo_overrun),
      .ddr_wr_fifo_empty       (ddr_wr_fifo_empty),
      .ddr_rd_empty            (ddr_rd_empty),
      .make_data_p_edge_ddr_clk(make_data_p_edge_ddr_clk),
      .ui_clk                  (ui_clk),
      .ui_clk_sync_rst         (ui_clk_sync_rst),
      .init_calib_complete     (init_calib_complete),
      .clk                     (clk),
      .RESET                   (RESET),
      .data_from_ddr_en        (data_from_ddr_en),
      .data_from_ddr_dd        (data_from_ddr_dd),
      .user_r_rd_en            (user_r_rd_en),
      .ddr_rd_req              (ddr_rd_req),
      .req_stop                (req_stop),
      .rst_local_t_ddr_clk     (rst_local_t_ddr_clk),
      .fault_ddr_overrun       (fault_ddr_overrun),
      .fault_ddr_warning       (fault_ddr_warning),
      .make_data_on            (make_data_on),
      .make_data_p_edge        (make_data_p_edge),
      .view_size               (view_size),
      .rp_back_en              (rp_back_en),
      .rp_back_view_addr       (rp_back_view_addr)
   );

   ddr4_mig_adapter #(
      .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH   (AXI_ID_WIDTH)
   ) ddr4_mig_uut (
      .c0_init_calib_complete  (init_calib_complete),
      .c0_ddr4_ui_clk          (ui_clk),
      .c0_ddr4_ui_clk_sync_rst (ui_clk_sync_rst),
      .dbg_bus                 (),
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
      .c0_ddr4_s_axi_awid      (axi_awid),
      .c0_ddr4_s_axi_awaddr    (axi_awaddr),
      .c0_ddr4_s_axi_awlen     (axi_awlen),
      .c0_ddr4_s_axi_awsize    (axi_awsize),
      .c0_ddr4_s_axi_awburst   (axi_awburst),
      .c0_ddr4_s_axi_awlock    (axi_awlock),
      .c0_ddr4_s_axi_awcache   (axi_awcache),
      .c0_ddr4_s_axi_awprot    (axi_awprot),
      .c0_ddr4_s_axi_awqos     (axi_awqos),
      .c0_ddr4_s_axi_awvalid   (axi_awvalid),
      .c0_ddr4_s_axi_awready   (axi_awready),
      .c0_ddr4_s_axi_wdata     (axi_wdata),
      .c0_ddr4_s_axi_wstrb     (axi_wstrb),
      .c0_ddr4_s_axi_wlast     (axi_wlast),
      .c0_ddr4_s_axi_wvalid    (axi_wvalid),
      .c0_ddr4_s_axi_wready    (axi_wready),
      .c0_ddr4_s_axi_bid       (axi_bid),
      .c0_ddr4_s_axi_bresp     (axi_bresp),
      .c0_ddr4_s_axi_bvalid    (axi_bvalid),
      .c0_ddr4_s_axi_bready    (axi_bready),
      .c0_ddr4_s_axi_arid      (axi_arid),
      .c0_ddr4_s_axi_araddr    (axi_araddr),
      .c0_ddr4_s_axi_arlen     (axi_arlen),
      .c0_ddr4_s_axi_arsize    (axi_arsize),
      .c0_ddr4_s_axi_arburst   (axi_arburst),
      .c0_ddr4_s_axi_arlock    (axi_arlock),
      .c0_ddr4_s_axi_arcache   (axi_arcache),
      .c0_ddr4_s_axi_arprot    (axi_arprot),
      .c0_ddr4_s_axi_arqos     (axi_arqos),
      .c0_ddr4_s_axi_arvalid   (axi_arvalid),
      .c0_ddr4_s_axi_arready   (axi_arready),
      .c0_ddr4_s_axi_rid       (axi_rid),
      .c0_ddr4_s_axi_rdata     (axi_rdata),
      .c0_ddr4_s_axi_rresp     (axi_rresp),
      .c0_ddr4_s_axi_rlast     (axi_rlast),
      .c0_ddr4_s_axi_rvalid    (axi_rvalid),
      .c0_ddr4_s_axi_rready    (axi_rready)
   );

endmodule
