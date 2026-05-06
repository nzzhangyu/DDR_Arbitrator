`timescale 1ps/1ps

`ifdef XILINX_SIMULATOR
module short(in1, in1);
   inout in1;
endmodule
`endif

module tb_ddr4_controller_mig_real;

   import arch_package::*;

   localparam int CTRL_ADDR_WIDTH      = 28;
   localparam int AXI_ADDR_WIDTH       = 32;
   localparam int AXI_ID_WIDTH         = 4;
   localparam int DEFAULT_SIM_VIEWS    = 1;
   localparam int TOTAL_FRAME_VIEWS    = 2320;
   localparam int VIEW_PERIOD_US       = 232;
   localparam int CLK_PERIOD_PS        = 5000;
   localparam int MIG_SYS_PERIOD_PS    = 4998;
   localparam int VIEW_PERIOD_CYCLES   = (VIEW_PERIOD_US * 1000000) / CLK_PERIOD_PS;
   localparam int FTPS_PER_SLICE       = 30;
   localparam int CHANNELS_PER_SLICE   = 48;
   localparam int SLICES_PER_VIEW      = 128;
   localparam int SAMPLE_BITS          = 16;
   localparam int AXI_DATA_BITS        = 128;
   localparam int SAMPLES_PER_BEAT     = AXI_DATA_BITS / SAMPLE_BITS;
   localparam int SLICE_HEADER_BEATS   = 2;
   localparam int SLICE_PAYLOAD_SAMPLES = FTPS_PER_SLICE * CHANNELS_PER_SLICE;
   localparam int SLICE_PAYLOAD_BEATS =
      (SLICE_PAYLOAD_SAMPLES + SAMPLES_PER_BEAT - 1) / SAMPLES_PER_BEAT;
   localparam int SLICE_TOTAL_BEATS    = SLICE_HEADER_BEATS + SLICE_PAYLOAD_BEATS;
   localparam int VIEW_TOTAL_BEATS     = SLICES_PER_VIEW * SLICE_TOTAL_BEATS;
   localparam int TIMEOUT_CYCLES       = 5000000;

   localparam int SDRAM_ADDR_WIDTH     = 17;
   localparam int DQ_WIDTH             = 16;
   localparam int DQS_WIDTH            = 2;
   localparam int DRAM_WIDTH           = 8;
   localparam int NUM_PHYSICAL_PARTS   = DQ_WIDTH / DRAM_WIDTH;
   localparam int RANK_WIDTH           = 1;
   localparam int CS_WIDTH             = 1;
   localparam string CA_MIRROR         = "OFF";
   localparam logic [2:0] WR_CMD       = 3'b100;
   localparam logic [2:0] RD_CMD       = 3'b101;

   parameter UTYPE_density CONFIGURED_DENSITY = _16G;

   logic                       clk;
   logic                       reset;
   logic                       c0_sys_clk_p;
   logic                       c0_sys_clk_n;
   logic                       rst_local_t_ddr_clk;
   logic                       data_from_ddr_en;
   logic [127:0]               data_from_ddr_dd;
   logic                       user_r_rd_en;
   logic                       ddr_rd_req;
   logic                       req_stop;
   logic                       rp_back_en;
   logic [CTRL_ADDR_WIDTH-1:0] rp_back_view_addr;
   logic                       Fault_inject_en;
   logic                       make_data_on;
   logic                       make_data_p_edge;
   logic [15:0]                view_size;

   logic                       c0_ddr4_act_n;
   logic [16:0]                c0_ddr4_adr;
   logic [1:0]                 c0_ddr4_ba;
   logic [1:0]                 c0_ddr4_bg;
   logic [0:0]                 c0_ddr4_cke;
   logic [0:0]                 c0_ddr4_odt;
   logic [0:0]                 c0_ddr4_cs_n;
   logic [0:0]                 c0_ddr4_ck_t;
   logic [0:0]                 c0_ddr4_ck_c;
   logic                       c0_ddr4_reset_n;
   wire  [1:0]                 c0_ddr4_dm_dbi_n;
   wire  [15:0]                c0_ddr4_dq;
   wire  [1:0]                 c0_ddr4_dqs_c;
   wire  [1:0]                 c0_ddr4_dqs_t;
   logic                       dbg_clk;
   logic                       ui_clk;
   logic                       ui_clk_sync_rst;
   logic                       init_calib_complete;
   logic                       user_r_valid;
   logic [127:0]               user_r_data;
   logic                       user_r_empty;
   logic                       ddr_overrun;
   logic                       ddr_warning;
   logic                       wr_fifo_overrun;
   logic                       ddr_wr_fifo_empty;
   logic                       ddr_rd_empty;
   logic                       make_data_p_edge_ddr_clk;
   logic                       clk_backbone;

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

   reg  [SDRAM_ADDR_WIDTH-1:0] c0_ddr4_adr_sdram[1:0];
   reg  [1:0]                  c0_ddr4_ba_sdram[1:0];
   reg  [1:0]                  c0_ddr4_bg_sdram[1:0];
   reg  [SDRAM_ADDR_WIDTH-1:0] DDR4_ADRMOD[RANK_WIDTH-1:0];
   bit                         en_model;
   tri                         model_enable = en_model;
   wire                        c0_ddr4_ck_t_mem;
   wire                        c0_ddr4_ck_c_mem;

   assign c0_ddr4_ck_t_mem = c0_ddr4_ck_t[0];
   assign c0_ddr4_ck_c_mem = c0_ddr4_ck_c[0];

   ddr4_controller #(
      .ADDR_WIDTH     (CTRL_ADDR_WIDTH),
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
   always #(CLK_PERIOD_PS / 2.0) clk = ~clk;

   initial c0_sys_clk_p = 1'b0;
   always #(MIG_SYS_PERIOD_PS / 2.0) c0_sys_clk_p = ~c0_sys_clk_p;
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
      en_model             = 1'b0;
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

      #5000 en_model = 1'b1;

      if ($value$plusargs("views=%d", sim_view_count)) begin
         if ((sim_view_count < 1) || (sim_view_count > TOTAL_FRAME_VIEWS)) begin
            $fatal(1, "Invalid +views=%0d, expected 1..%0d",
                   sim_view_count, TOTAL_FRAME_VIEWS);
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

      $display("DDR real MIG test config: views=%0d/%0d scoreboard=%s slices/view=%0d beats/slice=%0d view_beats=%0d",
               sim_view_count, TOTAL_FRAME_VIEWS,
               use_hash_scoreboard ? "hash" : "queue",
               SLICES_PER_VIEW, SLICE_TOTAL_BEATS, VIEW_TOTAL_BEATS);

      repeat (12) @(posedge clk);
      reset = 1'b0;
      wait (init_calib_complete);
      repeat (32) @(posedge clk);

      pulse_make_data();
      ddr_rd_req = 1'b1;
      repeat (512) @(posedge clk);

      fork
         begin
            repeat (128) @(posedge clk);
            consumer_enable = 1'b1;
         end
      join_none

      send_slice_stream();
      wait_for_completion();

      if (mismatch_count != 0) begin
         $fatal(1, "DDR real MIG test failed with %0d mismatches", mismatch_count);
      end
      if (overflow_count != 0) begin
         $fatal(1, "DDR real MIG test failed with %0d overflow/warning events", overflow_count);
      end
      if (timeout_count != 0) begin
         $fatal(1, "DDR real MIG test timed out after receiving %0d of %0d beats",
                recv_count, sent_count);
      end
      if (use_hash_scoreboard && (actual_hash !== expected_hash)) begin
         $fatal(1, "DDR real MIG hash mismatch: actual=%h expected=%h",
                actual_hash, expected_hash);
      end
      if ((!use_hash_scoreboard) && (expected_q.size() != 0)) begin
         $fatal(1, "DDR real MIG test ended with %0d expected beats still queued",
                expected_q.size());
      end

      $display("DDR real MIG slice test passed: views=%0d sent=%0d received=%0d",
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

   always_comb begin
      c0_ddr4_adr_sdram[0] = c0_ddr4_adr;
      c0_ddr4_adr_sdram[1] = (CA_MIRROR == "ON") ?
                              {c0_ddr4_adr[SDRAM_ADDR_WIDTH-1:14],
                               c0_ddr4_adr[11], c0_ddr4_adr[12],
                               c0_ddr4_adr[13], c0_ddr4_adr[10:9],
                               c0_ddr4_adr[7], c0_ddr4_adr[8],
                               c0_ddr4_adr[5], c0_ddr4_adr[6],
                               c0_ddr4_adr[3], c0_ddr4_adr[4],
                               c0_ddr4_adr[2:0]} :
                              c0_ddr4_adr;
      c0_ddr4_ba_sdram[0]  = c0_ddr4_ba;
      c0_ddr4_ba_sdram[1]  = (CA_MIRROR == "ON") ?
                              {c0_ddr4_ba[0], c0_ddr4_ba[1]} :
                              c0_ddr4_ba;
      c0_ddr4_bg_sdram[0]  = c0_ddr4_bg;
      c0_ddr4_bg_sdram[1]  = (CA_MIRROR == "ON" && DRAM_WIDTH != 16) ?
                              {c0_ddr4_bg[0], c0_ddr4_bg[1]} :
                              c0_ddr4_bg;
   end

   genvar rnk;
   generate
      for (rnk = 0; rnk < CS_WIDTH; rnk++) begin : rankup
         always_comb begin
            if (c0_ddr4_act_n) begin
               unique casez (c0_ddr4_adr_sdram[0][16:14])
                  WR_CMD,
                  RD_CMD: begin
                     DDR4_ADRMOD[rnk] =
                        c0_ddr4_adr_sdram[rnk] & 17'h1c7ff;
                  end
                  default: begin
                     DDR4_ADRMOD[rnk] = c0_ddr4_adr_sdram[rnk];
                  end
               endcase
            end
            else begin
               DDR4_ADRMOD[rnk] = c0_ddr4_adr_sdram[rnk];
            end
         end
      end
   endgenerate

   genvar i;
   genvar r;
   genvar s;

   generate
      DDR4_if #(.CONFIGURED_DQ_BITS(8))
         iDDR4[0:(RANK_WIDTH*NUM_PHYSICAL_PARTS)-1]();

      for (r = 0; r < RANK_WIDTH; r++) begin : memModels_Ri1
         for (i = 0; i < NUM_PHYSICAL_PARTS; i++) begin : memModel1
            ddr4_model #(
               .CONFIGURED_DQ_BITS (8),
               .CONFIGURED_DENSITY (CONFIGURED_DENSITY)
            ) ddr4_model_u (
               .model_enable (model_enable),
               .iDDR4        (iDDR4[(r*NUM_PHYSICAL_PARTS)+i])
            );
         end
      end

      for (r = 0; r < RANK_WIDTH; r++) begin : tranDQ2
         for (i = 0; i < NUM_PHYSICAL_PARTS; i++) begin : tranDQ12
            for (s = 0; s < 8; s++) begin : tranDQ2
`ifdef XILINX_SIMULATOR
               short bidiDQ(iDDR4[(r*NUM_PHYSICAL_PARTS)+i].DQ[s],
                             c0_ddr4_dq[s+i*8]);
