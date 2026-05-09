`timescale 1ns/1ps

// Lightweight DDR4 AXI mock for fast simulation.
// The model keeps a small 128-bit word memory, returns OKAY responses, and
// can inject simple ready/data stalls to exercise controller backpressure.
module ddr4_fast_mock #(
   parameter int AXI_ADDR_WIDTH                 = 32,
   parameter int AXI_ID_WIDTH                   = 1,
   parameter int MEM_WORDS                      = 16384,
   parameter int CALIB_DELAY_CYCLES             = 32,
   parameter int READ_LATENCY_CYCLES            = 2,
   parameter int REFRESH_INTERVAL_CYCLES        = 0,
   parameter int REFRESH_BLOCK_CYCLES           = 0,
   parameter int MAINT_INTERVAL_CYCLES          = 0,
   parameter int MAINT_BLOCK_CYCLES             = 0,
   parameter int READY_STALL_INTERVAL_CYCLES    = 0,
   parameter int READY_STALL_CYCLES             = 0,
   parameter int READ_DATA_GAP_INTERVAL_CYCLES  = 0,
   parameter int READ_DATA_GAP_CYCLES           = 0,
   parameter int TURNAROUND_CYCLES              = 0
) (
   input  logic                      clk_in,
   input  logic                      RESET,

   // MIG interface
   output logic                      ui_clk,
   output logic                      ui_clk_sync_rst,
   output logic                      init_calib_complete,
   output logic                      dbg_clk,

   // AXI4 master write address channel
   input  logic [AXI_ID_WIDTH-1:0]   axi_awid,
   input  logic [AXI_ADDR_WIDTH-1:0] axi_awaddr,
   input  logic [7:0]                axi_awlen,
   input  logic [2:0]                axi_awsize,
   input  logic [1:0]                axi_awburst,
   input  logic                      axi_awlock,
   input  logic [3:0]                axi_awcache,
   input  logic [2:0]                axi_awprot,
   input  logic [3:0]                axi_awqos,
   input  logic                      axi_awvalid,
   output logic                      axi_awready,

   // AXI4 master write data channel
   input  logic [127:0]              axi_wdata,
   input  logic [15:0]               axi_wstrb,
   input  logic                      axi_wlast,
   input  logic                      axi_wvalid,
   output logic                      axi_wready,

   // AXI4 master write response channel
   output logic [AXI_ID_WIDTH-1:0]   axi_bid,
   output logic [1:0]                axi_bresp,
   output logic                      axi_bvalid,
   input  logic                      axi_bready,

   // AXI4 master read address channel
   input  logic [AXI_ID_WIDTH-1:0]   axi_arid,
   input  logic [AXI_ADDR_WIDTH-1:0] axi_araddr,
   input  logic [7:0]                axi_arlen,
   input  logic [2:0]                axi_arsize,
   input  logic [1:0]                axi_arburst,
   input  logic                      axi_arlock,
   input  logic [3:0]                axi_arcache,
   input  logic [2:0]                axi_arprot,
   input  logic [3:0]                axi_arqos,
   input  logic                      axi_arvalid,
   output logic                      axi_arready,

   // AXI4 master read data channel
   output logic [AXI_ID_WIDTH-1:0]   axi_rid,
   output logic [127:0]              axi_rdata,
   output logic [1:0]                axi_rresp,
   output logic                      axi_rlast,
   output logic                      axi_rvalid,
   input  logic                      axi_rready
);

   // Memory is addressed as 128-bit words. AXI byte address bits [3:0] select
   // bytes within a word and are ignored by the array index.
   localparam int MEM_ADDR_BITS   = $clog2(MEM_WORDS);
   localparam int MEM_WORD_MSB    = 4 + MEM_ADDR_BITS - 1;
   localparam logic [AXI_ADDR_WIDTH-1:0] AXI_WORD_BYTES = AXI_ADDR_WIDTH'(16);
   localparam logic [1:0] OKAY      = 2'b00;
   localparam logic [1:0] MEM_BRESP = OKAY;
   localparam logic [1:0] MEM_RRESP = OKAY;

   // Small behavioral storage used only by simulation.
   logic [127:0] mem [0:MEM_WORDS-1];
   logic [7:0]   calib_cnt;

   logic [AXI_ADDR_WIDTH-1:0] write_addr_q;
   logic [8:0]                write_beats_left_q;
   logic [AXI_ID_WIDTH-1:0]   write_id_q;
   logic                      write_active_q;
   logic                      write_resp_pending_q;

   logic [AXI_ADDR_WIDTH-1:0] read_addr_q;
   logic [8:0]                read_beats_left_q;
   logic [AXI_ID_WIDTH-1:0]   read_id_q;
   logic [7:0]                read_latency_q;
   logic                      read_active_q;
   logic                      read_data_valid_q;

   logic [MEM_ADDR_BITS-1:0]  write_mem_index;
   logic [MEM_ADDR_BITS-1:0]  read_mem_index;
   // Stress knobs model coarse DDR4 unavailability windows without pulling in
   // the full MIG simulation model.
   logic [31:0]               stress_cycle_q;             // Counts post-calibration cycles for periodic stall windows.
   logic [15:0]               turnaround_cnt_q;           // Counts down the optional read/write direction-change delay.
   logic                      last_cmd_was_read_q;        // Tracks whether the last accepted address command was a read.
   logic                      cmd_stall_active;           // Blocks AW/AR/W acceptance during refresh/maintenance/ready stalls.
   logic                      data_stall_active;          // Blocks RVALID during refresh/maintenance/read-gap stalls.
   logic                      turn_write_block;           // Blocks a write command while a read-to-write turnaround is active.
   logic                      turn_read_block;            // Blocks a read command while a write-to-read turnaround is active.
   logic                      write_data_fire;            // One-cycle pulse when a write data beat is accepted.
   logic                      read_data_fire;             // One-cycle pulse when a read data beat is accepted by the master.
   int                        refresh_interval_cfg;       // Cycles between simulated DDR refresh stall windows.
   int                        refresh_block_cfg;          // Number of cycles blocked during each refresh window.
   int                        maint_interval_cfg;         // Cycles between simulated MIG maintenance stall windows.
   int                        maint_block_cfg;            // Number of cycles blocked during each maintenance window.
   int                        ready_stall_interval_cfg;   // Cycles between extra ready-deassertion windows.
   int                        ready_stall_block_cfg;      // Number of cycles blocked during each ready-stall window.
   int                        read_gap_interval_cfg;      // Cycles between read-data gap windows.
   int                        read_gap_block_cfg;         // Number of cycles RVALID is suppressed during each read-data gap.
   int                        turnaround_cycles_cfg;      // Configured cycles to wait when switching read/write direction.

   integer i;

   initial begin
      for (i = 0; i < MEM_WORDS; i++) begin
         mem[i] = '0;
      end

      // Parameters provide defaults; plusargs let a test sweep stall behavior
      // without recompiling the mock.
      refresh_interval_cfg     = REFRESH_INTERVAL_CYCLES;
      refresh_block_cfg        = REFRESH_BLOCK_CYCLES;
      maint_interval_cfg       = MAINT_INTERVAL_CYCLES;
      maint_block_cfg          = MAINT_BLOCK_CYCLES;
      ready_stall_interval_cfg = READY_STALL_INTERVAL_CYCLES;
      ready_stall_block_cfg    = READY_STALL_CYCLES;
      read_gap_interval_cfg    = READ_DATA_GAP_INTERVAL_CYCLES;
      read_gap_block_cfg       = READ_DATA_GAP_CYCLES;
      turnaround_cycles_cfg    = TURNAROUND_CYCLES;

      void'($value$plusargs("mock_refresh_interval=%d", refresh_interval_cfg));
      void'($value$plusargs("mock_refresh_block=%d", refresh_block_cfg));
      void'($value$plusargs("mock_maint_interval=%d", maint_interval_cfg));
      void'($value$plusargs("mock_maint_block=%d", maint_block_cfg));
      void'($value$plusargs("mock_ready_stall_interval=%d", ready_stall_interval_cfg));
      void'($value$plusargs("mock_ready_stall_block=%d", ready_stall_block_cfg));
      void'($value$plusargs("mock_read_gap_interval=%d", read_gap_interval_cfg));
      void'($value$plusargs("mock_read_gap_block=%d", read_gap_block_cfg));
      void'($value$plusargs("mock_turnaround=%d", turnaround_cycles_cfg));
   end

   // The real MIG generates ui_clk/dbg_clk. The fast mock aliases them to the
   // incoming simulation clock so the rest of the design sees the same ports.
   assign ui_clk = clk_in;
   assign dbg_clk = clk_in;
   assign ui_clk_sync_rst = RESET | (~init_calib_complete);

   // Returns true during the first block_cycles of each interval_cycles window.
   function automatic logic periodic_block_active(
      input int interval_cycles,
      input int block_cycles,
      input logic [31:0] cycle
   );
      if ((interval_cycles <= 0) || (block_cycles <= 0)) begin
         periodic_block_active = 1'b0;
      end
      else begin
         periodic_block_active = ((cycle % interval_cycles) < block_cycles);
      end
   endfunction

   always_ff @(posedge clk_in) begin
      if (RESET || (~init_calib_complete)) begin
         stress_cycle_q <= '0;
      end
      else begin
         stress_cycle_q <= stress_cycle_q + 32'd1;
      end
   end

   // Command stalls block address/command acceptance. Data stalls only delay
   // read-data return, which is useful for replay/backpressure testing.
   assign cmd_stall_active =
      periodic_block_active(refresh_interval_cfg, refresh_block_cfg, stress_cycle_q) ||
      periodic_block_active(maint_interval_cfg, maint_block_cfg, stress_cycle_q) ||
      periodic_block_active(ready_stall_interval_cfg, ready_stall_block_cfg, stress_cycle_q);

   assign data_stall_active =
      periodic_block_active(refresh_interval_cfg, refresh_block_cfg, stress_cycle_q) ||
      periodic_block_active(maint_interval_cfg, maint_block_cfg, stress_cycle_q) ||
      periodic_block_active(read_gap_interval_cfg, read_gap_block_cfg, stress_cycle_q);

   // Simple init_calib_complete generator. While calibration is incomplete,
   // user logic remains in ui_clk_sync_rst.
   always_ff @(posedge clk_in) begin
      if (RESET) begin
         calib_cnt            <= '0;
         init_calib_complete  <= 1'b0;
      end
      else if (~init_calib_complete) begin
         if ((CALIB_DELAY_CYCLES <= 1) ||
             (calib_cnt >= (CALIB_DELAY_CYCLES - 1))) begin
            init_calib_complete <= 1'b1;
         end
         else begin
            calib_cnt <= calib_cnt + 8'd1;
         end
      end
   end

   // Accept only one outstanding write burst and one outstanding read burst.
   assign axi_awready      = init_calib_complete &&
                             (~cmd_stall_active) &&
                             (~turn_write_block) &&
                             (~write_active_q) &&
                             (~write_resp_pending_q);
   assign axi_wready       = init_calib_complete && (~cmd_stall_active) && write_active_q;
   assign axi_bvalid       = write_resp_pending_q;
   assign axi_bid          = write_id_q;
   assign axi_bresp        = MEM_BRESP;
      
   assign axi_arready      = init_calib_complete &&
                             (~cmd_stall_active) &&
                             (~turn_read_block) &&
                             (~read_active_q) &&
                             (~read_data_valid_q);
   assign axi_rid          = read_id_q;
   assign axi_rresp        = MEM_RRESP;
   assign axi_rvalid       = read_data_valid_q && (~data_stall_active);
   assign axi_rlast        = axi_rvalid && (read_beats_left_q == 9'd1);

   // Convert byte addresses to 128-bit word indexes.
   assign write_mem_index  = write_addr_q[MEM_WORD_MSB:4];
   assign read_mem_index   = read_addr_q[MEM_WORD_MSB:4];
   assign axi_rdata        = mem[read_mem_index];
   assign turn_write_block = (turnaround_cnt_q != 0) && last_cmd_was_read_q;
   assign turn_read_block  = (turnaround_cnt_q != 0) && (~last_cmd_was_read_q);
   assign write_data_fire  = write_active_q && axi_wvalid && axi_wready;
   assign read_data_fire   = axi_rvalid && axi_rready;

   // Optional bus turnaround penalty prevents immediate read/write direction
   // changes and approximates a coarse DDR scheduling delay.
   always_ff @(posedge clk_in) begin
      if (RESET || (~init_calib_complete)) begin
         turnaround_cnt_q   <= '0;
         last_cmd_was_read_q <= 1'b0;
      end
      else begin
         if (turnaround_cnt_q != 0) begin
            turnaround_cnt_q <= turnaround_cnt_q - 16'd1;
         end

         if (axi_awvalid && axi_awready) begin
            if (last_cmd_was_read_q && (turnaround_cycles_cfg > 0)) begin
               turnaround_cnt_q <= 16'(turnaround_cycles_cfg);
            end
            last_cmd_was_read_q <= 1'b0;
         end
         else if (axi_arvalid && axi_arready) begin
            if ((~last_cmd_was_read_q) && (turnaround_cycles_cfg > 0)) begin
               turnaround_cnt_q <= 16'(turnaround_cycles_cfg);
            end
            last_cmd_was_read_q <= 1'b1;
         end
      end
   end

   // AXI write path: latch AW, consume W beats, apply byte strobes, then hold
   // BVALID until the master accepts the response.
   always_ff @(posedge clk_in) begin
      if (RESET) begin
         write_addr_q           <= '0;
         write_beats_left_q     <= '0;
         write_id_q             <= '0;
         write_active_q         <= 1'b0;
         write_resp_pending_q   <= 1'b0;
      end
      else begin
         if (axi_awvalid && axi_awready) begin
            write_addr_q         <= axi_awaddr;
            write_beats_left_q   <= {1'b0, axi_awlen} + 9'd1;
            write_id_q           <= axi_awid;
            write_active_q       <= 1'b1;
         end

         if (write_data_fire) begin
            integer byte_idx;
            logic [127:0] next_word;

            // AXI WSTRB uses 1 to mean "write this byte".
            next_word = mem[write_mem_index];
            for (byte_idx = 0; byte_idx < 16; byte_idx++) begin
               if (axi_wstrb[byte_idx]) begin
                  next_word[byte_idx*8 +: 8] = axi_wdata[byte_idx*8 +: 8];
               end
            end
            mem[write_mem_index] <= next_word;
            write_addr_q         <= write_addr_q + AXI_WORD_BYTES;

            if (write_beats_left_q == 9'd1) begin
               write_beats_left_q   <= '0;
               write_active_q       <= 1'b0;
               write_resp_pending_q <= 1'b1;
            end
            else begin
               write_beats_left_q <= write_beats_left_q - 9'd1;
            end
         end

         if (axi_bvalid && axi_bready) begin
            write_resp_pending_q <= 1'b0;
         end
      end
   end

   // AXI read path: latch AR, wait the configured latency, then return one
   // 128-bit word per accepted R beat.
   always_ff @(posedge clk_in) begin
      if (RESET) begin
         read_addr_q         <= '0;
         read_beats_left_q   <= '0;
         read_id_q           <= '0;
         read_latency_q      <= '0;
         read_active_q       <= 1'b0;
         read_data_valid_q   <= 1'b0;
      end
      else begin
         if (axi_arvalid && axi_arready) begin
            read_addr_q       <= axi_araddr;
            read_beats_left_q <= {1'b0, axi_arlen} + 9'd1;
            read_id_q         <= axi_arid;
            read_latency_q    <= READ_LATENCY_CYCLES[7:0];
            read_active_q     <= 1'b1;
            read_data_valid_q <= 1'b0;
         end
         else if (read_active_q && ~read_data_valid_q) begin
            if (read_latency_q == 8'd0) begin
               read_data_valid_q <= 1'b1;
            end
            else begin
               read_latency_q <= read_latency_q - 8'd1;
            end
         end
         else if (read_data_fire) begin
            if (read_beats_left_q == 9'd1) begin
               read_beats_left_q <= '0;
               read_active_q     <= 1'b0;
               read_data_valid_q <= 1'b0;
            end
            else begin
               read_addr_q       <= read_addr_q + AXI_WORD_BYTES;
               read_beats_left_q <= read_beats_left_q - 9'd1;
               read_data_valid_q <= 1'b1;
            end
         end
      end
   end

endmodule
