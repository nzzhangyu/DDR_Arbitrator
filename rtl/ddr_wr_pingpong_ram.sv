`timescale 1ns/1ps

module ddr_wr_pingpong_ram #(
   parameter int DATA_WIDTH           = 128,
   parameter int BANK_DEPTH           = 8192,
   parameter int COMMIT_LEVEL         = 4096,
   parameter int COMMIT_TIMEOUT       = 2048,
   parameter int SKID_DEPTH           = 4,
   parameter int READ_LATENCY_CYCLES  = 2
) (
   output logic [DATA_WIDTH-1:0] dout,
   output logic                  full,
   output logic                  empty,
   output logic                  valid,
   output logic                  prog_empty,
   output logic [13:0]           rd_data_count,
   output logic                  wr_rst_busy,
   output logic                  rd_rst_busy,

   input  logic                  wr_clk,
   input  logic                  rd_clk,
   input  logic                  rst,
   input  logic [DATA_WIDTH-1:0] din,
   input  logic                  wr_en,
   input  logic                  rd_en,
   input  logic                  flush
);

   localparam int BANK_NUM          = 2;
   localparam int ADDR_WIDTH        = $clog2(BANK_DEPTH);
   localparam int LEVEL_WIDTH       = ADDR_WIDTH + 1;
   localparam int SKID_ADDR_WIDTH   = $clog2(SKID_DEPTH);
   localparam int MEMORY_SIZE_BITS  = DATA_WIDTH * BANK_DEPTH;
   localparam int BYTE_WRITE_WIDTH  = DATA_WIDTH;
   localparam logic [LEVEL_WIDTH-1:0] BANK_DEPTH_LEVEL   = LEVEL_WIDTH'(BANK_DEPTH);
   localparam logic [LEVEL_WIDTH-1:0] COMMIT_LEVEL_VALUE = LEVEL_WIDTH'(COMMIT_LEVEL);
   localparam logic [15:0]            COMMIT_TIMEOUT_VALUE = 16'(COMMIT_TIMEOUT);

   typedef enum logic [1:0] {
      WR_EMPTY,
      WR_FILLING,
      WR_COMMIT_PENDING
   } wr_bank_state_t;

   typedef enum logic [1:0] {
      RD_READY,
      RD_DRAINING,
      RD_EMPTY_PENDING
   } rd_bank_state_t;

   wr_bank_state_t wr_bank_state [0:BANK_NUM-1];
   rd_bank_state_t rd_bank_state [0:BANK_NUM-1];

   logic [BANK_NUM-1:0] wr_bank_free;
   logic                fill_bank;
   logic                fill_active;
   logic [ADDR_WIDTH-1:0] fill_addr;
   logic [LEVEL_WIDTH-1:0] fill_level;
   logic [15:0]         commit_timer;
   logic [LEVEL_WIDTH-1:0] fill_level_next;
   logic                wr_accept;
   logic                commit_now;

   logic [BANK_NUM-1:0] wr_commit_tgl;
   logic [LEVEL_WIDTH-1:0] wr_commit_len [0:BANK_NUM-1];

   (* ASYNC_REG = "true" *) logic [BANK_NUM-1:0] release_tgl_wr_meta;
   (* ASYNC_REG = "true" *) logic [BANK_NUM-1:0] release_tgl_wr_sync;
   logic [BANK_NUM-1:0] release_tgl_wr_prev;
   logic [BANK_NUM-1:0] release_edge_wr;

   (* ASYNC_REG = "true" *) logic [BANK_NUM-1:0] commit_tgl_rd_meta;
   (* ASYNC_REG = "true" *) logic [BANK_NUM-1:0] commit_tgl_rd_sync;
   logic [BANK_NUM-1:0] commit_tgl_rd_prev;
   logic [BANK_NUM-1:0] commit_edge_rd;

   logic [BANK_NUM-1:0] rd_release_tgl;
   logic [LEVEL_WIDTH-1:0] rd_bank_len [0:BANK_NUM-1];
   logic [LEVEL_WIDTH-1:0] rd_ready_len [0:BANK_NUM-1];

   logic                drain_active;
   logic                drain_bank;
   logic [ADDR_WIDTH-1:0] drain_addr;
   logic [LEVEL_WIDTH-1:0] drain_remaining;

   logic [ADDR_WIDTH-1:0] ram_rd_addr;
   logic                  ram_rd_fire;
   logic                  ram_rd_bank;
   logic                  ram_rd_last;
   logic [DATA_WIDTH-1:0] ram_dout [0:BANK_NUM-1];

   logic [READ_LATENCY_CYCLES-1:0] pipe_valid;
   logic [READ_LATENCY_CYCLES-1:0] pipe_bank;
   logic [READ_LATENCY_CYCLES-1:0] pipe_last;

   logic [DATA_WIDTH-1:0] skid_mem [0:SKID_DEPTH-1];
   logic [SKID_ADDR_WIDTH-1:0] skid_wr_ptr;
   logic [SKID_ADDR_WIDTH-1:0] skid_rd_ptr;
   logic [SKID_ADDR_WIDTH:0]   skid_count;
   logic [SKID_ADDR_WIDTH:0]   pipe_count;
   logic [SKID_ADDR_WIDTH:0]   prefetch_used;
   logic                       skid_push;
   logic                       skid_pop;
   logic [DATA_WIDTH-1:0]      skid_push_data;
   logic                       skid_push_last;
   logic                       skid_push_bank;

   logic [LEVEL_WIDTH:0]       rd_visible_count;
   logic [LEVEL_WIDTH:0]       rd_ready_sum;

   integer wr_i;
   integer pipe_i;
   integer rd_i;
   integer comb_i;

   initial begin
      if (BANK_NUM != 2) begin
         $error("ddr_wr_pingpong_ram supports exactly two banks.");
      end
      if (SKID_DEPTH < 2) begin
         $error("SKID_DEPTH must be at least 2.");
      end
      if (READ_LATENCY_CYCLES < 1) begin
         $error("READ_LATENCY_CYCLES must be at least 1.");
      end
   end

   assign wr_rst_busy = rst;
   assign rd_rst_busy = rst;

   assign release_edge_wr = release_tgl_wr_sync ^ release_tgl_wr_prev;
   assign commit_edge_rd  = commit_tgl_rd_sync ^ commit_tgl_rd_prev;

   assign wr_accept       = wr_en && fill_active && (fill_level < BANK_DEPTH_LEVEL);
   assign fill_level_next = fill_level + {{(LEVEL_WIDTH-1){1'b0}}, wr_accept};
   assign commit_now      = fill_active &&
                            (fill_level_next != '0) &&
                            ((fill_level_next >= BANK_DEPTH_LEVEL) ||
                             (fill_level_next >= COMMIT_LEVEL_VALUE) ||
                             (flush && (fill_level_next != '0)) ||
                             ((fill_level != '0) &&
                              (commit_timer >= COMMIT_TIMEOUT_VALUE)));

   assign full = ~fill_active;

   always_ff @(posedge wr_clk) begin
      if (rst) begin
         release_tgl_wr_meta <= '0;
         release_tgl_wr_sync <= '0;
         release_tgl_wr_prev <= '0;
      end
      else begin
         release_tgl_wr_meta <= rd_release_tgl;
         release_tgl_wr_sync <= release_tgl_wr_meta;
         release_tgl_wr_prev <= release_tgl_wr_sync;
      end
   end

   always_ff @(posedge wr_clk) begin
      if (rst) begin
         fill_bank              <= 1'b0;
         fill_active            <= 1'b1;
         fill_addr              <= '0;
         fill_level             <= '0;
         commit_timer           <= '0;
         wr_bank_free           <= 2'b10;
         wr_commit_tgl          <= '0;
         wr_commit_len[0]       <= '0;
         wr_commit_len[1]       <= '0;
         wr_bank_state[0]       <= WR_FILLING;
         wr_bank_state[1]       <= WR_EMPTY;
      end
      else begin
         for (wr_i = 0; wr_i < BANK_NUM; wr_i++) begin
            if (release_edge_wr[wr_i]) begin
               wr_bank_free[wr_i] <= 1'b1;
               wr_bank_state[wr_i] <= WR_EMPTY;
            end
         end

         if (~fill_active) begin
            if (wr_bank_free[0]) begin
               fill_bank        <= 1'b0;
               fill_active      <= 1'b1;
               fill_addr        <= '0;
               fill_level       <= '0;
               commit_timer     <= '0;
               wr_bank_free[0]  <= 1'b0;
               wr_bank_state[0] <= WR_FILLING;
            end
            else if (wr_bank_free[1]) begin
               fill_bank        <= 1'b1;
               fill_active      <= 1'b1;
               fill_addr        <= '0;
               fill_level       <= '0;
               commit_timer     <= '0;
               wr_bank_free[1]  <= 1'b0;
               wr_bank_state[1] <= WR_FILLING;
            end
         end
         else begin
            if (wr_accept) begin
               fill_addr  <= fill_addr + 1'b1;
               fill_level <= fill_level_next;
            end

            if (fill_level_next != '0) begin
               if (commit_now) begin
                  commit_timer <= '0;
               end
               else if (commit_timer != 16'hffff) begin
                  commit_timer <= commit_timer + 16'd1;
               end
            end
            else begin
               commit_timer <= '0;
            end

            if (commit_now) begin
               wr_commit_len[fill_bank] <= fill_level_next;
               wr_commit_tgl[fill_bank] <= ~wr_commit_tgl[fill_bank];
               wr_bank_state[fill_bank] <= WR_COMMIT_PENDING;

               if (wr_bank_free[~fill_bank]) begin
                  fill_bank                 <= ~fill_bank;
                  fill_active               <= 1'b1;
                  fill_addr                 <= '0;
                  fill_level                <= '0;
                  wr_bank_free[~fill_bank]  <= 1'b0;
                  wr_bank_state[~fill_bank] <= WR_FILLING;
               end
               else begin
                  fill_active <= 1'b0;
                  fill_addr   <= '0;
                  fill_level  <= '0;
               end
            end
         end
      end
   end

   genvar bank_gen;
   generate
      for (bank_gen = 0; bank_gen < BANK_NUM; bank_gen++) begin : gen_bank_ram
         xpm_memory_tdpram #(
            .ADDR_WIDTH_A        (ADDR_WIDTH),
            .ADDR_WIDTH_B        (ADDR_WIDTH),
            .AUTO_SLEEP_TIME     (0),
            .BYTE_WRITE_WIDTH_A  (BYTE_WRITE_WIDTH),
            .BYTE_WRITE_WIDTH_B  (BYTE_WRITE_WIDTH),
            .CASCADE_HEIGHT      (0),
            .CLOCKING_MODE       ("independent_clock"),
            .ECC_MODE            ("no_ecc"),
            .MEMORY_INIT_FILE    ("none"),
            .MEMORY_INIT_PARAM   ("0"),
            .MEMORY_OPTIMIZATION ("true"),
            .MEMORY_PRIMITIVE    ("block"),
            .MEMORY_SIZE         (MEMORY_SIZE_BITS),
            .MESSAGE_CONTROL     (0),
            .READ_DATA_WIDTH_A   (DATA_WIDTH),
            .READ_DATA_WIDTH_B   (DATA_WIDTH),
            .READ_LATENCY_A      (1),
            .READ_LATENCY_B      (READ_LATENCY_CYCLES),
            .READ_RESET_VALUE_A  ("0"),
            .READ_RESET_VALUE_B  ("0"),
            .RST_MODE_A          ("SYNC"),
            .RST_MODE_B          ("SYNC"),
            .SIM_ASSERT_CHK      (0),
            .USE_EMBEDDED_CONSTRAINT(0),
            .USE_MEM_INIT        (0),
            .WAKEUP_TIME         ("disable_sleep"),
            .WRITE_DATA_WIDTH_A  (DATA_WIDTH),
            .WRITE_DATA_WIDTH_B  (DATA_WIDTH),
            .WRITE_MODE_A        ("no_change"),
            .WRITE_MODE_B        ("no_change")
         ) bank_ram_uut (
            .dbiterra       (),
            .douta          (),
            .doutb          (ram_dout[bank_gen]),
            .sbiterra       (),
            .addra          (fill_addr),
            .addrb          (ram_rd_addr),
            .clka           (wr_clk),
            .clkb           (rd_clk),
            .dina           (din),
            .dinb           ('0),
            .ena            (1'b1),
            .enb            (ram_rd_fire && (ram_rd_bank == bank_gen[0])),
            .injectdbiterra (1'b0),
            .injectdbiterrb (1'b0),
            .injectsbiterra (1'b0),
            .injectsbiterrb (1'b0),
            .regcea         (1'b1),
            .regceb         (1'b1),
            .rsta           (rst),
            .rstb           (rst),
            .sleep          (1'b0),
            .wea            ({(DATA_WIDTH/BYTE_WRITE_WIDTH){wr_accept && (fill_bank == bank_gen[0])}}),
            .web            ('0),
            .dbiterrb       (),
            .sbiterrb       ()
         );
      end
   endgenerate

   always_ff @(posedge rd_clk) begin
      if (rst) begin
         commit_tgl_rd_meta <= '0;
         commit_tgl_rd_sync <= '0;
         commit_tgl_rd_prev <= '0;
      end
      else begin
         commit_tgl_rd_meta <= wr_commit_tgl;
         commit_tgl_rd_sync <= commit_tgl_rd_meta;
         commit_tgl_rd_prev <= commit_tgl_rd_sync;
      end
   end

   always_comb begin
      pipe_count = '0;
      for (comb_i = 0; comb_i < READ_LATENCY_CYCLES; comb_i++) begin
         pipe_count = pipe_count + {{SKID_ADDR_WIDTH{1'b0}}, pipe_valid[comb_i]};
      end
   end

   assign prefetch_used = skid_count + pipe_count;
   assign ram_rd_fire   = drain_active && (prefetch_used < SKID_DEPTH[SKID_ADDR_WIDTH:0]);
   assign ram_rd_bank   = drain_bank;
   assign ram_rd_addr   = drain_addr;
   assign ram_rd_last   = ram_rd_fire && (drain_remaining == {{LEVEL_WIDTH-1{1'b0}}, 1'b1});

   assign skid_push      = pipe_valid[READ_LATENCY_CYCLES-1];
   assign skid_push_bank = pipe_bank[READ_LATENCY_CYCLES-1];
   assign skid_push_last = pipe_last[READ_LATENCY_CYCLES-1];
   assign skid_push_data = skid_push_bank ? ram_dout[1] : ram_dout[0];
   assign skid_pop       = rd_en && (skid_count != '0);

   always_ff @(posedge rd_clk) begin
      if (rst) begin
         rd_release_tgl   <= '0;
         drain_active     <= 1'b0;
         drain_bank       <= 1'b0;
         drain_addr       <= '0;
         drain_remaining  <= '0;
         pipe_valid       <= '0;
         pipe_bank        <= '0;
         pipe_last        <= '0;
         skid_wr_ptr      <= '0;
         skid_rd_ptr      <= '0;
         skid_count       <= '0;
         rd_bank_len[0]   <= '0;
         rd_bank_len[1]   <= '0;
         rd_ready_len[0]  <= '0;
         rd_ready_len[1]  <= '0;
         rd_bank_state[0] <= RD_EMPTY_PENDING;
         rd_bank_state[1] <= RD_EMPTY_PENDING;
      end
      else begin
         for (rd_i = 0; rd_i < BANK_NUM; rd_i++) begin
            if (commit_edge_rd[rd_i]) begin
               rd_bank_len[rd_i]   <= wr_commit_len[rd_i];
               rd_ready_len[rd_i]  <= wr_commit_len[rd_i];
               rd_bank_state[rd_i] <= RD_READY;
            end
         end

         if (~drain_active) begin
            if (rd_ready_len[0] != '0) begin
               drain_active     <= 1'b1;
               drain_bank       <= 1'b0;
               drain_addr       <= '0;
               drain_remaining  <= rd_ready_len[0];
               rd_ready_len[0]  <= '0;
               rd_bank_state[0] <= RD_DRAINING;
            end
            else if (rd_ready_len[1] != '0) begin
               drain_active     <= 1'b1;
               drain_bank       <= 1'b1;
               drain_addr       <= '0;
               drain_remaining  <= rd_ready_len[1];
               rd_ready_len[1]  <= '0;
               rd_bank_state[1] <= RD_DRAINING;
            end
         end

         if (ram_rd_fire) begin
            drain_addr <= drain_addr + 1'b1;
            if (drain_remaining == {{LEVEL_WIDTH-1{1'b0}}, 1'b1}) begin
               drain_remaining <= '0;
               drain_active    <= 1'b0;
            end
            else begin
               drain_remaining <= drain_remaining - 1'b1;
            end
         end

         pipe_valid[0] <= ram_rd_fire;
         pipe_bank[0]  <= ram_rd_bank;
         pipe_last[0]  <= ram_rd_last;
         for (pipe_i = 1; pipe_i < READ_LATENCY_CYCLES; pipe_i++) begin
            pipe_valid[pipe_i] <= pipe_valid[pipe_i-1];
            pipe_bank[pipe_i]  <= pipe_bank[pipe_i-1];
            pipe_last[pipe_i]  <= pipe_last[pipe_i-1];
         end

         if (skid_push) begin
            skid_mem[skid_wr_ptr] <= skid_push_data;
            skid_wr_ptr           <= skid_wr_ptr + 1'b1;
         end

         if (skid_pop) begin
            skid_rd_ptr <= skid_rd_ptr + 1'b1;
         end

         unique case ({skid_push, skid_pop})
            2'b10: skid_count <= skid_count + 1'b1;
            2'b01: skid_count <= skid_count - 1'b1;
            default: skid_count <= skid_count;
         endcase

         if (skid_push && skid_push_last) begin
            rd_release_tgl[skid_push_bank] <= ~rd_release_tgl[skid_push_bank];
            rd_bank_state[skid_push_bank]  <= RD_EMPTY_PENDING;
            rd_bank_len[skid_push_bank]    <= '0;
         end
      end
   end

   always_comb begin
      rd_ready_sum = {1'b0, rd_ready_len[0]} +
                     {1'b0, rd_ready_len[1]} +
                     {1'b0, drain_remaining};
      rd_visible_count = rd_ready_sum +
                         {{(LEVEL_WIDTH+1-SKID_ADDR_WIDTH-1){1'b0}}, skid_count} +
                         {{(LEVEL_WIDTH+1-SKID_ADDR_WIDTH-1){1'b0}}, pipe_count};
   end

   assign dout       = skid_mem[skid_rd_ptr];
   assign valid      = (skid_count != '0);
   assign empty      = ~valid;
   assign prog_empty = (rd_visible_count < 14'd256);
   assign rd_data_count = (rd_visible_count > (LEVEL_WIDTH+1)'(14'h3fff)) ?
                          14'h3fff : 14'(rd_visible_count);

endmodule