`else
               tran bidiDQ(iDDR4[(r*NUM_PHYSICAL_PARTS)+i].DQ[s],
                            c0_ddr4_dq[s+i*8]);
`endif
            end
         end
      end

      for (r = 0; r < RANK_WIDTH; r++) begin : tranDQS2
         for (i = 0; i < NUM_PHYSICAL_PARTS; i++) begin : tranDQS12
`ifdef XILINX_SIMULATOR
            short bidiDQS(iDDR4[(r*NUM_PHYSICAL_PARTS)+i].DQS_t,
                           c0_ddr4_dqs_t[i]);
            short bidiDQS_(iDDR4[(r*NUM_PHYSICAL_PARTS)+i].DQS_c,
                            c0_ddr4_dqs_c[i]);
            short bidiDM(iDDR4[(r*NUM_PHYSICAL_PARTS)+i].DM_n,
                          c0_ddr4_dm_dbi_n[i]);
`else
            tran bidiDQS(iDDR4[(r*NUM_PHYSICAL_PARTS)+i].DQS_t,
                         c0_ddr4_dqs_t[i]);
            tran bidiDQS_(iDDR4[(r*NUM_PHYSICAL_PARTS)+i].DQS_c,
                           c0_ddr4_dqs_c[i]);
            tran bidiDM(iDDR4[(r*NUM_PHYSICAL_PARTS)+i].DM_n,
                        c0_ddr4_dm_dbi_n[i]);
