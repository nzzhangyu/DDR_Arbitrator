`timescale 1ns/1ps
// `include "h80_define.sv"

module ddr4_controller #(
   parameter int ADDR_WIDTH     = 28,
   parameter int APP_ADDR_WIDTH = ADDR_WIDTH + 4
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

   logic [APP_ADDR_WIDTH-1:0] app_addr;
   logic [2:0]                app_cmd;
   logic                      app_en;
   logic                      app_rdy;
   logic [127:0]              app_wdf_data;
   logic [15:0]               app_wdf_mask;
   logic                      app_wdf_wren;
   logic                      app_wdf_end;
   logic                      app_wdf_rdy;
   logic [127:0]              app_rd_data;
   logic                      app_rd_data_valid;
   logic                      app_rd_data_end;

   // User native bridge.
   // This block stages write data, generates MIG app requests, and reports status back up.
   user_app_top #(
      .ADDR_WIDTH     (ADDR_WIDTH),
      .APP_ADDR_WIDTH (APP_ADDR_WIDTH)
   ) user_app_top_uut (
      .app_addr                (app_addr),
      .app_cmd                 (app_cmd),
      .app_en                  (app_en),
      .app_rdy                 (app_rdy),
      .app_wdf_data            (app_wdf_data),
      .app_wdf_mask            (app_wdf_mask),
      .app_wdf_wren            (app_wdf_wren),
      .app_wdf_end             (app_wdf_end),
      .app_wdf_rdy             (app_wdf_rdy),
      .app_rd_data             (app_rd_data),
      .app_rd_data_valid       (app_rd_data_valid),
      .app_rd_data_end         (app_rd_data_end),
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

   ddr4_1200m ddr4_mig_uut (
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
      .c0_ddr4_app_addr        (app_addr),
      .c0_ddr4_app_cmd         (app_cmd),
      .c0_ddr4_app_en          (app_en),
      .c0_ddr4_app_rdy         (app_rdy),
      .c0_ddr4_app_wdf_data    (app_wdf_data),
      .c0_ddr4_app_wdf_mask    (app_wdf_mask),
      .c0_ddr4_app_wdf_wren    (app_wdf_wren),
      .c0_ddr4_app_wdf_end     (app_wdf_end),
      .c0_ddr4_app_wdf_rdy     (app_wdf_rdy),
      .c0_ddr4_app_rd_data     (app_rd_data),
      .c0_ddr4_app_rd_data_valid(app_rd_data_valid),
      .c0_ddr4_app_rd_data_end (app_rd_data_end)
   );

endmodule
