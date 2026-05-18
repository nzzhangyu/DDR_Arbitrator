`timescale 1ns/1ps

module tb_ddr4_controller_mock;

    // Test dimensions.
    localparam int CLK_PERIOD_PS      = 5000;
    localparam int CONV_PERIOD_US     = 232;
    localparam int DEFAULT_SIM_VIEWS  = 2;
    localparam int TOTAL_VIEWS        = 2320;
    localparam int FTP_NUM            = 30;
    localparam int CH_NUM             = 48;
    localparam int SLICE_NUM          = 128;
    localparam int SAMPLE_BITS        = 16;
    localparam int VIEW_PERIOD_CYCLES = (CONV_PERIOD_US * 1000000) / CLK_PERIOD_PS;

    // Native app bus dimensions.
    localparam int ADDR_WIDTH     = 20;
    localparam int APP_ADDR_WIDTH = ADDR_WIDTH + 4;
    localparam int APP_DATA_BITS  = 128;
    
    // Derived frame and mock-memory limits.
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

    // Scoreboard and monitor state.
    logic [127:0]          expected_q[$];                       // Expected queue.
    logic [127:0]          expected_word;                       // Queue compare word.
    int                    sent_count;                          // Sent beats.
    int                    recv_count;                          // Received beats.
    int                    mismatch_count;                      // Data mismatches.
    int                    overflow_count;                      // Overflow/warning events.
    int                    timeout_count;                       // Timeout flag.
    int                    native_read_cmd_count;               // Native read commands.
    int                    native_write_cmd_count;              // Native write commands.
    int                    read_budget_error_count;             // Read-budget errors.
    int                    urgent_interrupt_error_count;        // Urgent-interrupt errors.
    int                    urgent_read_data_event_count;        // Urgent read-data events.
    int                    sim_view_count;                      // Run view count.
    int                    expected_total_beats;                // Expected beat total.
    int                    max_wr_fifo_level_limit;             // WR FIFO max limit.
    int                    min_rd_fifo_level_limit;             // RD FIFO min limit.
    int                    max_user_underflow_cycles_limit;     // Underflow run limit.
    int                    max_app_rdy_stall_limit;             // app_rdy stall limit.
    int                    max_app_wdf_stall_limit;             // app_wdf_rdy stall limit.
    int                    max_read_data_gap_limit;             // Read-data gap limit.
    int                    underflow_count;                     // Underflow count.
    int                    monitor_error_count;                 // Monitor errors.
    int                    log_fd;                              // Log file handle.
    bit                    use_hash_scoreboard;                 // Hash scoreboard select.
    bit                    worst_check_enable;                  // Worst-check enable.
    logic [63:0]           expected_hash;                       // Sent data hash.
    logic [63:0]           actual_hash;                         // Readback data hash.
    string                 scoreboard_mode;                     // Scoreboard plusarg.
    string                 log_path;                            // Log path plusarg.
    bit                    consumer_enable;                     // Consumer enable.
    bit                    send_done;                           // Stream done.
    logic                  native_read_cmd_fire;                // Accepted read command.
    logic                  native_write_cmd_fire;               // Accepted write command.
    logic                  in_read_data_state;                  // RTL read-data state.
    logic                  urgent_read_data_event_fire;         // Urgent during read data.
    logic                  expected_data_remaining;             // Pending expected data.
    logic                  stream_start;                        // Stream start pulse.

    // DUT.
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

    // Fast native DDR model.
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

    // Business stream source.
    ddr4_controller_tb_stream_source #(
        .CONV_PERIOD_US (CONV_PERIOD_US),
        .CLK_PERIOD_PS  (CLK_PERIOD_PS),
        .FTP_NUM        (FTP_NUM),
        .CH_NUM         (CH_NUM),
        .SLICE_NUM      (SLICE_NUM),
        .SAMPLE_BITS    (SAMPLE_BITS),
        .APP_DATA_BITS  (APP_DATA_BITS)
    ) stream_source_u (
        .clk            (clk),
        .reset          (reset),
        .start          (stream_start),
        .sim_view_count (sim_view_count),
        .data_en        (data_from_ddr_en),
        .data_word      (data_from_ddr_dd),
        .send_done      (send_done)
    );

    // Accepted native command pulses.
    assign native_read_cmd_fire  = app_en && app_rdy && (app_cmd == APP_CMD_READ);
    assign native_write_cmd_fire = app_en && app_rdy && (app_cmd == APP_CMD_WRITE);
    assign in_read_data_state =
        (dut.user_rw_cmd_gen_uut.rw_state == dut.user_rw_cmd_gen_uut.RW_READ_DATA);
    assign urgent_read_data_event_fire =
        in_read_data_state && dut.user_rw_cmd_gen_uut.wr_level_urgent;
    assign ddr_rd_req = ddr_rd_req_base;
    assign expected_data_remaining = (recv_count < sent_count);

    initial clk = 1'b0;
    always #(CLK_PERIOD_PS / 2000.0) clk = ~clk;

    initial fast_mock_clk = 1'b0;
    always #(CLK_PERIOD_PS / 2000.0) fast_mock_clk = ~fast_mock_clk;

    // Passive monitor.
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
        .native_read_cmd_count          (native_read_cmd_count),
        .native_write_cmd_count         (native_write_cmd_count),
        .read_budget_error_count        (read_budget_error_count),
        .urgent_interrupt_error_count   (urgent_interrupt_error_count),
        .urgent_read_data_event_count   (urgent_read_data_event_count),
        .underflow_count                (underflow_count),
        .monitor_error_count            (monitor_error_count)
    );

    initial begin
        // Main scenario: reset, configure, stream, drain, check.
        reset                = 1'b1;
        rst_local_t_ddr_clk  = 1'b0;
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
        max_wr_fifo_level_limit = 16383;
        min_rd_fifo_level_limit = 1;
        max_user_underflow_cycles_limit = 0;
        max_app_rdy_stall_limit = -1;
        max_app_wdf_stall_limit = -1;
        max_read_data_gap_limit = -1;
        log_fd               = 0;
        use_hash_scoreboard  = 1'b0;
        worst_check_enable   = 1'b0;
        expected_hash        = 64'h6a09_e667_f3bc_c909;
        actual_hash          = 64'h6a09_e667_f3bc_c909;
        log_path             = "tb_ddr4_controller_mock.log";
        consumer_enable      = 1'b0;
        stream_start         = 1'b0;

        if (!$value$plusargs("log=%s", log_path)) begin
            log_path = "tb_ddr4_controller_mock.log";
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

        // Optional worst-case limits.
        void'($value$plusargs("worst_check=%d", worst_check_enable));
        void'($value$plusargs("max_wr_fifo_level=%d", max_wr_fifo_level_limit));
        void'($value$plusargs("min_rd_fifo_level=%d", min_rd_fifo_level_limit));
        void'($value$plusargs("max_user_underflow_cycles=%d", max_user_underflow_cycles_limit));
        void'($value$plusargs("max_app_rdy_stall=%d", max_app_rdy_stall_limit));
        void'($value$plusargs("max_app_wdf_stall=%d", max_app_wdf_stall_limit));
        void'($value$plusargs("max_read_data_gap=%d", max_read_data_gap_limit));

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

        $display("DDR mock test config: views=%0d/%0d scoreboard=%s worst_check=%0d slices/view=%0d beats/slice=%0d payload_beats/slice=%0d view_beats=%0d period_cycles=%0d",
                sim_view_count, TOTAL_VIEWS,
                use_hash_scoreboard ? "hash" : "queue",
                worst_check_enable,
                SLICE_NUM,
                SLICE_TOTAL_BEATS, SLICE_PAYLOAD_BEATS,
                VIEW_TOTAL_BEATS, VIEW_PERIOD_CYCLES);
        $fdisplay(log_fd, "CONFIG: views=%0d/%0d scoreboard=%s worst_check=%0d slices/view=%0d beats/slice=%0d payload_beats/slice=%0d view_beats=%0d period_cycles=%0d max_wr_fifo=%0d min_rd_fifo=%0d max_user_underflow=%0d max_app_rdy_stall=%0d max_app_wdf_stall=%0d max_read_data_gap=%0d",
                    sim_view_count, TOTAL_VIEWS,
                    use_hash_scoreboard ? "hash" : "queue",
                    worst_check_enable,
                    SLICE_NUM,
                    SLICE_TOTAL_BEATS, SLICE_PAYLOAD_BEATS,
                    VIEW_TOTAL_BEATS, VIEW_PERIOD_CYCLES,
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
        consumer_enable = 1'b1;
        // Startup guard before gap-free stream.
        repeat (256) @(posedge clk);

        stream_start = 1'b1;
        @(posedge clk);
        stream_start = 1'b0;
        wait_for_completion();

        // Ordered failure checks.
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
        // Controller status failures.
        if (!reset && (wr_fifo_overrun || ddr_overrun || ddr_warning)) begin
            overflow_count++;
            $fdisplay(log_fd, "ERROR: DDR status event at %0t: wr_fifo_overrun=%0b ddr_overrun=%0b ddr_warning=%0b",
                    $time, wr_fifo_overrun, ddr_overrun, ddr_warning);
            $error("DDR status event at %0t: wr_fifo_overrun=%0b ddr_overrun=%0b ddr_warning=%0b",
                    $time, wr_fifo_overrun, ddr_overrun, ddr_warning);
        end
    end

    always @(posedge clk) begin
        // Expected stream sampling.
        if (!reset && data_from_ddr_en) begin
            if (use_hash_scoreboard) begin
                expected_hash = update_hash(expected_hash, data_from_ddr_dd, sent_count);
            end
            else begin
                expected_q.push_back(data_from_ddr_dd);
            end
            sent_count++;
        end
    end

    always_ff @(posedge clk) begin
        // Continuous consumer.
        if (reset) begin
            user_r_rd_en <= 1'b0;
        end
        else begin
            user_r_rd_en <= user_r_valid;
        end
    end

    always @(posedge clk) begin
        // End-to-end data checker.
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
            // Acquisition start pulse.
            @(posedge clk);
            make_data_on     <= 1'b1;
            make_data_p_edge <= 1'b1;
            @(posedge clk);
            make_data_p_edge <= 1'b0;
            repeat (3) @(posedge clk);
            make_data_on <= 1'b0;
        end
    endtask

    task automatic wait_for_completion();
        begin
            // Wait for stream drain.
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
