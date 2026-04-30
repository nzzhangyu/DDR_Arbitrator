`timescale 1ns/1ps

module user_rw_cmd_gen #(
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

   output logic                      make_data_p_edge_ddr_clk,
   output logic                      ddr_rd_empty,
   output logic                      ddr_overrun,
   output logic                      ddr_warning,
   output logic                      ddr_wr_fifo_rd_en,
   output logic [127:0]              ddr_dataout,
   output logic                      ddr_dataout_en,

   input  logic                      init_calib_complete,
   input  logic                      ui_clk,
   input  logic                      ui_clk_sync_rst,
   input  logic                      ddr_rd_req,
   input  logic                      req_stop,
   input  logic                      make_data_on,
   input  logic [15:0]               view_size,
   input  logic                      rst_local_t_ddr_clk,
   input  logic                      fault_ddr_overrun,
   input  logic                      fault_ddr_warning,
   input  logic                      ddr_wr_fifo_empty,
   input  logic                      ddr_wr_fifo_valid,
   input  logic                      ddr_wr_fifo_prog_empty,
   input  logic [13:0]               ddr_wr_fifo_level,
   input  logic                      wr_fifo_overrun,
   input  logic [127:0]              ddr_wr_fifo_dout,
   input  logic                      cache_fifo_prog_full,
   input  logic                      cache_fifo_almost_empty,
   input  logic [13:0]               cache_fifo_data_count,
   input  logic                      rp_back_en,
   input  logic [ADDR_WIDTH-1:0]     rp_back_view_addr
);

   // Watermark thresholds.
   // The write-side levels describe how full the upstream staging buffer is.
   // The read-side levels describe how much data should be kept available for replay / refill.
   localparam logic [13:0] WR_LEVEL_LOW      = 14'd2048;
   localparam logic [13:0] WR_LEVEL_HIGH     = 14'd8192;
   localparam logic [13:0] WR_LEVEL_URGENT   = 14'd12288;

   localparam logic [13:0] RD_LEVEL_URGENT   = 14'd4096;
   localparam logic [13:0] RD_LEVEL_LOW      = 14'd8192;
   localparam logic [13:0] RD_LEVEL_HIGH     = 14'd12288;
   localparam logic [13:0] RD_CACHE_DEPTH    = 14'd16383;

   localparam logic [8:0]  RD_GRANT_MAX      = 9'd256;
   localparam logic [8:0]  RD_GRANT_WR_HIGH  = 9'd128;

   localparam logic [2:0]  AXI_SIZE_16B      = 3'd4;
   localparam logic [1:0]  AXI_BURST_INCR    = 2'b01;

   typedef enum logic [3:0] {
      RW_IDLE,      // Wait for calibration and replay/backtracking blocks to clear.
      RW_ARB_PRE,   // Fast arbitration entry for urgent or single-sided requests.
      RW_ARB,       // Full arbitration when read and write requests are both active.
      RW_WRITE_AW,  // Issue the AXI write address for the selected burst.
      RW_WRITE_W,   // Stream write data beats until the burst is complete.
      RW_WRITE_B,   // Wait for the AXI write response before re-arbitrating.
      RW_READ_AR,   // Issue the AXI read address for the selected burst.
      RW_READ_R     // Accept read data beats until the AXI burst ends.
   } rw_state_t;

   // Start pulse sync.
   // Synchronize the start pulse into ui_clk and extract a clean rising edge.
   (* ASYNC_REG = "true" *) logic make_data_on_rcom_cdc_to_d;
   (* ASYNC_REG = "true" *) logic make_data_on_dd;
   (* ASYNC_REG = "true" *) logic make_data_on_ddd;
   logic make_data_on_edge;

   always_ff @(posedge ui_clk) begin
      if (ui_clk_sync_rst) begin
         make_data_on_rcom_cdc_to_d <= '0;
         make_data_on_dd            <= '0;
         make_data_on_ddd           <= '0;
      end
      else begin
         make_data_on_rcom_cdc_to_d <= make_data_on;
         make_data_on_dd            <= make_data_on_rcom_cdc_to_d;
         make_data_on_ddd           <= make_data_on_dd;
      end
   end

   assign make_data_on_edge         = make_data_on_dd & (~make_data_on_ddd);
   assign make_data_p_edge_ddr_clk  = make_data_on_edge;

   // Replay delay.
   // Delay replay request so the current AXI transaction can settle first.
   logic [7:0] rp_back_en_dly_cnt;

   always_ff @(posedge ui_clk) begin
      if (ui_clk_sync_rst) begin
         rp_back_en_dly_cnt <= '0;
      end
      else if (rp_back_en) begin
         rp_back_en_dly_cnt <= 8'd1;
      end
      else if (|rp_back_en_dly_cnt) begin
         rp_back_en_dly_cnt <= rp_back_en_dly_cnt + 8'd1;
      end
   end

   logic [10:0] wr_tail_age_cnt;
   logic        wr_tail_age_reached;
   logic        clear_wr_wait_age;

   // Write wait aging.
   // Allow a partial write tail below one full burst to drain after it waits long enough.
   assign wr_tail_age_reached = wr_tail_age_cnt[10];

   always_ff @(posedge ui_clk) begin
      if (ui_clk_sync_rst) begin
         wr_tail_age_cnt <= '0;
      end
      else if (clear_wr_wait_age || (~ddr_wr_fifo_valid)) begin
         wr_tail_age_cnt <= '0;
      end
      else if (~wr_tail_age_reached) begin
         wr_tail_age_cnt <= wr_tail_age_cnt + 11'd1;
      end
   end

   // Pressure state.
   // These flags are the coarse "how much room do we still have?" view that
   // the arbiter uses before it decides whether to favor reads or writes.
   logic wr_level_low;
   logic wr_level_high;
   logic wr_level_urgent;
   logic wr_has_full_burst;
   logic rd_level_low;
   logic rd_level_urgent;
   logic rd_cache_can_prefetch;
   logic [14:0] rd_cache_free_count;

   assign wr_level_low          = ddr_wr_fifo_level >= WR_LEVEL_LOW;
   assign wr_level_high         = ddr_wr_fifo_level >= WR_LEVEL_HIGH;
   assign wr_level_urgent       = ddr_wr_fifo_level >= WR_LEVEL_URGENT;
   assign wr_has_full_burst     = ~ddr_wr_fifo_prog_empty;
   
   assign rd_level_urgent       = cache_fifo_almost_empty |
                              (cache_fifo_data_count <= RD_LEVEL_URGENT);
   assign rd_level_low          = cache_fifo_data_count <= RD_LEVEL_LOW;
   assign rd_cache_free_count   = {1'b0, RD_CACHE_DEPTH} - {1'b0, cache_fifo_data_count};
   assign rd_cache_can_prefetch = (~cache_fifo_prog_full) &
                                  (cache_fifo_data_count < RD_LEVEL_HIGH);

   // Request gating.
   // A request becomes eligible only after the corresponding buffer is non-empty
   // and the read cache has enough room to accept another burst.
   logic ddr_wr_req;
   logic ddr_rd_req_d;
   logic ddr_rd_req_dd;
   logic ddr_rd_req_qual;

   // Write request sources:
   // - enough pressure to start normal draining;
   // - enough data for a full AXI burst;
   // - a small tail has waited long enough and should not be stranded.
   assign ddr_wr_req = ddr_wr_fifo_valid &
                       (wr_level_low | wr_has_full_burst |
                        wr_tail_age_reached);

   always_ff @(posedge ui_clk) begin
      if (ui_clk_sync_rst || rst_local_t_ddr_clk) begin
         ddr_rd_req_d  <= '0;
         ddr_rd_req_dd <= '0;
      end
      else begin
         ddr_rd_req_d  <= ddr_rd_req;
         ddr_rd_req_dd <= ddr_rd_req_d;
      end
   end

   assign ddr_rd_req_qual = (~ddr_rd_empty) & ddr_rd_req_dd & rd_cache_can_prefetch;

   // Arbitration state.
   // The arbiter remembers the last granted direction so normal traffic does not
   // starve one side when both read and write requests are active.
   rw_state_t rw_state;
   rw_state_t rw_next_state;
   logic remember_write_grant;
   logic remember_read_grant;
   logic clear_last_grant;
   logic last_grant_was_write;
   logic last_grant_was_read;

   always_ff @(posedge ui_clk) begin
      if (ui_clk_sync_rst) begin
         last_grant_was_write <= '0;
      end
      else if (clear_last_grant || remember_read_grant) begin
         last_grant_was_write <= '0;
      end
      else if (remember_write_grant) begin
         last_grant_was_write <= 1'b1;
      end
   end

   always_ff @(posedge ui_clk) begin
      if (ui_clk_sync_rst) begin
         last_grant_was_read <= '0;
      end
      else if (clear_last_grant || remember_write_grant) begin
         last_grant_was_read <= '0;
      end
      else if (remember_read_grant) begin
         last_grant_was_read <= 1'b1;
      end
   end

   always_ff @(posedge ui_clk) begin
      if (ui_clk_sync_rst || rst_local_t_ddr_clk || make_data_on_edge) begin
         rw_state <= RW_IDLE;
      end
      else begin
         rw_state <= rw_next_state;
      end
   end

   // Burst tracking.
   // Burst length is re-evaluated from the current levels before each new grant.
   // Once a burst starts, the write or read side runs to its AXI boundary.
   logic [8:0] write_burst_len;
   logic [8:0] read_burst_len;
   logic [8:0] write_beat_cnt;
   logic [8:0] read_beat_cnt;
   logic [8:0] rd_grant_limit;
   logic       write_burst_done;
   logic       read_burst_done;
   logic       block_for_replay;
   logic       rd_cache_has_grant_space;

   // Shorten read grants when write FIFO pressure is high so writes get back in sooner.
   assign rd_grant_limit = wr_level_high ? RD_GRANT_WR_HIGH : RD_GRANT_MAX;
   assign rd_cache_has_grant_space = rd_cache_free_count >= {6'd0, rd_grant_limit};
   // Hold new arbitration while the read pointer is being rewound for replay.
   assign block_for_replay = rp_back_en || (|rp_back_en_dly_cnt);

   logic wr_urgent_req;
   logic wr_high_req;
   logic wr_fair_req;
   logic rd_req_with_space;
   logic rd_req_allowed;
   logic rd_urgent_req;
   logic rd_low_or_urgent_req;
   logic rd_fair_req;
   logic both_rw_req;

   assign wr_urgent_req        = wr_level_urgent && ddr_wr_req;
   assign wr_high_req          = wr_level_high && ddr_wr_req;
   assign rd_req_with_space    = ddr_rd_req_qual && rd_cache_has_grant_space;
   assign rd_req_allowed       = rd_req_with_space && (~wr_level_urgent);
   assign rd_urgent_req        = rd_level_urgent && rd_req_allowed;
   assign rd_low_or_urgent_req = (rd_level_low || rd_level_urgent) && rd_req_allowed;
   assign both_rw_req          = ddr_wr_req && ddr_rd_req_qual;
   assign wr_fair_req          = ddr_wr_req && (~last_grant_was_write);
   assign rd_fair_req          = rd_req_allowed && (~last_grant_was_read);

   // Arbitration policy:
   // - urgent write protects the upstream FIFO from overflow;
   // - low/urgent read refills the downstream cache when write is not urgent;
   // - normal read/write contention uses last-grant memory to avoid one-sided service;
   // - AXI bursts are not interrupted, so preemption happens only at burst boundaries.
   always_comb begin
      rw_next_state        = rw_state;
      remember_write_grant = 1'b0;
      remember_read_grant  = 1'b0;
      clear_last_grant     = 1'b0;
      clear_wr_wait_age    = 1'b0;

      if (~init_calib_complete) begin
         rw_next_state    = RW_IDLE;
         clear_last_grant = 1'b1;
      end
      else begin
         unique case (rw_state)
            RW_IDLE: begin
               clear_last_grant = 1'b1;
               rw_next_state    = block_for_replay ? RW_IDLE : RW_ARB_PRE;
            end

            RW_ARB_PRE: begin
               // Replay/backtracking has priority over issuing a fresh AXI command.
               if (block_for_replay) begin
                  rw_next_state    = RW_IDLE;
                  clear_last_grant = 1'b1;
               end
               // Protect the write FIFO first when it reaches the urgent level.
               else if (wr_urgent_req) begin
                  rw_next_state    = RW_WRITE_AW;
                  clear_last_grant = 1'b1;
               end
               // Refill the read cache if it is urgent and write pressure is not urgent.
               else if (rd_urgent_req) begin
                  rw_next_state    = RW_READ_AR;
                  clear_last_grant = 1'b1;
               end
               // Both sides request service; use the remembered last grant below.
               else if (both_rw_req) begin
                  rw_next_state    = RW_ARB;
               end
               // Single-sided read request.
               else if (rd_req_allowed) begin
                  rw_next_state    = RW_READ_AR;
                  clear_last_grant = 1'b1;
               end
               // Single-sided write request.
               else if (ddr_wr_req) begin
                  rw_next_state    = RW_WRITE_AW;
                  clear_last_grant = 1'b1;
               end
            end

            RW_ARB: begin
               // Urgent write overrides normal fairness.
               if (wr_urgent_req) begin
                  rw_next_state        = RW_WRITE_AW;
                  remember_write_grant = 1'b1;
               end
               // Low or urgent cache level can pull service toward reads.
               else if (rd_low_or_urgent_req) begin
                  rw_next_state       = RW_READ_AR;
                  remember_read_grant = 1'b1;
               end
               // High write pressure wins if the previous grant was not already a write.
               else if (wr_high_req && (~last_grant_was_write)) begin
                  rw_next_state        = RW_WRITE_AW;
                  remember_write_grant = 1'b1;
               end
               // Normal fairness path for write service.
               else if (wr_fair_req) begin
                  rw_next_state        = RW_WRITE_AW;
                  remember_write_grant = 1'b1;
               end
               // Normal fairness path for read service.
               else if (rd_fair_req) begin
                  rw_next_state       = RW_READ_AR;
                  remember_read_grant = 1'b1;
               end
               // Fallback write grant when fairness did not select a side.
               else if (ddr_wr_req) begin
                  rw_next_state        = RW_WRITE_AW;
                  remember_write_grant = 1'b1;
               end
               // Fallback read grant if writes are not urgent and cache space is available.
               else if (rd_req_allowed) begin
                  rw_next_state       = RW_READ_AR;
                  remember_read_grant = 1'b1;
               end
               else begin
                  rw_next_state    = RW_ARB_PRE;
                  clear_last_grant = 1'b1;
               end
            end

            RW_WRITE_AW: begin
               clear_wr_wait_age = 1'b1;
               if (write_burst_len == 0) begin
                  rw_next_state = RW_ARB_PRE;
               end
               // Address handshake locks in the write burst; data follows in W state.
               else if (m_axi_awvalid && m_axi_awready) begin
                  rw_next_state = RW_WRITE_W;
               end
            end

            RW_WRITE_W: begin
               // Complete the full write burst before checking for read preemption.
               if (write_burst_done) begin
                  rw_next_state = RW_WRITE_B;
               end
            end

            RW_WRITE_B: begin
               // AXI write response closes the transaction and returns to arbitration.
               if (m_axi_bvalid) begin
                  rw_next_state = RW_ARB_PRE;
               end
            end

            RW_READ_AR: begin
               if ((read_burst_len == 0) || (~rd_cache_has_grant_space)) begin
                  rw_next_state = RW_ARB_PRE;
               end
               // Address handshake locks in the read burst; data follows in R state.
               else if (m_axi_arvalid && m_axi_arready) begin
                  rw_next_state = RW_READ_R;
               end
            end

            RW_READ_R: begin
               // RLAST marks the burst boundary where the next arbitration can happen.
               if (read_burst_done) begin
                  rw_next_state = RW_ARB_PRE;
               end
            end

            default: begin
               rw_next_state = RW_IDLE;
            end
         endcase
      end
   end

   // Helper functions.
   // Keep burst and address helpers close to their use sites.
   function automatic logic [8:0] clamp_count_256(input logic [13:0] level);
      if (level >= 14'd256) begin
         clamp_count_256 = 9'd256;
      end
      else begin
         clamp_count_256 = {1'b0, level[7:0]};
      end
   endfunction

   function automatic logic [8:0] min3_beat_count(
      input logic [8:0] a,
      input logic [8:0] b,
      input logic [8:0] c
   );
      logic [8:0] min_ab;
      begin
         min_ab = (a < b) ? a : b;
         min3_beat_count = (min_ab < c) ? min_ab : c;
      end
   endfunction

   function automatic logic [8:0] clamp_available_count(input logic [ADDR_WIDTH:0] level);
      if (|level[ADDR_WIDTH:8]) begin
         clamp_available_count = 9'd256;
      end
      else begin
         clamp_available_count = {1'b0, level[7:0]};
      end
   endfunction

   function automatic logic [8:0] clamp_free_count(input logic [14:0] level);
      if (|level[14:8]) begin
         clamp_free_count = 9'd256;
      end
      else begin
         clamp_free_count = {1'b0, level[7:0]};
      end
   endfunction

   function automatic logic [AXI_ADDR_WIDTH-1:0] beat_to_axi_addr(
      input logic [ADDR_WIDTH-1:0] beat_addr
   );
      // Internal addresses count 128-bit beats; AXI addresses count bytes.
      beat_to_axi_addr = ({ {(AXI_ADDR_WIDTH-ADDR_WIDTH){1'b0}}, beat_addr } << 4);
   endfunction

   // Address counters.
   // Internal addresses are counted in 128-bit beats.
   // AXI addresses are converted to byte addresses only at the boundary helper.
   logic [ADDR_WIDTH:0]   user_ad_wr_i;
   logic [ADDR_WIDTH:0]   user_ad_rd_i;
   logic [ADDR_WIDTH-1:0] user_ad_wr;
   logic [ADDR_WIDTH-1:0] user_ad_rd;
   logic [ADDR_WIDTH:0]   ddr_read_available_count;

   assign user_ad_wr               = user_ad_wr_i[ADDR_WIDTH-1:0];
   assign user_ad_rd               = user_ad_rd_i[ADDR_WIDTH-1:0];
   assign ddr_rd_empty             = (user_ad_wr_i == user_ad_rd_i);
   assign ddr_read_available_count = user_ad_wr_i - user_ad_rd_i;

   // Legacy per-view counters.
   // These counters are kept as comments to preserve the old view concept.
   logic        write_data_fire;
   logic        read_data_fire;

   assign write_data_fire = m_axi_wvalid && m_axi_wready;
   assign read_data_fire  = m_axi_rvalid && m_axi_rready;

   always_ff @(posedge ui_clk) begin
      if (ui_clk_sync_rst || rst_local_t_ddr_clk || make_data_on_edge) begin
         user_ad_wr_i <= '0;
      end
      else if (write_data_fire) begin
         user_ad_wr_i <= user_ad_wr_i + 1'b1;
      end
   end

   always_ff @(posedge ui_clk) begin
      if (ui_clk_sync_rst || rst_local_t_ddr_clk || make_data_on_edge) begin
         user_ad_rd_i <= '0;
      end
      // Replay rewinds the read pointer to the requested view address.
      else if (rp_back_en) begin
         user_ad_rd_i <= {1'b0, rp_back_view_addr};
      end
      else if (read_data_fire) begin
         user_ad_rd_i <= user_ad_rd_i + 1'b1;
      end
   end

   always_ff @(posedge ui_clk) begin
      if (ui_clk_sync_rst || rst_local_t_ddr_clk || make_data_on_edge) begin
         write_burst_len <= '0;
      end
      else if (rw_state == RW_ARB_PRE || rw_state == RW_ARB) begin
         // Write bursts are based on FIFO level and clamped to the AXI maximum of 256 beats.
         write_burst_len <= (ddr_wr_fifo_level == 0 && ddr_wr_fifo_valid) ?
                            9'd1 : clamp_count_256(ddr_wr_fifo_level);
      end
   end

   always_ff @(posedge ui_clk) begin
      if (ui_clk_sync_rst || rst_local_t_ddr_clk || make_data_on_edge) begin
         read_burst_len <= '0;
      end
      else if (rw_state == RW_ARB_PRE || rw_state == RW_ARB) begin
         // Read bursts are limited by grant policy, DDR data available, and cache free space.
         read_burst_len <= min3_beat_count(
            rd_grant_limit,
            clamp_available_count(ddr_read_available_count),
            clamp_free_count(rd_cache_free_count)
         );
      end
   end

   always_ff @(posedge ui_clk) begin
      if (ui_clk_sync_rst || rst_local_t_ddr_clk || make_data_on_edge) begin
         write_beat_cnt <= '0;
      end
      else if (rw_state != RW_WRITE_W) begin
         write_beat_cnt <= '0;
      end
      else if (write_data_fire) begin
         write_beat_cnt <= write_beat_cnt + 1'b1;
      end
   end

   always_ff @(posedge ui_clk) begin
      if (ui_clk_sync_rst || rst_local_t_ddr_clk || make_data_on_edge) begin
         read_beat_cnt <= '0;
      end
      else if (rw_state != RW_READ_R) begin
         read_beat_cnt <= '0;
      end
      else if (read_data_fire) begin
         read_beat_cnt <= read_beat_cnt + 1'b1;
      end
   end

   assign write_burst_done = write_data_fire && (write_beat_cnt == (write_burst_len - 1'b1));
   assign read_burst_done  = read_data_fire && m_axi_rlast;

   assign ddr_wr_fifo_rd_en = (rw_state == RW_WRITE_W) &&
                              m_axi_wready &&
                              ddr_wr_fifo_valid &&
                              (write_beat_cnt < write_burst_len);

   assign m_axi_awid    = '0;
   assign m_axi_awaddr  = beat_to_axi_addr(user_ad_wr);
   assign m_axi_awlen   = write_burst_len[7:0] - 8'd1;
   assign m_axi_awsize  = AXI_SIZE_16B;
   assign m_axi_awburst = AXI_BURST_INCR;
   assign m_axi_awlock  = 1'b0;
   assign m_axi_awcache = 4'b0011;
   assign m_axi_awprot  = 3'b000;
   assign m_axi_awqos   = 4'b0000;
   assign m_axi_awvalid = (rw_state == RW_WRITE_AW) && (write_burst_len != 0);

   assign m_axi_wdata   = ddr_wr_fifo_dout;
   assign m_axi_wstrb   = 16'hffff;
   assign m_axi_wvalid  = (rw_state == RW_WRITE_W) &&
                          ddr_wr_fifo_valid &&
                          (write_beat_cnt < write_burst_len);
   assign m_axi_wlast   = m_axi_wvalid && (write_beat_cnt == (write_burst_len - 1'b1));
   assign m_axi_bready  = (rw_state == RW_WRITE_B);

   assign m_axi_arid    = '0;
   assign m_axi_araddr  = beat_to_axi_addr(user_ad_rd);
   assign m_axi_arlen   = read_burst_len[7:0] - 8'd1;
   assign m_axi_arsize  = AXI_SIZE_16B;
   assign m_axi_arburst = AXI_BURST_INCR;
   assign m_axi_arlock  = 1'b0;
   assign m_axi_arcache = 4'b0011;
   assign m_axi_arprot  = 3'b000;
   assign m_axi_arqos   = 4'b0000;
   assign m_axi_arvalid = (rw_state == RW_READ_AR) &&
                          (read_burst_len != 0) &&
                          rd_cache_has_grant_space;
   assign m_axi_rready  = (rw_state == RW_READ_R);

   assign ddr_dataout    = m_axi_rdata;
   assign ddr_dataout_en = read_data_fire;

   logic [ADDR_WIDTH:0] wr_sub_rd;
   logic [ADDR_WIDTH:0] wr_sub_rd_diff;
   logic                wr_rd_same_signal;
   logic                wr_rd_diff_signal;
   logic                set_ddr_overrun;

   assign wr_rd_same_signal = (user_ad_wr_i[ADDR_WIDTH] == user_ad_rd_i[ADDR_WIDTH]);
   assign wr_rd_diff_signal = (user_ad_wr_i[ADDR_WIDTH] ^ user_ad_rd_i[ADDR_WIDTH]);
   assign set_ddr_overrun   = wr_rd_diff_signal &
                              (user_ad_wr_i[ADDR_WIDTH-1:0] == user_ad_rd_i[ADDR_WIDTH-1:0]);

   always_ff @(posedge ui_clk) begin
      if (ui_clk_sync_rst) begin
         ddr_overrun <= '0;
      end
      else if (rst_local_t_ddr_clk || (~init_calib_complete) || make_data_on_edge) begin
         ddr_overrun <= '0;
      end
      else if (fault_ddr_overrun || set_ddr_overrun) begin
         ddr_overrun <= 1'b1;
      end
      else begin
         ddr_overrun <= '0;
      end
   end

   assign wr_sub_rd      = {1'b0, user_ad_wr_i[ADDR_WIDTH-1:0]} -
                           {1'b0, user_ad_rd_i[ADDR_WIDTH-1:0]};
   assign wr_sub_rd_diff = {1'b1, user_ad_wr_i[ADDR_WIDTH-1:0]} -
                           {1'b0, user_ad_rd_i[ADDR_WIDTH-1:0]};

   always_ff @(posedge ui_clk) begin
      if (ui_clk_sync_rst) begin
         ddr_warning <= '0;
      end
      else if (rst_local_t_ddr_clk || (~init_calib_complete) || make_data_on_edge) begin
         ddr_warning <= '0;
      end
      else if (fault_ddr_warning) begin
         ddr_warning <= 1'b1;
      end
      else if (wr_rd_same_signal && (|wr_sub_rd[ADDR_WIDTH:ADDR_WIDTH-2])) begin
         ddr_warning <= 1'b1;
      end
      else if (wr_rd_diff_signal && (|wr_sub_rd_diff[ADDR_WIDTH:ADDR_WIDTH-2])) begin
         ddr_warning <= 1'b1;
      end
      else begin
         ddr_warning <= '0;
      end
   end

   // Legacy synchronizer.
   // The old overrun synchronizer is kept as comment only for reference.

endmodule
