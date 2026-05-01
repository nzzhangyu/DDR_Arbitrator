`timescale 1ns/1ps

module tb_ddr4_controller_mock;

   localparam int ADDR_WIDTH          = 20;
   localparam int AXI_ADDR_WIDTH      = ADDR_WIDTH + 4;
   localparam int AXI_ID_WIDTH        = 1;
   localparam int DEFAULT_SIM_VIEWS   = 2;
   localparam int TOTAL_FRAME_VIEWS   = 2320;
   localparam int VIEW_PERIOD_US      = 232;
   localparam int CLK_PERIOD_PS       = 5000;
   localparam int VIEW_PERIOD_CYCLES  = (VIEW_PERIOD_US * 1000000) / CLK_PERIOD_PS;
   localparam int FTPS_PER_SLICE      = 30;
   localparam int CHANNELS_PER_SLICE  = 48;
   localparam int SLICES_PER_VIEW     = 128;
   localparam int SAMPLE_BITS         = 16;
   localparam int AXI_DATA_BITS       = 128;
   localparam int SAMPLES_PER_BEAT    = AXI_DATA_BITS / SAMPLE_BITS;
   localparam int SLICE_HEADER_BEATS  = 2;
   localparam int SLICE_PAYLOAD_SAMPLES = FTPS_PER_SLICE * CHANNELS_PER_SLICE;
   localparam int SLICE_PAYLOAD_BEATS =
      (SLICE_PAYLOAD_SAMPLES + SAMPLES_PER_BEAT - 1) / SAMPLES_PER_BEAT;
   localparam int SLICE_TOTAL_BEATS   = SLICE_HEADER_BEATS + SLICE_PAYLOAD_BEATS;
   localparam int VIEW_TOTAL_BEATS    = SLICES_PER_VIEW * SLICE_TOTAL_BEATS;
   localparam int MOCK_MEM_WORDS      = 1 << ADDR_WIDTH;
   localparam int MOCK_MAX_VIEWS      = MOCK_MEM_WORDS / VIEW_TOTAL_BEATS;
   localparam int TIMEOUT_CYCLES      = 1200000;

   logic                  clk;
   logic                  reset;
   logic                  c0_sys_clk_p;
   logic                  c0_sys_clk_n;
   logic                  rst_local_t_ddr_clk;
   logic                  data_from_ddr_en;
   logic [127:0]          data_from_ddr_dd;
   logic                  user_r_rd_en;
   logic                  ddr_rd_req;
   logic                  req_stop;
   logic                  rp_back_en;
   logic [ADDR_WIDTH-1:0] rp_back_view_addr;
   logic                  Fault_inject_en;
   logic                  make_data_on;
   logic                  make_data_p_edge;
   logic [15:0]           view_size;

   logic                  c0_ddr4_act_n;
   logic [16:0]           c0_ddr4_adr;
   logic [1:0]            c0_ddr4_ba;
   logic [1:0]            c0_ddr4_bg;
   logic [0:0]            c0_ddr4_cke;
   logic [0:0]            c0_ddr4_odt;
   logic [0:0]            c0_ddr4_cs_n;
   logic [0:0]            c0_ddr4_ck_t;
   logic [0:0]            c0_ddr4_ck_c;
   logic                  c0_ddr4_reset_n;
   wire  [1:0]            c0_ddr4_dm_dbi_n;
   wire  [15:0]           c0_ddr4_dq;
   wire  [1:0]            c0_ddr4_dqs_c;
   wire  [1:0]            c0_ddr4_dqs_t;
   logic                  dbg_clk;
   logic                  ui_clk;
   logic                  ui_clk_sync_rst;
   logic                  init_calib_complete;
   logic                  user_r_valid;
   logic [127:0]          user_r_data;
   logic                  user_r_empty;
   logic                  ddr_overrun;
   logic                  ddr_warning;
   logic                  wr_fifo_overrun;
   logic                  ddr_wr_fifo_empty;
   logic                  ddr_rd_empty;
   logic                  make_data_p_edge_ddr_clk;
   logic                  clk_backbone;

   logic [127:0] expected_q[$];
   logic [127:0] expected_word;
   int           sent_count;
   int           recv_count;
   int           mismatch_count;
   int           overflow_count;
   int           timeout_count;
   int           sim_view_count;
   int           expected_total_beats;
   bit           use_hash_scoreboard;
   logic [63:0]  expected_hash;
   logic [63:0]  actual_hash;
   string        scoreboard_mode;
   bit           consumer_enable;
   bit           send_done;
   int unsigned  consume_cycle;

   ddr4_controller #(
      .ADDR_WIDTH     (ADDR_WIDTH),
      .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH   (AXI_ID_WIDTH)
   ) dut (
      .c0_ddr4_act_n            (c0_ddr4_act_n),
      .c0_ddr4_adr              (c0_ddr4_adr),
      .c0_ddr4_ba               (c0_ddr4_ba),
      .c0_ddr4_bg               (c0_ddr4_bg),
      .c0_ddr4_cke              (c0_ddr4_cke),
      .c0_ddr4_odt              (c0_ddr4_odt),
      .c0_ddr4_cs_n             (c0_ddr4_cs_n),
      .c0_ddr4_ck_t             (c0_ddr4_ck_t),
      .c0_ddr4_ck_c             (c0_ddr4_ck_c),
      .c0_ddr4_reset_n          (c0_ddr4_reset_n),
      .c0_ddr4_dm_dbi_n         (c0_ddr4_dm_dbi_n),
      .c0_ddr4_dq               (c0_ddr4_dq),
      .c0_ddr4_dqs_c            (c0_ddr4_dqs_c),
      .c0_ddr4_dqs_t            (c0_ddr4_dqs_t),
      .dbg_clk                  (dbg_clk),
      .ui_clk                   (ui_clk),
      .ui_clk_sync_rst          (ui_clk_sync_rst),
      .init_calib_complete      (init_calib_complete),
      .user_r_valid             (user_r_valid),
      .user_r_data              (user_r_data),
      .user_r_empty             (user_r_empty),
      .ddr_overrun              (ddr_overrun),
      .ddr_warning              (ddr_warning),
      .wr_fifo_overrun          (wr_fifo_overrun),
      .ddr_wr_fifo_empty        (ddr_wr_fifo_empty),
      .ddr_rd_empty             (ddr_rd_empty),
      .make_data_p_edge_ddr_clk (make_data_p_edge_ddr_clk),
      .clk_backbone             (clk_backbone),
      .clk                      (clk),
      .RESET                    (reset),
      .c0_sys_clk_p             (c0_sys_clk_p),
      .c0_sys_clk_n             (c0_sys_clk_n),
      .rst_local_t_ddr_clk      (rst_local_t_ddr_clk),
      .data_from_ddr_en         (data_from_ddr_en),
      .data_from_ddr_dd         (data_from_ddr_dd),
      .user_r_rd_en             (user_r_rd_en),
      .ddr_rd_req               (ddr_rd_req),
      .req_stop                 (req_stop),
      .rp_back_en               (rp_back_en),
      .rp_back_view_addr        (rp_back_view_addr),
      .Fault_inject_en          (Fault_inject_en),
      .make_data_on             (make_data_on),
      .make_data_p_edge         (make_data_p_edge),
      .view_size                (view_size)
   );

   initial clk = 1'b0;
   always #(CLK_PERIOD_PS / 2000.0) clk = ~clk;

   initial c0_sys_clk_p = 1'b0;
   always #(CLK_PERIOD_PS / 2000.0) c0_sys_clk_p = ~c0_sys_clk_p;
   assign c0_sys_clk_n = ~c0_sys_clk_p;

   always @(posedge clk) begin
      if (reset) begin
         consume_cycle <= '0;
      end
      else begin
         consume_cycle <= consume_cycle + 1;
      end
   end

   initial begin
      reset                = 1'b1;
      rst_local_t_ddr_clk  = 1'b0;
      data_from_ddr_en     = 1'b0;
      data_from_ddr_dd     = '0;
      ddr_rd_req           = 1'b0;
      req_stop             = 1'b0;
      rp_back_en           = 1'b0;
      rp_back_view_addr    = '0;
      Fault_inject_en      = 1'b0;
      make_data_on         = 1'b0;
      make_data_p_edge     = 1'b0;
      sent_count           = 0;
      recv_count           = 0;
      mismatch_count       = 0;
      overflow_count       = 0;
      timeout_count        = 0;
      sim_view_count       = DEFAULT_SIM_VIEWS;
      use_hash_scoreboard  = 1'b0;
      expected_hash        = 64'h6a09_e667_f3bc_c909;
      actual_hash          = 64'h6a09_e667_f3bc_c909;
      consumer_enable      = 1'b0;
      send_done            = 1'b0;
      if ($value$plusargs("views=%d", sim_view_count)) begin
         if ((sim_view_count < 1) || (sim_view_count > MOCK_MAX_VIEWS)) begin
            $fatal(1, "Invalid +views=%0d, expected 1..%0d for this mock memory",
                   sim_view_count, MOCK_MAX_VIEWS);
         end
      end
      if ($value$plusargs("scoreboard=%s", scoreboard_mode)) begin
         if (scoreboard_mode == "hash") begin
            use_hash_scoreboard = 1'b1;
         end
         else if (scoreboard_mode == "queue") begin
            use_hash_scoreboard = 1'b0;
         end
         else begin
            $fatal(1, "Invalid +scoreboard=%s, expected queue or hash",
                   scoreboard_mode);
         end
      end
      expected_total_beats = sim_view_count * VIEW_TOTAL_BEATS;
      view_size            = VIEW_TOTAL_BEATS[15:0];

      $display("DDR mock test config: views=%0d/%0d scoreboard=%s slices/view=%0d beats/slice=%0d payload_beats/slice=%0d view_beats=%0d period_cycles=%0d",
               sim_view_count, TOTAL_FRAME_VIEWS,
               use_hash_scoreboard ? "hash" : "queue",
               SLICES_PER_VIEW,
               SLICE_TOTAL_BEATS, SLICE_PAYLOAD_BEATS,
               VIEW_TOTAL_BEATS, VIEW_PERIOD_CYCLES);

      repeat (12) @(posedge clk);
      reset = 1'b0;
      wait (init_calib_complete);
      repeat (8) @(posedge clk);

      pulse_make_data();
      ddr_rd_req = 1'b1;
      repeat (256) @(posedge clk);

      fork
         begin
            repeat (128) @(posedge clk);
            consumer_enable = 1'b1;
         end
      join_none

      send_slice_stream();
      wait_for_completion();

      if (mismatch_count != 0) begin
         $fatal(1, "DDR controller mock test failed with %0d mismatches", mismatch_count);
      end
      if (overflow_count != 0) begin
         $fatal(1, "DDR controller mock test failed with %0d overflow/warning events", overflow_count);
      end
      if (timeout_count != 0) begin
         $fatal(1, "DDR controller mock test timed out after receiving %0d of %0d beats",
                recv_count, sent_count);
      end
      if (use_hash_scoreboard && (actual_hash !== expected_hash)) begin
         $fatal(1, "DDR controller mock hash mismatch: actual=%h expected=%h",
                actual_hash, expected_hash);
      end
      if ((!use_hash_scoreboard) && (expected_q.size() != 0)) begin
         $fatal(1, "DDR controller mock test ended with %0d expected beats still queued",
                expected_q.size());
      end

      $display("DDR controller mock slice test passed: views=%0d sent=%0d received=%0d",
               sim_view_count, sent_count, recv_count);
      $finish;
   end

   always @(posedge clk) begin
      if (!reset && (wr_fifo_overrun || ddr_overrun || ddr_warning)) begin
         overflow_count++;
         $error("DDR status event at %0t: wr_fifo_overrun=%0b ddr_overrun=%0b ddr_warning=%0b",
                $time, wr_fifo_overrun, ddr_overrun, ddr_warning);
      end
   end

   always_ff @(posedge clk) begin
      if (reset) begin
         user_r_rd_en <= 1'b0;
      end
      else begin
         user_r_rd_en <= consumer_enable && user_r_valid;
      end
   end

   always @(posedge clk) begin
      if (!reset && user_r_rd_en && user_r_valid) begin
         if (use_hash_scoreboard) begin
            actual_hash = update_hash(actual_hash, user_r_data, recv_count);
         end
         else if (expected_q.size() == 0) begin
            mismatch_count++;
            $error("Unexpected read beat at %0t: data=%h", $time, user_r_data);
         end
         else begin
            expected_word = expected_q.pop_front();
            if (user_r_data !== expected_word) begin
               mismatch_count++;
               $error("Read mismatch at beat %0d: data=%h expected=%h",
                      recv_count, user_r_data, expected_word);
            end
         end
         recv_count++;
      end
   end

   task automatic pulse_make_data();
      begin
         @(posedge clk);
         make_data_on     <= 1'b1;
         make_data_p_edge <= 1'b1;
         @(posedge clk);
         make_data_p_edge <= 1'b0;
         repeat (3) @(posedge clk);
         make_data_on <= 1'b0;
      end
   endtask

   task automatic send_slice_stream();
      int view_idx;
      int slice_idx;
      int view_start_cycle;
      begin
         for (view_idx = 0; view_idx < sim_view_count; view_idx++) begin
            view_start_cycle = consume_cycle;
            for (slice_idx = 0; slice_idx < SLICES_PER_VIEW; slice_idx++) begin
               send_slice_frame(view_idx, slice_idx);
            end
            idle_write_cycle();
            while ((consume_cycle - view_start_cycle) < VIEW_PERIOD_CYCLES) begin
               @(posedge clk);
            end
         end
         idle_write_cycle();
         send_done = 1'b1;
      end
   endtask

   task automatic send_slice_frame(input int view_idx, input int slice_idx);
      int payload_beat_idx;
      begin
         push_write_beat(make_slice_header0(view_idx, slice_idx));
         push_write_beat(make_slice_header1(view_idx, slice_idx));

         for (payload_beat_idx = 0;
              payload_beat_idx < SLICE_PAYLOAD_BEATS;
              payload_beat_idx++) begin
            push_write_beat(make_payload_word(view_idx, slice_idx, payload_beat_idx));
         end
      end
   endtask

   task automatic push_write_beat(input logic [127:0] word);
      begin
         @(negedge clk);
         data_from_ddr_dd = word;
         data_from_ddr_en = 1'b1;
         if (use_hash_scoreboard) begin
            expected_hash = update_hash(expected_hash, word, sent_count);
         end
         else begin
            expected_q.push_back(word);
         end
         sent_count++;
      end
   endtask

   task automatic idle_write_cycle();
      begin
         @(negedge clk);
         data_from_ddr_en = 1'b0;
         data_from_ddr_dd = '0;
      end
   endtask

   task automatic wait_for_completion();
      begin
         while ((!(send_done && (recv_count == sent_count))) &&
                (recv_count < expected_total_beats) &&
                (timeout_count == 0)) begin
            @(posedge clk);
         end

         repeat (20) @(posedge clk);
      end
   endtask

   initial begin
      repeat (TIMEOUT_CYCLES) @(posedge clk);
      timeout_count = 1;
   end

   function automatic logic [127:0] make_slice_header0(
      input int view_idx,
      input int slice_idx
   );
      make_slice_header0 = {
         32'hdd44_0001,
         16'(view_idx),
         16'(slice_idx),
         16'(SLICES_PER_VIEW),
         16'(SLICE_PAYLOAD_BEATS),
         16'(FTPS_PER_SLICE),
         16'(CHANNELS_PER_SLICE)
      };
   endfunction

   function automatic logic [127:0] make_slice_header1(
      input int view_idx,
      input int slice_idx
   );
      make_slice_header1 = {
         32'hdd44_0002,
         16'(view_idx),
         16'(slice_idx),
         16'(VIEW_PERIOD_US),
         16'(VIEW_PERIOD_CYCLES),
         32'(sent_count),
         16'(SAMPLES_PER_BEAT),
         16'(SAMPLE_BITS)
      };
   endfunction

   function automatic logic [15:0] make_sample16(
      input int view_idx,
      input int slice_idx,
      input int sample_idx
   );
      make_sample16 = 16'((view_idx * 16'h101) ^
                          (slice_idx * 16'h11) ^
                          sample_idx);
   endfunction

   function automatic logic [127:0] make_payload_word(
      input int view_idx,
      input int slice_idx,
      input int payload_beat_idx
   );
      logic [127:0] word;
      int sample_lane;
      int sample_idx;
      begin
         word = '0;
         for (sample_lane = 0; sample_lane < SAMPLES_PER_BEAT; sample_lane++) begin
            sample_idx = payload_beat_idx * SAMPLES_PER_BEAT + sample_lane;
            if (sample_idx < SLICE_PAYLOAD_SAMPLES) begin
               word[sample_lane*SAMPLE_BITS +: SAMPLE_BITS] =
                  make_sample16(view_idx, slice_idx, sample_idx);
            end
         end
         make_payload_word = word;
      end
   endfunction

   function automatic logic [63:0] update_hash(
      input logic [63:0] hash_in,
      input logic [127:0] word,
      input int beat_idx
   );
      logic [63:0] mixed;
      begin
         mixed = word[63:0] ^
                 word[127:64] ^
                 (64'(beat_idx) * 64'h9e37_79b9_7f4a_7c15);
         update_hash = {hash_in[56:0], hash_in[63:57]} ^ mixed;
      end
   endfunction

endmodule

`ifdef TB_DDR4_CONTROLLER_LOCAL_MIG_WRAPPER
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

   input  logic [0:0]            c0_ddr4_s_axi_awid,
   input  logic [23:0]           c0_ddr4_s_axi_awaddr,
   input  logic [7:0]            c0_ddr4_s_axi_awlen,
   input  logic [2:0]            c0_ddr4_s_axi_awsize,
   input  logic [1:0]            c0_ddr4_s_axi_awburst,
   input  logic                  c0_ddr4_s_axi_awlock,
   input  logic [3:0]            c0_ddr4_s_axi_awcache,
   input  logic [2:0]            c0_ddr4_s_axi_awprot,
   input  logic [3:0]            c0_ddr4_s_axi_awqos,
   input  logic                  c0_ddr4_s_axi_awvalid,
   output logic                  c0_ddr4_s_axi_awready,
   input  logic [127:0]          c0_ddr4_s_axi_wdata,
   input  logic [15:0]           c0_ddr4_s_axi_wstrb,
   input  logic                  c0_ddr4_s_axi_wlast,
   input  logic                  c0_ddr4_s_axi_wvalid,
   output logic                  c0_ddr4_s_axi_wready,
   output logic [0:0]            c0_ddr4_s_axi_bid,
   output logic [1:0]            c0_ddr4_s_axi_bresp,
   output logic                  c0_ddr4_s_axi_bvalid,
   input  logic                  c0_ddr4_s_axi_bready,
   input  logic [0:0]            c0_ddr4_s_axi_arid,
   input  logic [23:0]           c0_ddr4_s_axi_araddr,
   input  logic [7:0]            c0_ddr4_s_axi_arlen,
   input  logic [2:0]            c0_ddr4_s_axi_arsize,
   input  logic [1:0]            c0_ddr4_s_axi_arburst,
   input  logic                  c0_ddr4_s_axi_arlock,
   input  logic [3:0]            c0_ddr4_s_axi_arcache,
   input  logic [2:0]            c0_ddr4_s_axi_arprot,
   input  logic [3:0]            c0_ddr4_s_axi_arqos,
   input  logic                  c0_ddr4_s_axi_arvalid,
   output logic                  c0_ddr4_s_axi_arready,
   output logic [0:0]            c0_ddr4_s_axi_rid,
   output logic [127:0]          c0_ddr4_s_axi_rdata,
   output logic [1:0]            c0_ddr4_s_axi_rresp,
   output logic                  c0_ddr4_s_axi_rlast,
   output logic                  c0_ddr4_s_axi_rvalid,
   input  logic                  c0_ddr4_s_axi_rready
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
      .AXI_ADDR_WIDTH      (24),
      .AXI_ID_WIDTH        (1),
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
      .axi_awid            (c0_ddr4_s_axi_awid),
      .axi_awaddr          (c0_ddr4_s_axi_awaddr),
      .axi_awlen           (c0_ddr4_s_axi_awlen),
      .axi_awsize          (c0_ddr4_s_axi_awsize),
      .axi_awburst         (c0_ddr4_s_axi_awburst),
      .axi_awlock          (c0_ddr4_s_axi_awlock),
      .axi_awcache         (c0_ddr4_s_axi_awcache),
      .axi_awprot          (c0_ddr4_s_axi_awprot),
      .axi_awqos           (c0_ddr4_s_axi_awqos),
      .axi_awvalid         (c0_ddr4_s_axi_awvalid),
      .axi_awready         (c0_ddr4_s_axi_awready),
      .axi_wdata           (c0_ddr4_s_axi_wdata),
      .axi_wstrb           (c0_ddr4_s_axi_wstrb),
      .axi_wlast           (c0_ddr4_s_axi_wlast),
      .axi_wvalid          (c0_ddr4_s_axi_wvalid),
      .axi_wready          (c0_ddr4_s_axi_wready),
      .axi_bid             (c0_ddr4_s_axi_bid),
      .axi_bresp           (c0_ddr4_s_axi_bresp),
      .axi_bvalid          (c0_ddr4_s_axi_bvalid),
      .axi_bready          (c0_ddr4_s_axi_bready),
      .axi_arid            (c0_ddr4_s_axi_arid),
      .axi_araddr          (c0_ddr4_s_axi_araddr),
      .axi_arlen           (c0_ddr4_s_axi_arlen),
      .axi_arsize          (c0_ddr4_s_axi_arsize),
      .axi_arburst         (c0_ddr4_s_axi_arburst),
      .axi_arlock          (c0_ddr4_s_axi_arlock),
      .axi_arcache         (c0_ddr4_s_axi_arcache),
      .axi_arprot          (c0_ddr4_s_axi_arprot),
      .axi_arqos           (c0_ddr4_s_axi_arqos),
      .axi_arvalid         (c0_ddr4_s_axi_arvalid),
      .axi_arready         (c0_ddr4_s_axi_arready),
      .axi_rid             (c0_ddr4_s_axi_rid),
      .axi_rdata           (c0_ddr4_s_axi_rdata),
      .axi_rresp           (c0_ddr4_s_axi_rresp),
      .axi_rlast           (c0_ddr4_s_axi_rlast),
      .axi_rvalid          (c0_ddr4_s_axi_rvalid),
      .axi_rready          (c0_ddr4_s_axi_rready)
   );

endmodule
`endif
