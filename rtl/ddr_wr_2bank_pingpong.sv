`timescale 1ns/1ps

module ddr_wr_2bank_pingpong #(
   parameter int DATA_WIDTH           = 128,
   parameter int BANK_DEPTH           = 8192,
   parameter int COMMIT_TIMEOUT       = 2048,
   parameter int READ_LATENCY_CYCLES  = 2,
   parameter int SKID_DEPTH           = 4,
   parameter int PROG_EMPTY_THRESHOLD = 256
) (
   output logic [DATA_WIDTH-1:0] dout,
   output logic                  full,
   output logic                  empty,
   output logic                  valid,
   output logic                  prog_empty,
   output logic [13:0]           rd_data_count,
   output logic                  overrun,
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

   localparam int BANK_NUM         = 2;
   localparam int ADDR_WIDTH       = $clog2(BANK_DEPTH);
   localparam int LEVEL_WIDTH      = ADDR_WIDTH + 1;
   localparam int SKID_ADDR_WIDTH  = $clog2(SKID_DEPTH);
   localparam int MEMORY_SIZE_BITS = DATA_WIDTH * BANK_DEPTH;

   localparam logic [LEVEL_WIDTH-1:0] BANK_DEPTH_LEVEL =
      LEVEL_WIDTH'(BANK_DEPTH);
   localparam logic [LEVEL_WIDTH-1:0] PROG_EMPTY_LEVEL =
      LEVEL_WIDTH'(PROG_EMPTY_THRESHOLD);
   localparam logic [15:0] COMMIT_TIMEOUT_LEVEL =
      16'(COMMIT_TIMEOUT);
   localparam logic [SKID_ADDR_WIDTH:0] SKID_DEPTH_COUNT =
      (SKID_ADDR_WIDTH + 1)'(SKID_DEPTH);

   // CDC ownership.
   // Write side toggles commit bits when a bank is ready.
   // Read side toggles free bits after the committed bank has drained.
   logic [BANK_NUM-1:0] wr_commit_tgl;
   logic [BANK_NUM-1:0] rd_free_tgl;
   logic [LEVEL_WIDTH-1:0] wr_commit_len [0:BANK_NUM-1];

   (* ASYNC_REG = "true" *) logic [BANK_NUM-1:0] commit_tgl_rd_meta;
   (* ASYNC_REG = "true" *) logic [BANK_NUM-1:0] commit_tgl_rd_sync;
   logic [BANK_NUM-1:0] commit_tgl_rd_prev;
   logic [BANK_NUM-1:0] commit_edge_rd;

   (* ASYNC_REG = "true" *) logic [BANK_NUM-1:0] free_tgl_wr_meta;
   (* ASYNC_REG = "true" *) logic [BANK_NUM-1:0] free_tgl_wr_sync;
   logic [BANK_NUM-1:0] free_tgl_wr_prev;
   logic [BANK_NUM-1:0] free_edge_wr;

   // Write bank control.
   logic [BANK_NUM-1:0] wr_bank_free;
   logic                wr_bank_sel;
   logic                wr_active;
   logic [ADDR_WIDTH-1:0] wr_addr;
   logic [LEVEL_WIDTH-1:0] wr_level;
   logic [15:0]         wr_idle_timer;
   logic                wr_accept;
   logic                wr_commit_now;
   logic [LEVEL_WIDTH-1:0] wr_level_next;

   // Read bank control.
   logic [BANK_NUM-1:0] rd_bank_ready;
   logic [LEVEL_WIDTH-1:0] rd_bank_len [0:BANK_NUM-1];
   logic                rd_active;
   logic                rd_bank_sel;
   logic [ADDR_WIDTH-1:0] rd_addr;
   logic [LEVEL_WIDTH-1:0] rd_remaining;
   logic [LEVEL_WIDTH-1:0] rd_visible_count;

   // RAM read latency and skid buffer.
   // The skid buffer keeps AXI W data available while XPM read data is in flight.
   logic [DATA_WIDTH-1:0] ram_dout [0:BANK_NUM-1];
   logic                  ram_rd_fire;
   logic                  ram_rd_bank;
   logic [READ_LATENCY_CYCLES-1:0] ram_valid_pipe;
   logic [READ_LATENCY_CYCLES-1:0] ram_bank_pipe;
   logic [DATA_WIDTH-1:0] skid_mem [0:SKID_DEPTH-1];
   logic [SKID_ADDR_WIDTH-1:0] skid_wr_ptr;
   logic [SKID_ADDR_WIDTH-1:0] skid_rd_ptr;
   logic [SKID_ADDR_WIDTH:0] skid_count;
   logic [SKID_ADDR_WIDTH:0] pipe_count;
   logic [SKID_ADDR_WIDTH:0] prefetch_used;
   logic                  skid_push;
   logic                  skid_pop;
   logic [DATA_WIDTH-1:0] skid_push_data;
   logic                  can_issue_read;

   integer wr_i;
   integer rd_i;
   integer pipe_i;
   integer pipe_comb_i;
   integer level_comb_i;

   initial begin
      if (BANK_NUM != 2) begin
         $error("ddr_wr_2bank_pingpong supports exactly two banks.");
      end
      if (BANK_DEPTH != (1 << ADDR_WIDTH)) begin
         $error("BANK_DEPTH must be a power of two.");
      end
      if (READ_LATENCY_CYCLES < 1) begin
         $error("READ_LATENCY_CYCLES must be at least 1.");
      end
      if (SKID_DEPTH < (READ_LATENCY_CYCLES + 1)) begin
         $error("SKID_DEPTH must be larger than READ_LATENCY_CYCLES.");
      end
   end

   assign wr_rst_busy = rst;
   assign rd_rst_busy = rst;

   assign free_edge_wr   = free_tgl_wr_sync ^ free_tgl_wr_prev;
   assign commit_edge_rd = commit_tgl_rd_sync ^ commit_tgl_rd_prev;

   // Write side.
   // Only one bank is active for filling at a time.
   // The active bank is committed when it is full, explicitly flushed, or idle long enough.
   assign full          = ~wr_active;
   assign wr_accept     = wr_en && wr_active && (wr_level < BANK_DEPTH_LEVEL);
   assign wr_level_next = wr_level + LEVEL_WIDTH'(wr_accept);
   assign wr_commit_now = wr_active &&
                          (wr_level_next != '0) &&
                          ((wr_level_next >= BANK_DEPTH_LEVEL) ||
                           (flush && (wr_level_next != '0)) ||
                           ((wr_level != '0) &&
                            (wr_idle_timer >= COMMIT_TIMEOUT_LEVEL)));

   always_ff @(posedge wr_clk) begin
      if (rst) begin
         free_tgl_wr_meta <= '0;
         free_tgl_wr_sync <= '0;
         free_tgl_wr_prev <= '0;
      end
      else begin
         free_tgl_wr_meta <= rd_free_tgl;
         free_tgl_wr_sync <= free_tgl_wr_meta;
         free_tgl_wr_prev <= free_tgl_wr_sync;
      end
   end

   always_ff @(posedge wr_clk) begin
      if (rst) begin
         wr_bank_free     <= 2'b10;
         wr_bank_sel      <= 1'b0;
         wr_active        <= 1'b1;
         wr_addr          <= '0;
         wr_level         <= '0;
         wr_idle_timer    <= '0;
         wr_commit_tgl    <= '0;
         wr_commit_len[0] <= '0;
         wr_commit_len[1] <= '0;
         overrun          <= 1'b0;
      end
      else begin
         for (wr_i = 0; wr_i < BANK_NUM; wr_i++) begin
            if (free_edge_wr[wr_i]) begin
               wr_bank_free[wr_i] <= 1'b1;
            end
         end

         overrun <= wr_en && full;

         if (~wr_active) begin
            if (wr_bank_free[0] || free_edge_wr[0]) begin
               wr_bank_sel      <= 1'b0;
               wr_active        <= 1'b1;
               wr_bank_free[0]  <= 1'b0;
               wr_addr          <= '0;
               wr_level         <= '0;
               wr_idle_timer    <= '0;
            end
            else if (wr_bank_free[1] || free_edge_wr[1]) begin
               wr_bank_sel      <= 1'b1;
               wr_active        <= 1'b1;
               wr_bank_free[1]  <= 1'b0;
               wr_addr          <= '0;
               wr_level         <= '0;
               wr_idle_timer    <= '0;
            end
         end
         else begin
            if (wr_accept) begin
               wr_addr  <= wr_addr + 1'b1;
               wr_level <= wr_level_next;
            end

            if (wr_accept || wr_commit_now || (wr_level_next == '0)) begin
               wr_idle_timer <= '0;
            end
            else if (wr_idle_timer != 16'hffff) begin
               wr_idle_timer <= wr_idle_timer + 16'd1;
            end

            if (wr_commit_now) begin
               wr_commit_len[wr_bank_sel] <= wr_level_next;
               wr_commit_tgl[wr_bank_sel] <= ~wr_commit_tgl[wr_bank_sel];
               wr_addr                    <= '0;
               wr_level                   <= '0;
               wr_idle_timer              <= '0;

               if ((~wr_bank_sel) && (wr_bank_free[1] || free_edge_wr[1])) begin
                  wr_bank_sel     <= 1'b1;
                  wr_bank_free[1] <= 1'b0;
                  wr_active       <= 1'b1;
               end
               else if (wr_bank_sel && (wr_bank_free[0] || free_edge_wr[0])) begin
                  wr_bank_sel     <= 1'b0;
                  wr_bank_free[0] <= 1'b0;
                  wr_active       <= 1'b1;
               end
               else begin
                  wr_active       <= 1'b0;
               end
            end
         end
      end
   end

   // Read side CDC.
   // Commit length is latched once and stays stable until the read side frees the bank.
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

   always_ff @(posedge rd_clk) begin
      if (rst) begin
         rd_bank_ready  <= '0;
         rd_bank_len[0] <= '0;
         rd_bank_len[1] <= '0;
      end
      else begin
         for (rd_i = 0; rd_i < BANK_NUM; rd_i++) begin
            if (commit_edge_rd[rd_i]) begin
               rd_bank_ready[rd_i] <= 1'b1;
               rd_bank_len[rd_i]   <= wr_commit_len[rd_i];
            end
            else if (rd_active && (rd_bank_sel == rd_i[0]) &&
                     (rd_remaining == '0) && (skid_count == '0) &&
                     (ram_valid_pipe == '0)) begin
               rd_bank_ready[rd_i] <= 1'b0;
            end
         end
      end
   end

   // Read prefetch.
   // The skid FIFO keeps AXI-visible data decoupled from XPM latency.
   // Reads are only launched when there is room for both in-flight and already-buffered data.
   assign skid_pop       = rd_en && valid;
   assign prefetch_used  = skid_count + pipe_count;
   assign can_issue_read = rd_active &&
                           (rd_remaining != '0) &&
                           (prefetch_used < SKID_DEPTH_COUNT);
   assign ram_rd_fire    = can_issue_read;
   assign ram_rd_bank    = rd_bank_sel;

   always_ff @(posedge rd_clk) begin
      if (rst) begin
         rd_active    <= 1'b0;
         rd_bank_sel  <= 1'b0;
         rd_addr      <= '0;
         rd_remaining <= '0;
         rd_free_tgl  <= '0;
      end
      else begin
         if (~rd_active) begin
            if (rd_bank_ready[0]) begin
               rd_active    <= 1'b1;
               rd_bank_sel  <= 1'b0;
               rd_addr      <= '0;
               rd_remaining <= rd_bank_len[0];
            end
            else if (rd_bank_ready[1]) begin
               rd_active    <= 1'b1;
               rd_bank_sel  <= 1'b1;
               rd_addr      <= '0;
               rd_remaining <= rd_bank_len[1];
            end
         end
         else begin
            if (ram_rd_fire) begin
               rd_addr      <= rd_addr + 1'b1;
               rd_remaining <= rd_remaining - 1'b1;
            end

            if ((rd_remaining == '0) && (skid_count == '0) && (ram_valid_pipe == '0)) begin
               rd_free_tgl[rd_bank_sel] <= ~rd_free_tgl[rd_bank_sel];
               rd_active                <= 1'b0;
               rd_addr                  <= '0;
            end
         end
      end
   end

   always_comb begin
      pipe_count = '0;
      for (pipe_comb_i = 0; pipe_comb_i < READ_LATENCY_CYCLES; pipe_comb_i++) begin
         pipe_count = pipe_count +
                      {{SKID_ADDR_WIDTH{1'b0}}, ram_valid_pipe[pipe_comb_i]};
      end
   end

   always_ff @(posedge rd_clk) begin
      if (rst) begin
         ram_valid_pipe <= '0;
         ram_bank_pipe  <= '0;
      end
      else begin
         ram_valid_pipe[0] <= ram_rd_fire;
         ram_bank_pipe[0]  <= ram_rd_bank;
         for (pipe_i = 1; pipe_i < READ_LATENCY_CYCLES; pipe_i++) begin
            ram_valid_pipe[pipe_i] <= ram_valid_pipe[pipe_i-1];
            ram_bank_pipe[pipe_i]  <= ram_bank_pipe[pipe_i-1];
         end
      end
   end

   assign skid_push      = ram_valid_pipe[READ_LATENCY_CYCLES-1];
   assign skid_push_data = ram_bank_pipe[READ_LATENCY_CYCLES-1] ?
                           ram_dout[1] : ram_dout[0];

   always_ff @(posedge rd_clk) begin
      if (rst) begin
         skid_wr_ptr <= '0;
         skid_rd_ptr <= '0;
         skid_count  <= '0;
      end
      else begin
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
      end
   end

   always_comb begin
      rd_visible_count = {1'b0, rd_remaining} +
                         {{(LEVEL_WIDTH-SKID_ADDR_WIDTH){1'b0}}, skid_count} +
                         {{(LEVEL_WIDTH-SKID_ADDR_WIDTH){1'b0}}, pipe_count};
      for (level_comb_i = 0; level_comb_i < BANK_NUM; level_comb_i++) begin
         if (rd_bank_ready[level_comb_i] &&
             ((~rd_active) || (rd_bank_sel != level_comb_i[0]))) begin
            rd_visible_count = rd_visible_count + {1'b0, rd_bank_len[level_comb_i]};
         end
      end
   end

   assign dout          = skid_mem[skid_rd_ptr];
   assign valid         = skid_count != '0;
   assign empty         = ~valid && (rd_visible_count == '0);
   assign prog_empty    = rd_visible_count < {1'b0, PROG_EMPTY_LEVEL};
   assign rd_data_count = (|rd_visible_count[LEVEL_WIDTH:14]) ?
                          14'h3fff : rd_visible_count[13:0];

   genvar bank_g;
   generate
      for (bank_g = 0; bank_g < BANK_NUM; bank_g++) begin : gen_wr_bank_ram
         xpm_memory_tdpram #(
            .ADDR_WIDTH_A        (ADDR_WIDTH),
            .ADDR_WIDTH_B        (ADDR_WIDTH),
            .AUTO_SLEEP_TIME     (0),
            .BYTE_WRITE_WIDTH_A  (DATA_WIDTH),
            .BYTE_WRITE_WIDTH_B  (DATA_WIDTH),
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
            .USE_EMBEDDED_CONSTRAINT (0),
            .USE_MEM_INIT        (0),
            .WAKEUP_TIME         ("disable_sleep"),
            .WRITE_DATA_WIDTH_A  (DATA_WIDTH),
            .WRITE_DATA_WIDTH_B  (DATA_WIDTH),
            .WRITE_MODE_A        ("no_change"),
            .WRITE_MODE_B        ("no_change")
         ) bank_ram_u (
            .dbiterra       (),
            .dbiterrb       (),
            .douta          (),
            .doutb          (ram_dout[bank_g]),
            .sbiterra       (),
            .sbiterrb       (),
            .addra          (wr_addr),
            .addrb          (rd_addr),
            .clka           (wr_clk),
            .clkb           (rd_clk),
            .dina           (din),
            .dinb           ('0),
            .ena            (wr_accept && (wr_bank_sel == bank_g[0])),
            .enb            (ram_rd_fire && (rd_bank_sel == bank_g[0])),
            .injectdbiterra (1'b0),
            .injectdbiterrb (1'b0),
            .injectsbiterra (1'b0),
            .injectsbiterrb (1'b0),
            .regcea         (1'b0),
            .regceb         (1'b1),
            .rsta           (1'b0),
            .rstb           (rst),
            .sleep          (1'b0),
            .wea            (wr_accept && (wr_bank_sel == bank_g[0])),
            .web            (1'b0)
         );
      end
   endgenerate

endmodule
