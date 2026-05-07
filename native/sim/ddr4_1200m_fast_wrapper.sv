`timescale 1ns/1ps

// Simulation-only replacement for a native-interface Xilinx ddr4_1200m MIG IP.
// Compile this file for fast mock regressions, and compile the real native MIG
// simulation netlist instead for real-MIG validation.
module ddr4_1200m (
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

   input  logic [23:0]           c0_ddr4_app_addr,
   input  logic [2:0]            c0_ddr4_app_cmd,
   input  logic                  c0_ddr4_app_en,
   output logic                  c0_ddr4_app_rdy,
   input  logic [127:0]          c0_ddr4_app_wdf_data,
   input  logic [15:0]           c0_ddr4_app_wdf_mask,
   input  logic                  c0_ddr4_app_wdf_wren,
   input  logic                  c0_ddr4_app_wdf_end,
   output logic                  c0_ddr4_app_wdf_rdy,
   output logic [127:0]          c0_ddr4_app_rd_data,
   output logic                  c0_ddr4_app_rd_data_valid,
   output logic                  c0_ddr4_app_rd_data_end
);

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
      .APP_ADDR_WIDTH      (24),
      .MEM_WORDS           (1048576),
      .CALIB_DELAY_CYCLES  (16),
      .READ_LATENCY_CYCLES (3)
   ) mock_u (
      .clk_in              (c0_sys_clk_p),
      .RESET               (sys_rst),
      .ui_clk              (c0_ddr4_ui_clk),
      .ui_clk_sync_rst     (c0_ddr4_ui_clk_sync_rst),
      .init_calib_complete (c0_init_calib_complete),
      .dbg_clk             (dbg_clk),
      .app_addr            (c0_ddr4_app_addr),
      .app_cmd             (c0_ddr4_app_cmd),
      .app_en              (c0_ddr4_app_en),
      .app_rdy             (c0_ddr4_app_rdy),
      .app_wdf_data        (c0_ddr4_app_wdf_data),
      .app_wdf_mask        (c0_ddr4_app_wdf_mask),
      .app_wdf_wren        (c0_ddr4_app_wdf_wren),
      .app_wdf_end         (c0_ddr4_app_wdf_end),
      .app_wdf_rdy         (c0_ddr4_app_wdf_rdy),
      .app_rd_data         (c0_ddr4_app_rd_data),
      .app_rd_data_valid   (c0_ddr4_app_rd_data_valid),
      .app_rd_data_end     (c0_ddr4_app_rd_data_end)
   );

endmodule
