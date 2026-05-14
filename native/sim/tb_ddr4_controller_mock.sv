`timescale 1ns/1ps

module tb_ddr4_controller_mock;

   localparam int CLK_PERIOD_PS      = 5000;   
   // System Paramete
   localparam int CONV_PERIOD_US     = 232;
   localparam int DEFAULT_SIM_VIEWS  = 2;
   localparam int TOTAL_VIEWS        = 2320;
   localparam int FTP_NUM            = 30;
   localparam int CH_NUM             = 48;
   localparam int SLICE_NUM          = 128;
   localparam int SAMPLE_BITS        = 16;
   localparam int VIEW_PERIOD_CYCLES = (CONV_PERIOD_US * 1000000) / CLK_PERIOD_PS;

   // Mig Parameters
   localparam int ADDR_WIDTH     = 20;
   localparam int APP_ADDR_WIDTH = ADDR_WIDTH + 4;
   localparam int APP_DATA_BITS  = 128;
   
   // Frame Parameters
   localparam int SLICE_HEADER_BEATS    = 2;
   localparam int SAMPLES_PER_BEAT      = APP_DATA_BITS / SAMPLE_BITS;
   localparam int SLICE_PAYLOAD_SAMPLES = FTP_NUM * CH_NUM;
   localparam int SLICE_PAYLOAD_BEATS   = (SLICE_PAYLOAD_SAMPLES + SAMPLES_PER_BEAT - 1) / SAMPLES_PER_BEAT;
   localparam int SLICE_TOTAL_BEATS     = SLICE_HEADER_BEATS + SLICE_PAYLOAD_BEATS;
   localparam int VIEW_TOTAL_BEATS      = SLICE_NUM * SLICE_TOTAL_BEATS;
   localparam int MOCK_MEM_WORDS        = 1 << ADDR_WIDTH;
   localparam int MOCK_MAX_VIEWS        = MOCK_MEM_WORDS / VIEW_TOTAL_BEATS;
   localparam int TIMEOUT_CYCLES        = 1200000;
   localparam logic [2:0] APP_CMD_WRITE = 3'b000;
   localparam logic [2:0] APP_CMD_READ  = 3'b001;

   logic                  clk;
   logic                  reset;
   logic                  fast_mock_clk;
   logic                  rst_local_t_ddr_clk;
   logic                  data_from_ddr_en;
   logic [127:0]          data_from_ddr_dd;
   logic                  user_r_rd_en;
   logic                  ddr_rd_req;
   logic                  ddr_rd_req_base;
   logic                  req_stop;
   logic                  rp_back_en;
   logic [ADDR_WIDTH-1:0] rp_back_view_addr;
   logic                  Fault_inject_en;
   logic                  make_data_on;
   logic                  make_data_p_edge;
   logic [15:0]           view_size;

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

   logic [APP_ADDR_WIDTH-1:0] app_addr;
   logic [2:0]                app_cmd;
   logic                      app_en;
   logic                      app_rdy;
   logic [127:0]              app_wdf_data;
   logic [15:0]               app_wdf_mask;
   logic                      app_wdf_wren;
   logic                      app_wdf_end;
   logic                      app_wdf_rdy;
   logic [127:0]              app_rd_data;
   logic                      app_rd_data_valid;
   logic                      app_rd_data_end;

   logic [127:0]          expected_q[$];
   logic [127:0]          expected_word;
   int                    sent_count;
   int                    recv_count;
   int                    mismatch_count;
   int                    overflow_count;
   int                    timeout_count;
   int                    native_read_cmd_count;
   int                    native_write_cmd_count;
   int                    read_budget_error_count;
   int                    urgent_interrupt_error_count;
   int                    urgent_read_data_event_count;
   int                    sim_view_count;
   int                    expected_total_beats;
   int                    write_gap_interval;
   int                    write_gap_block;
   int                    consumer_stall_interval;
   int                    consumer_stall_block;
   int                    rd_req_stall_interval;
   int                    rd_req_stall_block;
   int                    max_wr_fifo_level_limit;
   int                    min_rd_fifo_level_limit;
   int                    max_user_underflow_cycles_limit;
   int                    max_app_rdy_stall_limit;
   int                    max_app_wdf_stall_limit;
   int                    max_read_data_gap_limit;
   int                    underflow_count;
   int                    write_gap_cycle_count;
   int                    consumer_stall_cycle_count;
   int                    rd_req_stall_cycle_count;
   int                    monitor_error_count;
   int                    log_fd;
   bit                    use_hash_scoreboard;
   bit                    stress_enable;
   bit                    worst_check_enable;
   logic [63:0]           expected_hash;
   logic [63:0]           actual_hash;
   string                 scoreboard_mode;
   string                 log_path;
   bit                    consumer_enable;
   bit                    send_done;
   int unsigned           consume_cycle;
   int unsigned           write_beat_cycle;
   int unsigned           consumer_active_cycle;
   int unsigned           rd_req_active_cycle;
   logic                  native_read_cmd_fire;
   logic                  native_write_cmd_fire;
   logic                  in_read_data_state;
   logic                  urgent_read_data_event_fire;
   logic                  consumer_stall_active;
   logic                  rd_req_stall_active;
   logic                  expected_data_remaining;

   user_app_top #(
      .ADDR_WIDTH     (ADDR_WIDTH),
      .APP_ADDR_WIDTH (APP_ADDR_WIDTH)
   ) dut (
      .app_addr                 (app_addr),
      .app_cmd                  (app_cmd),
      .app_en                   (app_en),
      .app_rdy                  (app_rdy),
      .app_wdf_data             (app_wdf_data),
      .app_wdf_mask             (app_wdf_mask),
      .app_wdf_wren             (app_wdf_wren),
      .app_wdf_end              (app_wdf_end),
      .app_wdf_rdy              (app_wdf_rdy),
      .app_rd_data              (app_rd_data),
      .app_rd_data_valid        (app_rd_data_valid),
      .app_rd_data_end          (app_rd_data_end),
      .user_r_valid             (user_r_valid),
      .user_r_data              (user_r_data),
      .user_r_empty             (user_r_empty),
      .ddr_overrun              (ddr_overrun),
      .ddr_warning              (ddr_warning),
      .wr_fifo_overrun          (wr_fifo_overrun),
      .ddr_wr_fifo_empty        (ddr_wr_fifo_empty),
      .ddr_rd_empty             (ddr_rd_empty),
      .make_data_p_edge_ddr_clk (make_data_p_edge_ddr_clk),
      .ui_clk                   (ui_clk),
      .ui_clk_sync_rst          (ui_clk_sync_rst),
      .init_calib_complete      (init_calib_complete),
      .clk                      (clk),
      .RESET                    (reset),
      .data_from_ddr_en         (data_from_ddr_en),
      .data_from_ddr_dd         (data_from_ddr_dd),
      .user_r_rd_en             (user_r_rd_en),
      .ddr_rd_req               (ddr_rd_req),
      .req_stop                 (req_stop),
      .rst_local_t_ddr_clk      (rst_local_t_ddr_clk),
      .fault_ddr_overrun        (Fault_inject_en),
      .fault_ddr_warning        (Fault_inject_en),
      .make_data_on             (make_data_on),
      .make_data_p_edge         (make_data_p_edge),
      .view_size                (view_size),
      .rp_back_en               (rp_back_en),
      .rp_back_view_addr        (rp_back_view_addr)
   );

   ddr4_fast_mock #(
      .APP_ADDR_WIDTH      (APP_ADDR_WIDTH),
      .MEM_WORDS           (MOCK_MEM_WORDS),
      .CALIB_DELAY_CYCLES  (16),
      .READ_LATENCY_CYCLES (3)
   ) mock_u (
      .clk_in              (fast_mock_clk),
      .RESET               (reset),
      .ui_clk              (ui_clk),
      .ui_clk_sync_rst     (ui_clk_sync_rst),
      .init_calib_complete (init_calib_complete),
      .dbg_clk             (dbg_clk),
      .app_addr            (app_addr),
      .app_cmd             (app_cmd),
      .app_en              (app_en),
      .app_rdy             (app_rdy),
      .app_wdf_data        (app_wdf_data),
      .app_wdf_mask        (app_wdf_mask),
      .app_wdf_wren        (app_wdf_wren),
      .app_wdf_end         (app_wdf_end),
      .app_wdf_rdy         (app_wdf_rdy),
      .app_rd_data         (app_rd_data),
      .app_rd_data_valid   (app_rd_data_valid),
      .app_rd_data_end     (app_rd_data_end)
   );

   assign native_read_cmd_fire  = app_en && app_rdy && (app_cmd == APP_CMD_READ);
   assign native_write_cmd_fire = app_en && app_rdy && (app_cmd == APP_CMD_WRITE);
   assign in_read_data_state =
      (dut.user_rw_cmd_gen_uut.rw_state == dut.user_rw_cmd_gen_uut.RW_READ_DATA);
   assign urgent_read_data_event_fire =
      in_read_data_state && dut.user_rw_cmd_gen_uut.wr_level_urgent;
   assign ddr_rd_req = ddr_rd_req_base && (!rd_req_stall_active);
   assign consumer_stall_active =
      consumer_enable &&
      (consumer_stall_interval > 0) &&
      ((consumer_active_cycle % consumer_stall_interval) < consumer_stall_block);
   assign rd_req_stall_active =
      (rd_req_stall_interval > 0) &&
      ((rd_req_active_cycle % rd_req_stall_interval) < rd_req_stall_block);
   assign expected_data_remaining = (recv_count < sent_count);

   initial clk = 1'b0;
   always #(CLK_PERIOD_PS / 2000.0) clk = ~clk;

   initial fast_mock_clk = 1'b0;
   always #(CLK_PERIOD_PS / 2000.0) fast_mock_clk = ~fast_mock_clk;

   ddr4_controller_tb_monitor monitor_u (
      .ui_clk                         (ui_clk),
      .ui_clk_sync_rst                (ui_clk_sync_rst),
      .clk                            (clk),
      .reset                          (reset),
      .log_fd                         (log_fd),
      .worst_check_enable             (worst_check_enable),
      .max_wr_fifo_level_limit        (max_wr_fifo_level_limit),
      .min_rd_fifo_level_limit        (min_rd_fifo_level_limit),
      .max_user_underflow_cycles_limit(max_user_underflow_cycles_limit),
      .max_app_rdy_stall_limit        (max_app_rdy_stall_limit),
      .max_app_wdf_stall_limit        (max_app_wdf_stall_limit),
      .max_read_data_gap_limit        (max_read_data_gap_limit),
      .init_calib_complete            (init_calib_complete),
      .app_rdy                        (app_rdy),
      .app_wdf_rdy                    (app_wdf_rdy),
      .app_rd_data_valid              (app_rd_data_valid),
      .user_r_valid                   (user_r_valid),
      .user_r_empty                   (user_r_empty),
      .consumer_enable                (consumer_enable),
      .consumer_stall_active          (consumer_stall_active),
      .expected_data_remaining        (expected_data_remaining),
      .native_read_cmd_fire           (native_read_cmd_fire),
      .native_write_cmd_fire          (native_write_cmd_fire),
      .in_read_data_state             (in_read_data_state),
      .urgent_read_data_event_fire    (urgent_read_data_event_fire),
      .wr_fifo_level                  (dut.ddr_wr_fifo_level),
      .wr_fifo_full                   (dut.ddr_wr_fifo_full),
      .rd_fifo_level                  (dut.ddr_rd_fifo_level),
      .rd_fifo_full                   (dut.ddr_rd_fifo_full),
      .rw_state                       (dut.user_rw_cmd_gen_uut.rw_state),
      .read_burst_len                 (dut.user_rw_cmd_gen_uut.read_burst_len),
      .read_beat_cnt                  (dut.user_rw_cmd_gen_uut.read_beat_cnt),
      .wr_level_high                  (dut.user_rw_cmd_gen_uut.wr_level_high),
      .wr_level_urgent                (dut.user_rw_cmd_gen_uut.wr_level_urgent),
      .read_data_fire                 (dut.user_rw_cmd_gen_uut.read_data_fire),
      .sent_count                     (sent_count),
      .recv_count                     (recv_count),
      .mismatch_count                 (mismatch_count),
      .overflow_count                 (overflow_count),
      .write_gap_cycle_count          (write_gap_cycle_count),
      .consumer_stall_cycle_count     (consumer_stall_cycle_count),
      .rd_req_stall_cycle_count       (rd_req_stall_cycle_count),
      .native_read_cmd_count          (native_read_cmd_count),
      .native_write_cmd_count         (native_write_cmd_count),
      .read_budget_error_count        (read_budget_error_count),
      .urgent_interrupt_error_count   (urgent_interrupt_error_count),
      .urgent_read_data_event_count   (urgent_read_data_event_count),
      .underflow_count                (underflow_count),
      .monitor_error_count            (monitor_error_count)
   );

   always @(posedge clk) begin
      if (reset) begin
         consume_cycle <= '0;
         consumer_active_cycle <= '0;
         rd_req_active_cycle <= '0;
         consumer_stall_cycle_count <= 0;
         rd_req_stall_cycle_count <= 0;
      end
      else begin
         consume_cycle <= consume_cycle + 1;
         if (consumer_enable) begin
            consumer_active_cycle <= consumer_active_cycle + 1;
         end
         if (ddr_rd_req_base) begin
            rd_req_active_cycle <= rd_req_active_cycle + 1;
         end
         if (consumer_stall_active) begin
            consumer_stall_cycle_count <= consumer_stall_cycle_count + 1;
         end
         if (rd_req_stall_active) begin
            rd_req_stall_cycle_count <= rd_req_stall_cycle_count + 1;
         end

      end
   end

   initial begin
      reset                = 1'b1;
      rst_local_t_ddr_clk  = 1'b0;
      data_from_ddr_en     = 1'b0;
      data_from_ddr_dd     = '0;
      ddr_rd_req_base      = 1'b0;
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
      write_gap_interval   = 0;
      write_gap_block      = 0;
      consumer_stall_interval = 0;
      consumer_stall_block = 0;
      rd_req_stall_interval = 0;
      rd_req_stall_block   = 0;
      max_wr_fifo_level_limit = 16383;
      min_rd_fifo_level_limit = 1;
      max_user_underflow_cycles_limit = 0;
      max_app_rdy_stall_limit = -1;
      max_app_wdf_stall_limit = -1;
      max_read_data_gap_limit = -1;
      write_gap_cycle_count = 0;
      consumer_stall_cycle_count = 0;
      rd_req_stall_cycle_count = 0;
      log_fd               = 0;
      use_hash_scoreboard  = 1'b0;
      stress_enable        = 1'b0;
      worst_check_enable   = 1'b0;
      expected_hash        = 64'h6a09_e667_f3bc_c909;
      actual_hash          = 64'h6a09_e667_f3bc_c909;
      log_path             = "tb_ddr4_controller_mock.log";
      consumer_enable      = 1'b0;
      send_done            = 1'b0;
      write_beat_cycle     = '0;
      consumer_active_cycle = '0;
      rd_req_active_cycle  = '0;

      if ($value$plusargs("log=%s", log_path)) begin
      end
      log_fd = $fopen(log_path, "w");
      if (log_fd == 0) begin
         $fatal(1, "Failed to open DDR controller mock log file: %s", log_path);
      end
      $display("DDR controller mock log: %s", log_path);
      $fdisplay(log_fd, "DDR controller mock log: %s", log_path);

      if ($value$plusargs("views=%d", sim_view_count)) begin
         if ((sim_view_count < 1) || (sim_view_count > MOCK_MAX_VIEWS)) begin
            $fdisplay(log_fd, "FATAL: Invalid +views=%0d, expected 1..%0d for this mock memory",
                      sim_view_count, MOCK_MAX_VIEWS);
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
            $fdisplay(log_fd, "FATAL: Invalid +scoreboard=%s, expected queue or hash",
                      scoreboard_mode);
            $fatal(1, "Invalid +scoreboard=%s, expected queue or hash",
                   scoreboard_mode);
         end
      end

      if ($value$plusargs("stress=%d", stress_enable)) begin
      end
      if (stress_enable) begin
         write_gap_interval = 193;
         write_gap_block = 9;
         consumer_stall_interval = 257;
         consumer_stall_block = 33;
         rd_req_stall_interval = 509;
         rd_req_stall_block = 41;
         worst_check_enable = 1'b1;
      end

      // Stress plusargs are deliberately orthogonal. +stress=1 selects a useful
      // default profile, while each field can still be overridden for focused
      // sweeps of the write input gap, user-consumer pause, or read-request pause.
      if ($value$plusargs("write_gap_interval=%d", write_gap_interval)) begin
      end
      if ($value$plusargs("write_gap_block=%d", write_gap_block)) begin
      end
      if ($value$plusargs("consumer_stall_interval=%d", consumer_stall_interval)) begin
      end
      if ($value$plusargs("consumer_stall_block=%d", consumer_stall_block)) begin
      end
      if ($value$plusargs("rd_req_stall_interval=%d", rd_req_stall_interval)) begin
      end
      if ($value$plusargs("rd_req_stall_block=%d", rd_req_stall_block)) begin
      end

      // Worst-case checks turn the measured windows below into assertions.
      // Leaving a max_*_stall plusarg unset records the window but does not fail
      // on that window; FIFO level and user-underflow limits have safe defaults.
      if ($value$plusargs("worst_check=%d", worst_check_enable)) begin
      end
      if ($value$plusargs("max_wr_fifo_level=%d", max_wr_fifo_level_limit)) begin
      end
      if ($value$plusargs("min_rd_fifo_level=%d", min_rd_fifo_level_limit)) begin
      end
      if ($value$plusargs("max_user_underflow_cycles=%d", max_user_underflow_cycles_limit)) begin
      end
      if ($value$plusargs("max_app_rdy_stall=%d", max_app_rdy_stall_limit)) begin
      end
      if ($value$plusargs("max_app_wdf_stall=%d", max_app_wdf_stall_limit)) begin
      end
      if ($value$plusargs("max_read_data_gap=%d", max_read_data_gap_limit)) begin
      end

      if ((write_gap_interval < 0) || (write_gap_block < 0) ||
          (consumer_stall_interval < 0) || (consumer_stall_block < 0) ||
          (rd_req_stall_interval < 0) || (rd_req_stall_block < 0)) begin
         $fdisplay(log_fd, "FATAL: Stress intervals/blocks must be non-negative");
         $fatal(1, "Stress intervals/blocks must be non-negative");
      end

      if (((write_gap_interval == 0) && (write_gap_block != 0)) ||
          ((consumer_stall_interval == 0) && (consumer_stall_block != 0)) ||
          ((rd_req_stall_interval == 0) && (rd_req_stall_block != 0))) begin
         $fdisplay(log_fd, "FATAL: Stress block requires a non-zero matching interval");
         $fatal(1, "Stress block requires a non-zero matching interval");
      end

      if (((write_gap_interval > 0) && (write_gap_block >= write_gap_interval)) ||
          ((consumer_stall_interval > 0) && (consumer_stall_block >= consumer_stall_interval)) ||
          ((rd_req_stall_interval > 0) && (rd_req_stall_block >= rd_req_stall_interval))) begin
         $fdisplay(log_fd, "FATAL: Stress block must be smaller than its interval");
         $fatal(1, "Stress block must be smaller than its interval");
      end

      if ((max_wr_fifo_level_limit < 0) || (max_wr_fifo_level_limit > 16383) ||
          (min_rd_fifo_level_limit < 0) || (min_rd_fifo_level_limit > 16383) ||
          (max_user_underflow_cycles_limit < 0) ||
          (max_app_rdy_stall_limit < -1) ||
          (max_app_wdf_stall_limit < -1) ||
          (max_read_data_gap_limit < -1)) begin
         $fdisplay(log_fd, "FATAL: Invalid worst-case threshold");
         $fatal(1, "Invalid worst-case threshold");
      end
      
      expected_total_beats = sim_view_count * VIEW_TOTAL_BEATS;
      view_size            = VIEW_TOTAL_BEATS[15:0];

      $display("DDR mock test config: views=%0d/%0d scoreboard=%s stress=%0d worst_check=%0d slices/view=%0d beats/slice=%0d payload_beats/slice=%0d view_beats=%0d period_cycles=%0d write_gap=%0d/%0d consumer_stall=%0d/%0d rd_req_stall=%0d/%0d",
               sim_view_count, TOTAL_VIEWS,
               use_hash_scoreboard ? "hash" : "queue",
               stress_enable, worst_check_enable,
               SLICE_NUM,
               SLICE_TOTAL_BEATS, SLICE_PAYLOAD_BEATS,
               VIEW_TOTAL_BEATS, VIEW_PERIOD_CYCLES,
               write_gap_interval, write_gap_block,
               consumer_stall_interval, consumer_stall_block,
               rd_req_stall_interval, rd_req_stall_block);
      $fdisplay(log_fd, "CONFIG: views=%0d/%0d scoreboard=%s stress=%0d worst_check=%0d slices/view=%0d beats/slice=%0d payload_beats/slice=%0d view_beats=%0d period_cycles=%0d write_gap=%0d/%0d consumer_stall=%0d/%0d rd_req_stall=%0d/%0d max_wr_fifo=%0d min_rd_fifo=%0d max_user_underflow=%0d max_app_rdy_stall=%0d max_app_wdf_stall=%0d max_read_data_gap=%0d",
                sim_view_count, TOTAL_VIEWS,
                use_hash_scoreboard ? "hash" : "queue",
                stress_enable, worst_check_enable,
                SLICE_NUM,
                SLICE_TOTAL_BEATS, SLICE_PAYLOAD_BEATS,
                VIEW_TOTAL_BEATS, VIEW_PERIOD_CYCLES,
                write_gap_interval, write_gap_block,
                consumer_stall_interval, consumer_stall_block,
                rd_req_stall_interval, rd_req_stall_block,
                max_wr_fifo_level_limit, min_rd_fifo_level_limit,
                max_user_underflow_cycles_limit,
                max_app_rdy_stall_limit, max_app_wdf_stall_limit,
                max_read_data_gap_limit);

      repeat (12) @(posedge clk);
      reset = 1'b0;
      wait (init_calib_complete);
      repeat (8) @(posedge clk);

      pulse_make_data();
      ddr_rd_req_base = 1'b1;
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
         monitor_u.write_summary("FAIL_MISMATCH");
         $fdisplay(log_fd, "FATAL: DDR controller mock test failed with %0d mismatches",
                   mismatch_count);
         $fatal(1, "DDR controller mock test failed with %0d mismatches", mismatch_count);
      end

      if (overflow_count != 0) begin
         monitor_u.write_summary("FAIL_OVERFLOW");
         $fdisplay(log_fd, "FATAL: DDR controller mock test failed with %0d overflow/warning events",
                   overflow_count);
         $fatal(1, "DDR controller mock test failed with %0d overflow/warning events", overflow_count);
      end

      if (monitor_error_count != 0) begin
         monitor_u.write_summary("FAIL_WORST_CASE");
         $fdisplay(log_fd, "FATAL: DDR controller mock test failed with %0d worst-case assertion errors",
                   monitor_error_count);
         $fatal(1, "DDR controller mock test failed with %0d worst-case assertion errors",
                monitor_error_count);
      end

      if (read_budget_error_count != 0) begin
         monitor_u.write_summary("FAIL_READ_BUDGET");
         $fdisplay(log_fd, "FATAL: DDR controller mock test failed with %0d read budget errors",
                   read_budget_error_count);
         $fatal(1, "DDR controller mock test failed with %0d read budget errors",
                read_budget_error_count);
      end

      if (urgent_interrupt_error_count != 0) begin
         monitor_u.write_summary("FAIL_URGENT_INTERRUPT");
         $fdisplay(log_fd, "FATAL: DDR controller mock test failed with %0d urgent interrupt errors",
                   urgent_interrupt_error_count);
         $fatal(1, "DDR controller mock test failed with %0d urgent interrupt errors",
                urgent_interrupt_error_count);
      end

      if (timeout_count != 0) begin
         monitor_u.write_summary("FAIL_TIMEOUT");
         $fdisplay(log_fd, "FATAL: DDR controller mock test timed out after receiving %0d of %0d beats, wr_ptr=%0d rd_ptr=%0d state=%0d read_len=%0d read_cnt=%0d wr_high=%0b wr_urgent=%0b rd_cmds=%0d wr_cmds=%0d",
                   recv_count, sent_count,
                   dut.user_rw_cmd_gen_uut.user_ad_wr_i,
                   dut.user_rw_cmd_gen_uut.user_ad_rd_i,
                   dut.user_rw_cmd_gen_uut.rw_state,
                   dut.user_rw_cmd_gen_uut.read_burst_len,
                   dut.user_rw_cmd_gen_uut.read_beat_cnt,
                   dut.user_rw_cmd_gen_uut.wr_level_high,
                   dut.user_rw_cmd_gen_uut.wr_level_urgent,
                   native_read_cmd_count,
                   native_write_cmd_count);
         $fatal(1, "DDR controller mock test timed out after receiving %0d of %0d beats, wr_ptr=%0d rd_ptr=%0d state=%0d read_len=%0d read_cnt=%0d wr_high=%0b wr_urgent=%0b rd_cmds=%0d wr_cmds=%0d",
                recv_count, sent_count,
                dut.user_rw_cmd_gen_uut.user_ad_wr_i,
                dut.user_rw_cmd_gen_uut.user_ad_rd_i,
                dut.user_rw_cmd_gen_uut.rw_state,
                dut.user_rw_cmd_gen_uut.read_burst_len,
                dut.user_rw_cmd_gen_uut.read_beat_cnt,
                dut.user_rw_cmd_gen_uut.wr_level_high,
                dut.user_rw_cmd_gen_uut.wr_level_urgent,
                native_read_cmd_count,
                native_write_cmd_count);
      end

      if (use_hash_scoreboard && (actual_hash !== expected_hash)) begin
         monitor_u.write_summary("FAIL_HASH");
         $fdisplay(log_fd, "FATAL: DDR controller mock hash mismatch: actual=%h expected=%h",
                   actual_hash, expected_hash);
         $fatal(1, "DDR controller mock hash mismatch: actual=%h expected=%h",
                actual_hash, expected_hash);
      end

      if ((!use_hash_scoreboard) && (expected_q.size() != 0)) begin
         monitor_u.write_summary("FAIL_EXPECTED_QUEUE");
         $fdisplay(log_fd, "FATAL: DDR controller mock test ended with %0d expected beats still queued",
                   expected_q.size());
         $fatal(1, "DDR controller mock test ended with %0d expected beats still queued",
                expected_q.size());
      end

      $display("DDR controller mock slice test passed: views=%0d sent=%0d received=%0d read_cmds=%0d write_cmds=%0d urgent_read_events=%0d",
               sim_view_count, sent_count, recv_count,
               native_read_cmd_count, native_write_cmd_count,
               urgent_read_data_event_count);
      monitor_u.write_summary("PASS");
      $fdisplay(log_fd, "PASS: views=%0d sent=%0d received=%0d read_cmds=%0d write_cmds=%0d urgent_read_events=%0d",
                sim_view_count, sent_count, recv_count,
                native_read_cmd_count, native_write_cmd_count,
                urgent_read_data_event_count);
      $fclose(log_fd);
      $finish;
   end

   always @(posedge clk) begin
      if (!reset && (wr_fifo_overrun || ddr_overrun || ddr_warning)) begin
         overflow_count++;
         $fdisplay(log_fd, "ERROR: DDR status event at %0t: wr_fifo_overrun=%0b ddr_overrun=%0b ddr_warning=%0b",
                   $time, wr_fifo_overrun, ddr_overrun, ddr_warning);
         $error("DDR status event at %0t: wr_fifo_overrun=%0b ddr_overrun=%0b ddr_warning=%0b",
                $time, wr_fifo_overrun, ddr_overrun, ddr_warning);
      end
   end

   always_ff @(posedge clk) begin
      if (reset) begin
         user_r_rd_en <= 1'b0;
      end
      else begin
         user_r_rd_en <= consumer_enable && (!consumer_stall_active) && user_r_valid;
      end
   end

   always @(posedge clk) begin
      if (!reset && user_r_rd_en && user_r_valid) begin
         if (use_hash_scoreboard) begin
            actual_hash = update_hash(actual_hash, user_r_data, recv_count);
         end
         else if (expected_q.size() == 0) begin
            mismatch_count++;
            $fdisplay(log_fd, "ERROR: Unexpected read beat at %0t: data=%h",
                      $time, user_r_data);
            $error("Unexpected read beat at %0t: data=%h", $time, user_r_data);
         end
         else begin
            expected_word = expected_q.pop_front();
            if (user_r_data !== expected_word) begin
               mismatch_count++;
               $fdisplay(log_fd, "ERROR: Read mismatch at beat %0d: data=%h expected=%h",
                         recv_count, user_r_data, expected_word);
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
            for (slice_idx = 0; slice_idx < SLICE_NUM; slice_idx++) begin
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
         while ((write_gap_interval > 0) &&
                ((write_beat_cycle % write_gap_interval) < write_gap_block)) begin
            idle_write_cycle();
            write_gap_cycle_count++;
            write_beat_cycle++;
         end

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
         write_beat_cycle++;
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
         16'(SLICE_NUM),
         16'(SLICE_PAYLOAD_BEATS),
         16'(FTP_NUM),
         16'(CH_NUM)
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
         16'(CONV_PERIOD_US),
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
