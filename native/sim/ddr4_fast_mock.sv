`timescale 1ns/1ps

// Lightweight DDR4 native-app mock for fast simulation.
// The model keeps a small 128-bit word memory and can inject simple
// ready/data stalls to exercise MIG app_* backpressure.
module ddr4_fast_mock #(
   parameter int APP_ADDR_WIDTH      = 32,
   parameter int MEM_WORDS           = 16384,
   parameter int CALIB_DELAY_CYCLES  = 32,
   parameter int READ_LATENCY_CYCLES = 2,
   parameter int REFRESH_INTERVAL_CYCLES = 0,
   parameter int REFRESH_BLOCK_CYCLES    = 0,
   parameter int MAINT_INTERVAL_CYCLES   = 0,
   parameter int MAINT_BLOCK_CYCLES      = 0,
   parameter int READY_STALL_INTERVAL_CYCLES = 0,
   parameter int READY_STALL_CYCLES          = 0,
   parameter int READ_DATA_GAP_INTERVAL_CYCLES = 0,
   parameter int READ_DATA_GAP_CYCLES          = 0,
   parameter int TURNAROUND_CYCLES = 0
) (
   input  logic                      clk_in,
   input  logic                      RESET,

   // MIG-style user clock/status outputs.
   output logic                      ui_clk,
   output logic                      ui_clk_sync_rst,
   output logic                      init_calib_complete,
   output logic                      dbg_clk,

   // Native MIG app command channel.
   input  logic [APP_ADDR_WIDTH-1:0] app_addr,
   input  logic [2:0]                app_cmd,
   input  logic                      app_en,
   output logic                      app_rdy,

   // Native MIG write-data FIFO channel.
   input  logic [127:0]              app_wdf_data,
   input  logic [15:0]               app_wdf_mask,
   input  logic                      app_wdf_wren,
   input  logic                      app_wdf_end,
   output logic                      app_wdf_rdy,

   // Native MIG read-data channel.
   output logic [127:0]              app_rd_data,
   output logic                      app_rd_data_valid,
   output logic                      app_rd_data_end
);

   // Memory is addressed as 128-bit words. app_addr bits [3:0] select bytes
   // within a word and are ignored by the array index.
   localparam int MEM_ADDR_BITS = $clog2(MEM_WORDS);
   localparam int MEM_WORD_MSB  = 4 + MEM_ADDR_BITS - 1;
   localparam logic [2:0] APP_CMD_WRITE = 3'b000;
   localparam logic [2:0] APP_CMD_READ  = 3'b001;

   // Small behavioral storage used only by simulation.
   logic [127:0] mem [0:MEM_WORDS-1];
   logic [7:0]   calib_cnt;

   logic [APP_ADDR_WIDTH-1:0] write_addr_q;
   logic                      write_cmd_pending_q;

   // Read commands move through this pipe before data appears on app_rd_data.
   logic [APP_ADDR_WIDTH-1:0] read_addr_pipe [0:READ_LATENCY_CYCLES];
   logic [READ_LATENCY_CYCLES:0] read_valid_pipe;

   logic [MEM_ADDR_BITS-1:0] write_mem_index;
   logic [MEM_ADDR_BITS-1:0] read_mem_index;
   // Stress knobs model coarse DDR4 unavailability windows without pulling in
   // the full MIG simulation model.
   logic [31:0]              stress_cycle_q;
   logic [15:0]              turnaround_cnt_q;
   logic                     last_cmd_was_read_q;
   logic                     cmd_stall_active;
   logic                     data_stall_active;
   logic                     read_pipe_stall;
   logic                     turn_write_block;
   logic                     turn_read_block;
   logic                     write_cmd_fire;
   logic                     read_cmd_fire;
   int                       refresh_interval_cfg;
   int                       refresh_block_cfg;
   int                       maint_interval_cfg;
   int                       maint_block_cfg;
   int                       ready_stall_interval_cfg;
   int                       ready_stall_block_cfg;
   int                       read_gap_interval_cfg;
   int                       read_gap_block_cfg;
   int                       turnaround_cycles_cfg;

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

   // Command stalls block app_en acceptance. Data stalls hold the read pipe at
   // its output stage, preserving read data until the stall clears.
   assign cmd_stall_active =
      periodic_block_active(refresh_interval_cfg, refresh_block_cfg, stress_cycle_q) ||
      periodic_block_active(maint_interval_cfg, maint_block_cfg, stress_cycle_q) ||
      periodic_block_active(ready_stall_interval_cfg, ready_stall_block_cfg, stress_cycle_q);

   assign data_stall_active =
      periodic_block_active(refresh_interval_cfg, refresh_block_cfg, stress_cycle_q) ||
      periodic_block_active(maint_interval_cfg, maint_block_cfg, stress_cycle_q) ||
      periodic_block_active(read_gap_interval_cfg, read_gap_block_cfg, stress_cycle_q);

   // Block command acceptance during read output stalls so the latency pipe
   // cannot overwrite a valid response.
   assign read_pipe_stall = read_valid_pipe[READ_LATENCY_CYCLES] && data_stall_active;
   assign turn_write_block = (turnaround_cnt_q != 0) && last_cmd_was_read_q;
   assign turn_read_block  = (turnaround_cnt_q != 0) && (~last_cmd_was_read_q);
   assign app_rdy = init_calib_complete &&
                    (~write_cmd_pending_q) &&
                    (~cmd_stall_active) &&
                    (~read_pipe_stall) &&
                    (~(turn_write_block && (app_cmd == APP_CMD_WRITE))) &&
                    (~(turn_read_block && (app_cmd == APP_CMD_READ)));
   assign app_wdf_rdy = init_calib_complete && (~cmd_stall_active);
   assign write_mem_index = write_addr_q[MEM_WORD_MSB:4];
   assign read_mem_index = read_addr_pipe[READ_LATENCY_CYCLES][MEM_WORD_MSB:4];
   assign app_rd_data = mem[read_mem_index];
   assign app_rd_data_valid = read_valid_pipe[READ_LATENCY_CYCLES] && (~data_stall_active);
   assign app_rd_data_end = app_rd_data_valid;
   assign write_cmd_fire = app_en && app_rdy && (app_cmd == APP_CMD_WRITE);
   assign read_cmd_fire  = app_en && app_rdy && (app_cmd == APP_CMD_READ);

   always_ff @(posedge clk_in) begin
      if (RESET) begin
         calib_cnt           <= '0;
         init_calib_complete <= 1'b0;
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

   // Simple init_calib_complete generator. While calibration is incomplete,
   // user logic remains in ui_clk_sync_rst.
   always_ff @(posedge clk_in) begin
      if (RESET) begin
         write_addr_q        <= '0;
         write_cmd_pending_q <= 1'b0;
      end
      else begin
         if (write_cmd_fire &&
             app_wdf_wren && app_wdf_rdy && app_wdf_end) begin
            integer byte_idx;
            logic [127:0] next_word;
            logic [MEM_ADDR_BITS-1:0] direct_write_index;

            // Same-cycle command/data case.
            direct_write_index = app_addr[MEM_WORD_MSB:4];
            next_word = mem[direct_write_index];
            for (byte_idx = 0; byte_idx < 16; byte_idx++) begin
               if (~app_wdf_mask[byte_idx]) begin
                  next_word[byte_idx*8 +: 8] = app_wdf_data[byte_idx*8 +: 8];
               end
            end
            mem[direct_write_index] <= next_word;
         end
         else if (write_cmd_fire) begin
            write_addr_q        <= app_addr;
            write_cmd_pending_q <= 1'b1;
         end

         if (write_cmd_pending_q && app_wdf_wren && app_wdf_rdy && app_wdf_end) begin
            integer byte_idx;
            logic [127:0] next_word;

            // Delayed write-data case after a command has been accepted.
            next_word = mem[write_mem_index];
            for (byte_idx = 0; byte_idx < 16; byte_idx++) begin
               if (~app_wdf_mask[byte_idx]) begin
                  next_word[byte_idx*8 +: 8] = app_wdf_data[byte_idx*8 +: 8];
               end
            end
            mem[write_mem_index] <= next_word;
            write_cmd_pending_q  <= 1'b0;
         end
      end
   end

   // Write path supports either same-cycle command+data or a command followed
   // later by one write-data beat. app_wdf_mask uses 0 to mean "write byte".
   // Optional bus turnaround penalty prevents immediate read/write direction
   // changes and approximates a coarse DDR scheduling delay.
   always_ff @(posedge clk_in) begin
      if (RESET || (~init_calib_complete)) begin
         turnaround_cnt_q    <= '0;
         last_cmd_was_read_q <= 1'b0;
      end
      else begin
         if (turnaround_cnt_q != 0) begin
            turnaround_cnt_q <= turnaround_cnt_q - 16'd1;
         end

         if (write_cmd_fire) begin
            if (last_cmd_was_read_q && (turnaround_cycles_cfg > 0)) begin
               turnaround_cnt_q <= 16'(turnaround_cycles_cfg);
            end
            last_cmd_was_read_q <= 1'b0;
         end
         else if (read_cmd_fire) begin
            if ((~last_cmd_was_read_q) && (turnaround_cycles_cfg > 0)) begin
               turnaround_cnt_q <= 16'(turnaround_cycles_cfg);
            end
            last_cmd_was_read_q <= 1'b1;
         end
      end
   end

   // Read path shifts accepted read addresses through a latency pipe. When the
   // output is stalled, the pipe holds its current contents.
   always_ff @(posedge clk_in) begin
      if (RESET) begin
         read_valid_pipe <= '0;
         for (int stage = 0; stage <= READ_LATENCY_CYCLES; stage++) begin
            read_addr_pipe[stage] <= '0;
         end
      end
      else if (~read_pipe_stall) begin
         read_valid_pipe[0] <= read_cmd_fire;
         read_addr_pipe[0]  <= app_addr;

         for (int stage = 1; stage <= READ_LATENCY_CYCLES; stage++) begin
            read_valid_pipe[stage] <= read_valid_pipe[stage-1];
            read_addr_pipe[stage]  <= read_addr_pipe[stage-1];
         end
      end
   end

endmodule
