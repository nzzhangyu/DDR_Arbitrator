`timescale 1ns/1ps

// Lightweight DDR4 native-app mock for fast simulation.
// The model keeps a small 128-bit word memory and a simple calibration delay.
module ddr4_fast_mock #(
   parameter int APP_ADDR_WIDTH      = 32,
   parameter int MEM_WORDS           = 16384,
   parameter int CALIB_DELAY_CYCLES  = 32,
   parameter int READ_LATENCY_CYCLES = 2
) (
   input  logic                      clk_in,
   input  logic                      RESET,

   output logic                      ui_clk,
   output logic                      ui_clk_sync_rst,
   output logic                      init_calib_complete,
   output logic                      dbg_clk,

   input  logic [APP_ADDR_WIDTH-1:0] app_addr,
   input  logic [2:0]                app_cmd,
   input  logic                      app_en,
   output logic                      app_rdy,

   input  logic [127:0]              app_wdf_data,
   input  logic [15:0]               app_wdf_mask,
   input  logic                      app_wdf_wren,
   input  logic                      app_wdf_end,
   output logic                      app_wdf_rdy,

   output logic [127:0]              app_rd_data,
   output logic                      app_rd_data_valid,
   output logic                      app_rd_data_end
);

   localparam int MEM_ADDR_BITS = $clog2(MEM_WORDS);
   localparam int MEM_WORD_MSB  = 4 + MEM_ADDR_BITS - 1;
   localparam logic [2:0] APP_CMD_WRITE = 3'b000;
   localparam logic [2:0] APP_CMD_READ  = 3'b001;

   logic [127:0] mem [0:MEM_WORDS-1];
   logic [7:0]   calib_cnt;

   logic [APP_ADDR_WIDTH-1:0] write_addr_q;
   logic                      write_cmd_pending_q;

   logic [APP_ADDR_WIDTH-1:0] read_addr_pipe [0:READ_LATENCY_CYCLES];
   logic [READ_LATENCY_CYCLES:0] read_valid_pipe;

   logic [MEM_ADDR_BITS-1:0] write_mem_index;
   logic [MEM_ADDR_BITS-1:0] read_mem_index;

   integer i;

   initial begin
      for (i = 0; i < MEM_WORDS; i++) begin
         mem[i] = '0;
      end
   end

   assign ui_clk = clk_in;
   assign dbg_clk = clk_in;
   assign ui_clk_sync_rst = RESET | (~init_calib_complete);
   assign app_rdy = init_calib_complete && (~write_cmd_pending_q);
   assign app_wdf_rdy = init_calib_complete;
   assign write_mem_index = write_addr_q[MEM_WORD_MSB:4];
   assign read_mem_index = read_addr_pipe[READ_LATENCY_CYCLES][MEM_WORD_MSB:4];
   assign app_rd_data = mem[read_mem_index];
   assign app_rd_data_valid = read_valid_pipe[READ_LATENCY_CYCLES];
   assign app_rd_data_end = app_rd_data_valid;

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

   always_ff @(posedge clk_in) begin
      if (RESET) begin
         write_addr_q        <= '0;
         write_cmd_pending_q <= 1'b0;
      end
      else begin
         if (app_en && app_rdy && (app_cmd == APP_CMD_WRITE) &&
             app_wdf_wren && app_wdf_rdy && app_wdf_end) begin
            integer byte_idx;
            logic [127:0] next_word;
            logic [MEM_ADDR_BITS-1:0] direct_write_index;

            direct_write_index = app_addr[MEM_WORD_MSB:4];
            next_word = mem[direct_write_index];
            for (byte_idx = 0; byte_idx < 16; byte_idx++) begin
               if (~app_wdf_mask[byte_idx]) begin
                  next_word[byte_idx*8 +: 8] = app_wdf_data[byte_idx*8 +: 8];
               end
            end
            mem[direct_write_index] <= next_word;
         end
         else if (app_en && app_rdy && (app_cmd == APP_CMD_WRITE)) begin
            write_addr_q        <= app_addr;
            write_cmd_pending_q <= 1'b1;
         end

         if (write_cmd_pending_q && app_wdf_wren && app_wdf_rdy && app_wdf_end) begin
            integer byte_idx;
            logic [127:0] next_word;

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

   always_ff @(posedge clk_in) begin
      if (RESET) begin
         read_valid_pipe <= '0;
         for (int stage = 0; stage <= READ_LATENCY_CYCLES; stage++) begin
            read_addr_pipe[stage] <= '0;
         end
      end
      else begin
         read_valid_pipe[0] <= app_en && app_rdy && (app_cmd == APP_CMD_READ);
         read_addr_pipe[0]  <= app_addr;

         for (int stage = 1; stage <= READ_LATENCY_CYCLES; stage++) begin
            read_valid_pipe[stage] <= read_valid_pipe[stage-1];
            read_addr_pipe[stage]  <= read_addr_pipe[stage-1];
         end
      end
   end

endmodule
