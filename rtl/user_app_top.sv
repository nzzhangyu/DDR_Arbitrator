`timescale 1ns/1ps

module user_app_top #(
   parameter int ADDR_WIDTH     = 24,
   parameter int AXI_ADDR_WIDTH = ADDR_WIDTH + 4,
   parameter int AXI_ID_WIDTH   = 1
) (
   // AXI4 master write address channel
   output logic [AXI_ID_WIDTH-1:0]   m_axi_awid,
   output logic [AXI_ADDR_WIDTH-1:0] m_axi_awaddr,
   output logic [7:0]                m_axi_awlen,
   output logic [2:0]                m_axi_awsize,
   output logic [1:0]                m_axi_awburst,
   output logic                      m_axi_awlock,
   output logic [3:0]                m_axi_awcache,
   output logic [2:0]                m_axi_awprot,
   output logic [3:0]                m_axi_awqos,
   output logic                      m_axi_awvalid,
   input  logic                      m_axi_awready,

   // AXI4 master write data channel
   output logic [127:0]              m_axi_wdata,
   output logic [15:0]               m_axi_wstrb,
   output logic                      m_axi_wlast,
   output logic                      m_axi_wvalid,
   input  logic                      m_axi_wready,

   // AXI4 master write response channel
   input  logic [AXI_ID_WIDTH-1:0]   m_axi_bid,
   input  logic [1:0]                m_axi_bresp,
   input  logic                      m_axi_bvalid,
   output logic                      m_axi_bready,

   // AXI4 master read address channel
   output logic [AXI_ID_WIDTH-1:0]   m_axi_arid,
   output logic [AXI_ADDR_WIDTH-1:0] m_axi_araddr,
   output logic [7:0]                m_axi_arlen,
   output logic [2:0]                m_axi_arsize,
   output logic [1:0]                m_axi_arburst,
   output logic                      m_axi_arlock,
   output logic [3:0]                m_axi_arcache,
   output logic [2:0]                m_axi_arprot,
   output logic [3:0]                m_axi_arqos,
   output logic                      m_axi_arvalid,
   input  logic                      m_axi_arready,

   // AXI4 master read data channel
   input  logic [AXI_ID_WIDTH-1:0]   m_axi_rid,
   input  logic [127:0]              m_axi_rdata,
   input  logic [1:0]                m_axi_rresp,
   input  logic                      m_axi_rlast,
   input  logic                      m_axi_rvalid,
   output logic                      m_axi_rready,

   output logic [127:0]              user_r_data,
   output logic                      user_r_valid,
   output logic                      user_r_empty,
   output logic                      ddr_overrun,
   output logic                      ddr_warning,
   output logic                      wr_fifo_overrun,
   output logic                      ddr_wr_fifo_empty,
   output logic                      ddr_rd_empty,
   output logic                      make_data_p_edge_ddr_clk,

   input  logic                      ui_clk,
   input  logic                      ui_clk_sync_rst,
   input  logic                      init_calib_complete,
   input  logic                      clk,
   input  logic                      RESET,
   input  logic                      data_from_ddr_en,
   input  logic [127:0]              data_from_ddr_dd,
   input  logic                      user_r_rd_en,
   input  logic                      ddr_rd_req,
   input  logic                      req_stop,
   input  logic                      rst_local_t_ddr_clk,
   input  logic                      fault_ddr_overrun,
   input  logic                      fault_ddr_warning,
   input  logic                      make_data_on,
   input  logic                      make_data_p_edge,
   input  logic [15:0]               view_size,
   input  logic                      rp_back_en,
   input  logic [ADDR_WIDTH-1:0]     rp_back_view_addr
);

   localparam int FIFO_DATA_WIDTH        = 128;
   localparam int DDR_FIFO_DEPTH         = 16384;
   localparam int DDR_FIFO_COUNT_WIDTH   = 15;
   localparam int WR_PROG_EMPTY_THRESH   = 256;
   localparam int RD_PROG_FULL_THRESH    = 12288;
   localparam logic [13:0] RD_ALMOST_EMPTY_THRESH = 14'd4096;

   // Write-side DDR staging FIFO.
   // The upstream producer writes in clk, while the AXI writer drains in ui_clk.
   logic [127:0] ddr_wr_fifo_dout;
   logic         ddr_wr_fifo_valid;
   logic         ddr_wr_fifo_prog_empty;
   logic         ddr_wr_fifo_full;
   logic         ddr_wr_fifo_overflow;
   logic         ddr_wr_fifo_rd_en;
   logic [14:0]  ddr_wr_fifo_rd_count_raw;
   logic [13:0]  ddr_wr_fifo_level;

   assign ddr_wr_fifo_level = ddr_wr_fifo_rd_count_raw[14] ?
                              14'h3fff : ddr_wr_fifo_rd_count_raw[13:0];

   xpm_fifo_async #(
      .CASCADE_HEIGHT      (0),
      .CDC_SYNC_STAGES     (2),
      .DOUT_RESET_VALUE    ("0"),
      .ECC_MODE            ("no_ecc"),
      .FIFO_MEMORY_TYPE    ("auto"),
      .FIFO_READ_LATENCY   (0),
      .FIFO_WRITE_DEPTH    (DDR_FIFO_DEPTH),
      .FULL_RESET_VALUE    (0),
      .PROG_EMPTY_THRESH   (WR_PROG_EMPTY_THRESH),
      .PROG_FULL_THRESH    (10),
      .RD_DATA_COUNT_WIDTH (DDR_FIFO_COUNT_WIDTH),
      .READ_DATA_WIDTH     (FIFO_DATA_WIDTH),
      .READ_MODE           ("fwft"),
      .RELATED_CLOCKS      (0),
      .SIM_ASSERT_CHK      (0),
      .USE_ADV_FEATURES    ("1F1F"),
      .WAKEUP_TIME         (0),
      .WRITE_DATA_WIDTH    (FIFO_DATA_WIDTH),
      .WR_DATA_COUNT_WIDTH (DDR_FIFO_COUNT_WIDTH)
   ) ddr_wr_fifo_uut (
      .data_valid    (ddr_wr_fifo_valid),
      .dout          (ddr_wr_fifo_dout),
      .empty         (ddr_wr_fifo_empty),
      .full          (ddr_wr_fifo_full),
      .overflow      (ddr_wr_fifo_overflow),
      .prog_empty    (ddr_wr_fifo_prog_empty),
      .rd_data_count (ddr_wr_fifo_rd_count_raw),
      .din           (data_from_ddr_dd),
      .injectdbiterr (1'b0),
      .injectsbiterr (1'b0),
      .rd_clk        (ui_clk),
      .rd_en         (ddr_wr_fifo_rd_en),
      .rst           (RESET),
      .sleep         (1'b0),
      .wr_clk        (clk),
      .wr_en         (data_from_ddr_en && (~ddr_wr_fifo_full))
   );

   // Read-side DDR staging FIFO.
   // AXI read data is captured in ui_clk and exposed as a pull FIFO in clk.
   logic [127:0] ddr_rd_fifo_din;
   logic         ddr_rd_fifo_wr_en;
   logic         ddr_rd_fifo_full;
   logic         ddr_rd_fifo_prog_full;
   logic         ddr_rd_fifo_almost_empty_ui;
   logic         ddr_rd_fifo_rd_en;
   logic [14:0]  ddr_rd_fifo_wr_count_raw;
   logic [13:0]  ddr_rd_fifo_level;

   assign ddr_rd_fifo_level = ddr_rd_fifo_wr_count_raw[14] ?
                              14'h3fff : ddr_rd_fifo_wr_count_raw[13:0];
   assign ddr_rd_fifo_almost_empty_ui =
      ddr_rd_fifo_level <= RD_ALMOST_EMPTY_THRESH;
   assign ddr_rd_fifo_rd_en = user_r_rd_en && user_r_valid;

   xpm_fifo_async #(
      .CASCADE_HEIGHT      (0),
      .CDC_SYNC_STAGES     (2),
      .DOUT_RESET_VALUE    ("0"),
      .ECC_MODE            ("no_ecc"),
      .FIFO_MEMORY_TYPE    ("auto"),
      .FIFO_READ_LATENCY   (0),
      .FIFO_WRITE_DEPTH    (DDR_FIFO_DEPTH),
      .FULL_RESET_VALUE    (0),
      .PROG_EMPTY_THRESH   (WR_PROG_EMPTY_THRESH),
      .PROG_FULL_THRESH    (RD_PROG_FULL_THRESH),
      .RD_DATA_COUNT_WIDTH (DDR_FIFO_COUNT_WIDTH),
      .READ_DATA_WIDTH     (FIFO_DATA_WIDTH),
      .READ_MODE           ("fwft"),
      .RELATED_CLOCKS      (0),
      .SIM_ASSERT_CHK      (0),
      .USE_ADV_FEATURES    ("1F1F"),
      .WAKEUP_TIME         (0),
      .WRITE_DATA_WIDTH    (FIFO_DATA_WIDTH),
      .WR_DATA_COUNT_WIDTH (DDR_FIFO_COUNT_WIDTH)
   ) ddr_rd_fifo_uut (
      .data_valid    (user_r_valid),
      .dout          (user_r_data),
      .empty         (user_r_empty),
      .full          (ddr_rd_fifo_full),
      .prog_full     (ddr_rd_fifo_prog_full),
      .wr_data_count (ddr_rd_fifo_wr_count_raw),
      .din           (ddr_rd_fifo_din),
      .injectdbiterr (1'b0),
      .injectsbiterr (1'b0),
      .rd_clk        (clk),
      .rd_en         (ddr_rd_fifo_rd_en),
      .rst           (RESET),
      .sleep         (1'b0),
      .wr_clk        (ui_clk),
      .wr_en         (ddr_rd_fifo_wr_en && (~ddr_rd_fifo_full))
   );

   // Command generator.
   // This block turns watermarks and cached data availability into AXI4 bursts.
   user_rw_cmd_gen #(
      .ADDR_WIDTH     (ADDR_WIDTH),
      .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH   (AXI_ID_WIDTH)
   ) user_rw_cmd_gen_uut (
      .m_axi_awid              (m_axi_awid),
      .m_axi_awaddr            (m_axi_awaddr),
      .m_axi_awlen             (m_axi_awlen),
      .m_axi_awsize            (m_axi_awsize),
      .m_axi_awburst           (m_axi_awburst),
      .m_axi_awlock            (m_axi_awlock),
      .m_axi_awcache           (m_axi_awcache),
      .m_axi_awprot            (m_axi_awprot),
      .m_axi_awqos             (m_axi_awqos),
      .m_axi_awvalid           (m_axi_awvalid),
      .m_axi_awready           (m_axi_awready),
      .m_axi_wdata             (m_axi_wdata),
      .m_axi_wstrb             (m_axi_wstrb),
      .m_axi_wlast             (m_axi_wlast),
      .m_axi_wvalid            (m_axi_wvalid),
      .m_axi_wready            (m_axi_wready),
      .m_axi_bid               (m_axi_bid),
      .m_axi_bresp             (m_axi_bresp),
      .m_axi_bvalid            (m_axi_bvalid),
      .m_axi_bready            (m_axi_bready),
      .m_axi_arid              (m_axi_arid),
      .m_axi_araddr            (m_axi_araddr),
      .m_axi_arlen             (m_axi_arlen),
      .m_axi_arsize            (m_axi_arsize),
      .m_axi_arburst           (m_axi_arburst),
      .m_axi_arlock            (m_axi_arlock),
      .m_axi_arcache           (m_axi_arcache),
      .m_axi_arprot            (m_axi_arprot),
      .m_axi_arqos             (m_axi_arqos),
      .m_axi_arvalid           (m_axi_arvalid),
      .m_axi_arready           (m_axi_arready),
      .m_axi_rid               (m_axi_rid),
      .m_axi_rdata             (m_axi_rdata),
      .m_axi_rresp             (m_axi_rresp),
      .m_axi_rlast             (m_axi_rlast),
      .m_axi_rvalid            (m_axi_rvalid),
      .m_axi_rready            (m_axi_rready),
      .make_data_p_edge_ddr_clk (make_data_p_edge_ddr_clk),
      .ddr_rd_empty             (ddr_rd_empty),
      .ddr_overrun              (ddr_overrun),
      .ddr_warning              (ddr_warning),
      .wr_fifo_rd_en            (ddr_wr_fifo_rd_en),
      .rd_fifo_din              (ddr_rd_fifo_din),
      .rd_fifo_wr_en            (ddr_rd_fifo_wr_en),
      .init_calib_complete      (init_calib_complete),
      .ui_clk                   (ui_clk),
      .ui_clk_sync_rst          (ui_clk_sync_rst),
      .ddr_rd_req               (ddr_rd_req),
      .req_stop                 (req_stop),
      .make_data_on             (make_data_on),
      .view_size                (view_size),
      .rst_local_t_ddr_clk      (rst_local_t_ddr_clk),
      .fault_ddr_overrun        (fault_ddr_overrun),
      .fault_ddr_warning        (fault_ddr_warning),
      .wr_fifo_empty            (ddr_wr_fifo_empty),
      .wr_fifo_valid            (ddr_wr_fifo_valid),
      .wr_fifo_prog_empty       (ddr_wr_fifo_prog_empty),
      .wr_fifo_rd_data_count    (ddr_wr_fifo_level),
      .wr_fifo_overrun          (wr_fifo_overrun),
      .wr_fifo_dout             (ddr_wr_fifo_dout),
      .rd_fifo_prog_full        (ddr_rd_fifo_prog_full),
      .rd_fifo_almost_empty     (ddr_rd_fifo_almost_empty_ui),
      .rd_fifo_data_count       (ddr_rd_fifo_level),
      .rd_fifo_full             (ddr_rd_fifo_full),
      .rp_back_en               (rp_back_en),
      .rp_back_view_addr        (rp_back_view_addr)
   );

   // Overrun monitor.
   // Flag overflow at the write FIFO boundary before data reaches AXI.
   always_ff @(posedge clk) begin
      if (RESET) begin
         wr_fifo_overrun <= '0;
      end
      else if (make_data_p_edge) begin
         wr_fifo_overrun <= '0;
      end
      else if (ddr_wr_fifo_overflow || (ddr_wr_fifo_full && data_from_ddr_en)) begin
         wr_fifo_overrun <= 1'b1;
      end
      else begin
         wr_fifo_overrun <= '0;
      end
   end

endmodule