`endif
         end
      end

      for (r = 0; r < RANK_WIDTH; r++) begin : ADDR_RANKS
         for (i = 0; i < NUM_PHYSICAL_PARTS; i++) begin : ADDR_R
            assign iDDR4[(r*NUM_PHYSICAL_PARTS)+i].BG      =
               c0_ddr4_bg_sdram[r];
            assign iDDR4[(r*NUM_PHYSICAL_PARTS)+i].BA      =
               c0_ddr4_ba_sdram[r];
            assign iDDR4[(r*NUM_PHYSICAL_PARTS)+i].ADDR_17 =
               (SDRAM_ADDR_WIDTH == 18) ?
               DDR4_ADRMOD[r][SDRAM_ADDR_WIDTH-1] : 1'b0;
            assign iDDR4[(r*NUM_PHYSICAL_PARTS)+i].ADDR    =
               DDR4_ADRMOD[r][13:0];
            assign iDDR4[(r*NUM_PHYSICAL_PARTS)+i].CS_n    =
               c0_ddr4_cs_n[r];
         end
      end

      for (r = 0; r < RANK_WIDTH; r++) begin : tranADCTL_RANKS1
         for (i = 0; i < NUM_PHYSICAL_PARTS; i++) begin : tranADCTL1
            assign iDDR4[(r*NUM_PHYSICAL_PARTS)+i].CK        =
               {c0_ddr4_ck_t_mem, c0_ddr4_ck_c_mem};
            assign iDDR4[(r*NUM_PHYSICAL_PARTS)+i].ACT_n     =
               c0_ddr4_act_n;
            assign iDDR4[(r*NUM_PHYSICAL_PARTS)+i].RAS_n_A16 =
               DDR4_ADRMOD[r][16];
            assign iDDR4[(r*NUM_PHYSICAL_PARTS)+i].CAS_n_A15 =
               DDR4_ADRMOD[r][15];
            assign iDDR4[(r*NUM_PHYSICAL_PARTS)+i].WE_n_A14  =
               DDR4_ADRMOD[r][14];
            assign iDDR4[(r*NUM_PHYSICAL_PARTS)+i].CKE       =
               c0_ddr4_cke[r];
            assign iDDR4[(r*NUM_PHYSICAL_PARTS)+i].ODT       =
               c0_ddr4_odt[r];
            assign iDDR4[(r*NUM_PHYSICAL_PARTS)+i].PARITY    = 1'b0;
            assign iDDR4[(r*NUM_PHYSICAL_PARTS)+i].TEN       = 1'b0;
            assign iDDR4[(r*NUM_PHYSICAL_PARTS)+i].ZQ        = 1'b1;
            assign iDDR4[(r*NUM_PHYSICAL_PARTS)+i].PWR       = 1'b1;
            assign iDDR4[(r*NUM_PHYSICAL_PARTS)+i].VREF_CA   = 1'b1;
            assign iDDR4[(r*NUM_PHYSICAL_PARTS)+i].VREF_DQ   = 1'b1;
            assign iDDR4[(r*NUM_PHYSICAL_PARTS)+i].RESET_n   =
               c0_ddr4_reset_n;
         end
      end
   endgenerate

endmodule
