`timescale 1ns/1ps

`include "ddr4_tb_config.svh"

`ifdef XILINX_SIMULATOR
module short(in1, in1);
   inout in1;
endmodule
`endif

module tb_ddr4_controller_mock;
`ifdef MIG
    import arch_package::*;
`endif

    // Test dimensions.
    localparam int CLK_PERIOD_PS      = 5000;
    localparam int MIG_SYS_PERIOD_PS  = 4998;
    localparam int CONV_PERIOD_US     = 232;
    localparam int DEFAULT_SIM_VIEWS  = 2;
    localparam int TOTAL_VIEWS        = 2320;
    localparam int FTP_NUM            = 30;
    localparam int CH_NUM             = 48;
    localparam int SLICE_NUM          = 128;
    localparam int SAMPLE_BITS        = 16;
    localparam int VIEW_PERIOD_CYCLES = (CONV_PERIOD_US * 1000000) / CLK_PERIOD_PS;

    // Native app bus dimensions.
`ifdef MIG
    localparam int ADDR_WIDTH     = 28; // Real MIG app_addr is 31 bits.
`else
    localparam int ADDR_WIDTH     = 21;
`endif
    localparam int APP_ADDR_WIDTH = ADDR_WIDTH + 3;
    localparam int APP_DATA_BITS  = 128;
    
    // Derived frame and mock-memory limits.
    localparam int READING_HEADER_BEATS  = 17;
    localparam int SLICE_HEADER_BEATS    = 1;
    localparam int SLICE_TRAILER_BEATS   = 1;
    localparam int SAMPLES_PER_BEAT      = APP_DATA_BITS / SAMPLE_BITS;
    localparam int SLICE_PAYLOAD_SAMPLES = FTP_NUM * CH_NUM;
    localparam int SLICE_PAYLOAD_BEATS   = (SLICE_PAYLOAD_SAMPLES + SAMPLES_PER_BEAT - 1) / SAMPLES_PER_BEAT;
    localparam int SLICE_TOTAL_BEATS     = SLICE_HEADER_BEATS + SLICE_PAYLOAD_BEATS + SLICE_TRAILER_BEATS;
    localparam int VIEW_TOTAL_BEATS      = READING_HEADER_BEATS + (SLICE_NUM * SLICE_TOTAL_BEATS);
    localparam int MOCK_MEM_WORDS        = 1 << ADDR_WIDTH;
    localparam int MOCK_MAX_VIEWS        = MOCK_MEM_WORDS / VIEW_TOTAL_BEATS;
    localparam int READ_ENABLE_PERIOD_US = 90;
    localparam int READ_ENABLE_PERIOD_CYCLES =
        (READ_ENABLE_PERIOD_US * 1000000) / CLK_PERIOD_PS;
    localparam int TIMEOUT_MARGIN_WINDOWS = 4;
    localparam int TIMEOUT_MARGIN_CYCLES  = VIEW_PERIOD_CYCLES + 1024;
    localparam logic [2:0] APP_CMD_WRITE = 3'b000;
    localparam logic [2:0] APP_CMD_READ  = 3'b001;
    localparam bit STREAM_INCREMENT_MODE = 1'b0;    // 0: frame, 1: 8-bit repeated increment.

    // Test item select.
    localparam int TEST_NORMAL = 0;                  // Loopback data correctness.
    localparam int TEST_STRESS = 1;                  // Backpressure/overflow/underflow diagnostics.
    localparam int TEST_KIND   = TEST_NORMAL;

    // Normal test: keep the existing fast loopback behavior.
    localparam int NORMAL_SIM_VIEWS                  = DEFAULT_SIM_VIEWS;
    localparam int NORMAL_MAX_WR_FIFO_LEVEL          = 16383;
    localparam int NORMAL_MIN_RD_FIFO_LEVEL          = 1;
    localparam int NORMAL_MAX_USER_UNDERFLOW_CYCLES  = 0;
    localparam int NORMAL_MAX_APP_RDY_STALL          = -1;
    localparam int NORMAL_MAX_APP_WDF_STALL          = -1;
    localparam int NORMAL_MAX_READ_DATA_GAP          = -1;
    localparam int NORMAL_GLOBAL_STALL_INTERVAL      = 0;
    localparam int NORMAL_GLOBAL_STALL_BLOCK         = 0;
    localparam int NORMAL_CMD_STALL_INTERVAL         = 0;
    localparam int NORMAL_CMD_STALL_BLOCK            = 0;
    localparam int NORMAL_READ_STALL_INTERVAL        = 0;
    localparam int NORMAL_READ_STALL_BLOCK           = 0;

    // Stress test: apply moderate mock backpressure and enable worst-case checks.
    localparam int STRESS_SIM_VIEWS                  = DEFAULT_SIM_VIEWS;
    localparam int STRESS_MAX_WR_FIFO_LEVEL          = 16000;
    localparam int STRESS_MIN_RD_FIFO_LEVEL          = 0;
    localparam int STRESS_MAX_USER_UNDERFLOW_CYCLES  = 512;
    localparam int STRESS_MAX_APP_RDY_STALL          = 64;
    localparam int STRESS_MAX_APP_WDF_STALL          = 64;
    localparam int STRESS_MAX_READ_DATA_GAP          = 64;
    localparam int STRESS_GLOBAL_STALL_INTERVAL      = 0;
    localparam int STRESS_GLOBAL_STALL_BLOCK         = 0;
    localparam int STRESS_CMD_STALL_INTERVAL         = 2048;
    localparam int STRESS_CMD_STALL_BLOCK            = 16;
    localparam int STRESS_READ_STALL_INTERVAL        = 4096;
    localparam int STRESS_READ_STALL_BLOCK           = 16;

    localparam bit ACTIVE_STRESS_MODE =
        (TEST_KIND == TEST_STRESS);
    localparam int ACTIVE_SIM_VIEWS =
        ACTIVE_STRESS_MODE ? STRESS_SIM_VIEWS : NORMAL_SIM_VIEWS;
    localparam int ACTIVE_MAX_WR_FIFO_LEVEL =
        ACTIVE_STRESS_MODE ? STRESS_MAX_WR_FIFO_LEVEL : NORMAL_MAX_WR_FIFO_LEVEL;
    localparam int ACTIVE_MIN_RD_FIFO_LEVEL =
        ACTIVE_STRESS_MODE ? STRESS_MIN_RD_FIFO_LEVEL : NORMAL_MIN_RD_FIFO_LEVEL;
    localparam int ACTIVE_MAX_USER_UNDERFLOW_CYCLES =
        ACTIVE_STRESS_MODE ? STRESS_MAX_USER_UNDERFLOW_CYCLES : NORMAL_MAX_USER_UNDERFLOW_CYCLES;
    localparam int ACTIVE_MAX_APP_RDY_STALL =
        ACTIVE_STRESS_MODE ? STRESS_MAX_APP_RDY_STALL : NORMAL_MAX_APP_RDY_STALL;
    localparam int ACTIVE_MAX_APP_WDF_STALL =
        ACTIVE_STRESS_MODE ? STRESS_MAX_APP_WDF_STALL : NORMAL_MAX_APP_WDF_STALL;
    localparam int ACTIVE_MAX_READ_DATA_GAP =
        ACTIVE_STRESS_MODE ? STRESS_MAX_READ_DATA_GAP : NORMAL_MAX_READ_DATA_GAP;
    localparam int ACTIVE_GLOBAL_STALL_INTERVAL =
        ACTIVE_STRESS_MODE ? STRESS_GLOBAL_STALL_INTERVAL : NORMAL_GLOBAL_STALL_INTERVAL;
    localparam int ACTIVE_GLOBAL_STALL_BLOCK =
        ACTIVE_STRESS_MODE ? STRESS_GLOBAL_STALL_BLOCK : NORMAL_GLOBAL_STALL_BLOCK;
    localparam int ACTIVE_CMD_STALL_INTERVAL =
        ACTIVE_STRESS_MODE ? STRESS_CMD_STALL_INTERVAL : NORMAL_CMD_STALL_INTERVAL;
    localparam int ACTIVE_CMD_STALL_BLOCK =
        ACTIVE_STRESS_MODE ? STRESS_CMD_STALL_BLOCK : NORMAL_CMD_STALL_BLOCK;
    localparam int ACTIVE_READ_STALL_INTERVAL =
        ACTIVE_STRESS_MODE ? STRESS_READ_STALL_INTERVAL : NORMAL_READ_STALL_INTERVAL;
    localparam int ACTIVE_READ_STALL_BLOCK =
        ACTIVE_STRESS_MODE ? STRESS_READ_STALL_BLOCK : NORMAL_READ_STALL_BLOCK;

`ifdef MIG
    // Real MIG smoke uses two x8 DDR4 component models to match the 16-bit DQ bus.
    localparam int SDRAM_ADDR_WIDTH      = 17;
    localparam int DQ_WIDTH              = 16;
    localparam int DQS_WIDTH             = 2;
    localparam int DRAM_WIDTH            = 8;
    localparam int NUM_PHYSICAL_PARTS    = DQ_WIDTH / DRAM_WIDTH;
    localparam int RANK_WIDTH            = 1;
    localparam int CS_WIDTH              = 1;
    localparam string CA_MIRROR          = "OFF";
    localparam UTYPE_density CONFIGURED_DENSITY = _16G;
    localparam logic [2:0] WR_CMD        = 3'b100;
    localparam logic [2:0] RD_CMD        = 3'b101;
`endif

    logic                  clk;
    logic                  reset;
    logic                  fast_mock_clk;
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

`ifdef MIG
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
`endif

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
    int                    read_window_count;                   // Downstream read windows.
    int                    sim_view_count;                      // Run view count.
    int                    expected_total_beats;                // Expected beat total.
    int                    timeout_cycle_limit;                 // Runtime timeout cycle limit.
    int                    max_wr_fifo_level_limit;             // WR FIFO max limit.
    int                    min_rd_fifo_level_limit;             // RD FIFO min limit.
    int                    max_user_underflow_cycles_limit;     // Underflow run limit.
    int                    max_app_rdy_stall_limit;             // app_rdy stall limit.
    int                    max_app_wdf_stall_limit;             // app_wdf_rdy stall limit.
    int                    max_read_data_gap_limit;             // Read-data gap limit.
    int                    mock_global_stall_interval_cfg;      // Global pressure period.
    int                    mock_global_stall_block_cfg;         // Global pressure length.
    int                    mock_cmd_stall_interval_cfg;         // Command pressure period.
    int                    mock_cmd_stall_block_cfg;            // Command pressure length.
    int                    mock_read_stall_interval_cfg;        // Read pressure period.
    int                    mock_read_stall_block_cfg;           // Read pressure length.
    int                    underflow_count;                     // Underflow count.
    int                    monitor_error_count;                 // Monitor errors.
    int                    log_fd;                              // Log file handle.
    bit                    use_hash_scoreboard;                 // Hash scoreboard select.
    bit                    worst_check_enable;                  // Worst-check enable.
    logic [63:0]           expected_hash;                       // Sent data hash.
    logic [63:0]           actual_hash;                         // Readback data hash.
    string                 scoreboard_mode;                     // Scoreboard plusarg.
    string                 log_path;                            // Log path plusarg.
    string                 test_kind_name;                      // Selected test item.
    logic                  consumer_enable;                     // Consumer enable.
    bit                    send_done;                           // Stream done.
    logic                  native_read_cmd_fire;                // Accepted read command.
    logic                  native_write_cmd_fire;               // Accepted write command.
    logic                  in_read_data_state;                  // RTL read-data state.
    logic                  urgent_read_data_event_fire;         // Urgent during read data.
    logic                  expected_data_remaining;             // Pending expected data.
    logic                  stream_start;                        // Stream start pulse.
    logic                  read_window_active;                  // Periodic downstream read window.
    logic                  read_window_read_fire;               // Accepted beat in read window.
    int unsigned           read_window_period_cnt;              // 90us window scheduler.
    int unsigned           read_window_beat_cnt;                // Accepted beats in current window.
    logic                  global_stall_active;                 // Mock-only pressure flag.
    logic                  cmd_stall_active;                    // Mock-only pressure flag.
    logic                  read_stall_active;                   // Mock-only pressure flag.

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

`ifdef MIG
    // Real native MIG model. Compile the native/sim/sim_mig export for this mode.
    ddr4_1200m mig_u (
        .c0_init_calib_complete   (init_calib_complete),
        .c0_ddr4_ui_clk           (ui_clk),
        .c0_ddr4_ui_clk_sync_rst  (ui_clk_sync_rst),
        .dbg_bus                  (),
        .dbg_clk                  (dbg_clk),
        .c0_ddr4_adr              (c0_ddr4_adr),
        .c0_ddr4_act_n            (c0_ddr4_act_n),
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
        .sys_rst                  (reset),
        .c0_sys_clk_p             (c0_sys_clk_p),
        .c0_sys_clk_n             (c0_sys_clk_n),
        .c0_ddr4_app_addr         (app_addr),
        .c0_ddr4_app_cmd          (app_cmd),
        .c0_ddr4_app_en           (app_en),
        .c0_ddr4_app_rdy          (app_rdy),
        .c0_ddr4_app_wdf_data     (app_wdf_data),
        .c0_ddr4_app_wdf_mask     (app_wdf_mask),
        .c0_ddr4_app_wdf_wren     (app_wdf_wren),
        .c0_ddr4_app_wdf_end      (app_wdf_end),
        .c0_ddr4_app_wdf_rdy      (app_wdf_rdy),
        .c0_ddr4_app_rd_data      (app_rd_data),
        .c0_ddr4_app_rd_data_valid(app_rd_data_valid),
        .c0_ddr4_app_rd_data_end  (app_rd_data_end)
    );

    assign global_stall_active = 1'b0;
    assign cmd_stall_active    = 1'b0;
    assign read_stall_active   = 1'b0;
`else
    // Fast native DDR model.
    ddr4_fast_mock #(
        .APP_ADDR_WIDTH                (APP_ADDR_WIDTH),
        .MEM_WORDS                     (MOCK_MEM_WORDS),
        .CALIB_DELAY_CYCLES            (16),
        .READ_LATENCY_CYCLES           (3),
        .GLOBAL_STALL_INTERVAL_CYCLES  (ACTIVE_GLOBAL_STALL_INTERVAL),
        .GLOBAL_STALL_CYCLES           (ACTIVE_GLOBAL_STALL_BLOCK),
        .CMD_STALL_INTERVAL_CYCLES     (ACTIVE_CMD_STALL_INTERVAL),
        .CMD_STALL_CYCLES              (ACTIVE_CMD_STALL_BLOCK),
        .READ_STALL_INTERVAL_CYCLES    (ACTIVE_READ_STALL_INTERVAL),
        .READ_STALL_CYCLES             (ACTIVE_READ_STALL_BLOCK)
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

    assign global_stall_active = mock_u.stall_model_u.global_stall_active;
    assign cmd_stall_active    = mock_u.stall_model_u.cmd_stall_active;
    assign read_stall_active   = mock_u.stall_model_u.read_stall_active;
`endif

    // Business stream source.
    ddr4_controller_tb_stream_source #(
        .CONV_PERIOD_US (CONV_PERIOD_US),
        .CLK_PERIOD_PS  (CLK_PERIOD_PS),
        .FTP_NUM        (FTP_NUM),
        .CH_NUM         (CH_NUM),
        .SLICE_NUM      (SLICE_NUM),
        .SAMPLE_BITS    (SAMPLE_BITS),
        .APP_DATA_BITS  (APP_DATA_BITS),
        .INCREMENT_MODE (STREAM_INCREMENT_MODE),
        .MODEL_HEADER_GAPS (1'b0)
    ) stream_source_u (
        .clk            (clk),
        .reset          (reset),
        .start          (stream_start),
        .sim_view_count (sim_view_count),
        .data_en        (data_from_ddr_en),
        .data_word      (data_from_ddr_dd),
        .send_done      (send_done)
    );

    assign ddr_rd_req  = read_window_active;
    assign req_stop    = ~read_window_active;
    assign user_r_rd_en = read_window_active && user_r_valid;

    // Accepted native command pulses.
    assign native_read_cmd_fire  = app_en && app_rdy && (app_cmd == APP_CMD_READ);
    assign native_write_cmd_fire = app_en && app_rdy && (app_cmd == APP_CMD_WRITE);
    assign in_read_data_state =
        (dut.user_rw_cmd_gen_uut.rw_state == dut.user_rw_cmd_gen_uut.RW_READ_DATA);
    assign urgent_read_data_event_fire =
        in_read_data_state && dut.user_rw_cmd_gen_uut.wr_level_urgent;
    assign expected_data_remaining = (recv_count < sent_count);
    assign consumer_enable = read_window_active;
    assign read_window_read_fire = user_r_rd_en && user_r_valid;

    initial clk = 1'b0;
    always #(CLK_PERIOD_PS / 2000.0) clk = ~clk;

    initial fast_mock_clk = 1'b0;
    always #(CLK_PERIOD_PS / 2000.0) fast_mock_clk = ~fast_mock_clk;

    initial c0_sys_clk_p = 1'b0;
    always #(MIG_SYS_PERIOD_PS / 2000.0) c0_sys_clk_p = ~c0_sys_clk_p;
    assign c0_sys_clk_n = ~c0_sys_clk_p;

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
        .global_stall_active            (global_stall_active),
        .cmd_stall_active               (cmd_stall_active),
        .read_stall_active              (read_stall_active),
        .wr_fifo_level                  (dut.ddr_wr_fifo_level),
        .wr_fifo_full                   (dut.ddr_wr_fifo_full),
        .rd_fifo_level                  (dut.ddr_rd_fifo_level),
        .rd_fifo_full                   (dut.ddr_rd_fifo_full),
        .rw_state                       (dut.user_rw_cmd_gen_uut.rw_state),
        .read_burst_len                 (dut.user_rw_cmd_gen_uut.read_burst_len),
        .read_beat_cnt                  (dut.user_rw_cmd_gen_uut.read_beat_cnt),
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
`ifdef MIG
        en_model             = 1'b0;
`endif
        rst_local_t_ddr_clk  = 1'b0;
        rp_back_en           = 1'b0;
        Fault_inject_en      = 1'b0;
        make_data_on         = 1'b0;
        make_data_p_edge     = 1'b0;
        sent_count           = 0;
        recv_count           = 0;
        mismatch_count       = 0;
        overflow_count       = 0;
        timeout_count        = 0;
        sim_view_count       = ACTIVE_SIM_VIEWS;
        timeout_cycle_limit  = 0;
        max_wr_fifo_level_limit = ACTIVE_MAX_WR_FIFO_LEVEL;
        min_rd_fifo_level_limit = ACTIVE_MIN_RD_FIFO_LEVEL;
        max_user_underflow_cycles_limit = ACTIVE_MAX_USER_UNDERFLOW_CYCLES;
        max_app_rdy_stall_limit = ACTIVE_MAX_APP_RDY_STALL;
        max_app_wdf_stall_limit = ACTIVE_MAX_APP_WDF_STALL;
        max_read_data_gap_limit = ACTIVE_MAX_READ_DATA_GAP;
        log_fd               = 0;
        use_hash_scoreboard  = 1'b0;
        worst_check_enable   = ACTIVE_STRESS_MODE;
        expected_hash        = 64'h6a09_e667_f3bc_c909;
        actual_hash          = 64'h6a09_e667_f3bc_c909;
        log_path             = "tb_ddr4_controller_mock.log";
        test_kind_name       = ACTIVE_STRESS_MODE ? "stress" : "normal";
        stream_start         = 1'b0;
        mock_global_stall_interval_cfg = ACTIVE_GLOBAL_STALL_INTERVAL;
        mock_global_stall_block_cfg    = ACTIVE_GLOBAL_STALL_BLOCK;
        mock_cmd_stall_interval_cfg    = ACTIVE_CMD_STALL_INTERVAL;
        mock_cmd_stall_block_cfg       = ACTIVE_CMD_STALL_BLOCK;
        mock_read_stall_interval_cfg   = ACTIVE_READ_STALL_INTERVAL;
        mock_read_stall_block_cfg      = ACTIVE_READ_STALL_BLOCK;

`ifdef MIG
        #5.0 en_model = 1'b1;
`endif

        if ((TEST_KIND != TEST_NORMAL) && (TEST_KIND != TEST_STRESS)) begin
            $fatal(1, "Invalid TEST_KIND=%0d, expected TEST_NORMAL or TEST_STRESS",
                    TEST_KIND);
        end

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
        void'($value$plusargs("mock_global_stall_interval=%d",
                              mock_global_stall_interval_cfg));
        void'($value$plusargs("mock_global_stall_block=%d",
                              mock_global_stall_block_cfg));
        void'($value$plusargs("mock_cmd_stall_interval=%d",
                              mock_cmd_stall_interval_cfg));
        void'($value$plusargs("mock_cmd_stall_block=%d",
                              mock_cmd_stall_block_cfg));
        void'($value$plusargs("mock_read_stall_interval=%d",
                              mock_read_stall_interval_cfg));
        void'($value$plusargs("mock_read_stall_block=%d",
                              mock_read_stall_block_cfg));

        if ((max_wr_fifo_level_limit < 0) || (max_wr_fifo_level_limit > 16383) ||
            (min_rd_fifo_level_limit < 0) || (min_rd_fifo_level_limit > 16383) ||
            (max_user_underflow_cycles_limit < 0) ||
            (max_app_rdy_stall_limit < -1) ||
            (max_app_wdf_stall_limit < -1) ||
            (max_read_data_gap_limit < -1) ||
            (mock_global_stall_interval_cfg < 0) ||
            (mock_global_stall_block_cfg < 0) ||
            (mock_cmd_stall_interval_cfg < 0) ||
            (mock_cmd_stall_block_cfg < 0) ||
            (mock_read_stall_interval_cfg < 0) ||
            (mock_read_stall_block_cfg < 0)) begin
            $fdisplay(log_fd, "FATAL: Invalid worst-case threshold");
            $fatal(1, "Invalid worst-case threshold");
        end
        
        expected_total_beats = sim_view_count * VIEW_TOTAL_BEATS;
        view_size            = VIEW_TOTAL_BEATS[15:0];
        timeout_cycle_limit  =
            (((expected_total_beats + SLICE_TOTAL_BEATS - 1) / SLICE_TOTAL_BEATS) +
             TIMEOUT_MARGIN_WINDOWS) * READ_ENABLE_PERIOD_CYCLES +
            TIMEOUT_MARGIN_CYCLES;

        $display("DDR mock test config: test_kind=%s views=%0d/%0d stream_mode=%s scoreboard=%s worst_check=%0d slices/view=%0d beats/slice=%0d payload_beats/slice=%0d view_beats=%0d period_cycles=%0d read_period_us=%0d read_period_cycles=%0d read_window_beats=%0d timeout_cycles=%0d",
                test_kind_name,
                sim_view_count, TOTAL_VIEWS,
                STREAM_INCREMENT_MODE ? "increment" : "frame",
                use_hash_scoreboard ? "hash" : "queue",
                worst_check_enable,
                SLICE_NUM,
                SLICE_TOTAL_BEATS, SLICE_PAYLOAD_BEATS,
                VIEW_TOTAL_BEATS, VIEW_PERIOD_CYCLES,
                READ_ENABLE_PERIOD_US, READ_ENABLE_PERIOD_CYCLES,
                SLICE_TOTAL_BEATS, timeout_cycle_limit);
        $fdisplay(log_fd, "CONFIG: test_kind=%s views=%0d/%0d stream_mode=%s scoreboard=%s worst_check=%0d slices/view=%0d beats/slice=%0d payload_beats/slice=%0d view_beats=%0d period_cycles=%0d read_period_us=%0d read_period_cycles=%0d read_window_beats=%0d timeout_cycles=%0d max_wr_fifo=%0d min_rd_fifo=%0d max_user_underflow=%0d max_app_rdy_stall=%0d max_app_wdf_stall=%0d max_read_data_gap=%0d global_stall=%0d/%0d cmd_stall=%0d/%0d read_stall=%0d/%0d",
                    test_kind_name,
                    sim_view_count, TOTAL_VIEWS,
                    STREAM_INCREMENT_MODE ? "increment" : "frame",
                    use_hash_scoreboard ? "hash" : "queue",
                    worst_check_enable,
                    SLICE_NUM,
                    SLICE_TOTAL_BEATS, SLICE_PAYLOAD_BEATS,
                    VIEW_TOTAL_BEATS, VIEW_PERIOD_CYCLES,
                    READ_ENABLE_PERIOD_US, READ_ENABLE_PERIOD_CYCLES,
                    SLICE_TOTAL_BEATS, timeout_cycle_limit,
                    max_wr_fifo_level_limit, min_rd_fifo_level_limit,
                    max_user_underflow_cycles_limit,
                    max_app_rdy_stall_limit, max_app_wdf_stall_limit,
                    max_read_data_gap_limit,
                    mock_global_stall_interval_cfg, mock_global_stall_block_cfg,
                    mock_cmd_stall_interval_cfg, mock_cmd_stall_block_cfg,
                    mock_read_stall_interval_cfg, mock_read_stall_block_cfg);

        repeat (12) @(posedge clk);
        reset = 1'b0;
        wait (init_calib_complete);
        repeat (8) @(posedge clk);

        pulse_make_data();
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
            $fdisplay(log_fd, "FATAL: DDR controller mock test timed out after receiving %0d of %0d beats, wr_ptr=%0d rd_ptr=%0d state=%0d read_len=%0d read_cnt=%0d wr_urgent=%0b rd_cmds=%0d wr_cmds=%0d",
                    recv_count, sent_count,
                    dut.user_rw_cmd_gen_uut.ddr_cache_wr_ptr,
                    dut.user_rw_cmd_gen_uut.ddr_cache_rd_ptr,
                    dut.user_rw_cmd_gen_uut.rw_state,
                    dut.user_rw_cmd_gen_uut.read_burst_len,
                    dut.user_rw_cmd_gen_uut.read_beat_cnt,
                    dut.user_rw_cmd_gen_uut.wr_level_urgent,
                    native_read_cmd_count,
                    native_write_cmd_count);
            $fatal(1, "DDR controller mock test timed out after receiving %0d of %0d beats, wr_ptr=%0d rd_ptr=%0d state=%0d read_len=%0d read_cnt=%0d wr_urgent=%0b rd_cmds=%0d wr_cmds=%0d",
                    recv_count, sent_count,
                    dut.user_rw_cmd_gen_uut.ddr_cache_wr_ptr,
                    dut.user_rw_cmd_gen_uut.ddr_cache_rd_ptr,
                    dut.user_rw_cmd_gen_uut.rw_state,
                    dut.user_rw_cmd_gen_uut.read_burst_len,
                    dut.user_rw_cmd_gen_uut.read_beat_cnt,
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

        $display("DDR controller mock slice test passed: test_kind=%s views=%0d sent=%0d received=%0d read_cmds=%0d write_cmds=%0d urgent_read_events=%0d",
                test_kind_name, sim_view_count, sent_count, recv_count,
                native_read_cmd_count, native_write_cmd_count,
                urgent_read_data_event_count);
        monitor_u.write_summary("PASS");
        $fdisplay(log_fd, "PASS: test_kind=%s views=%0d sent=%0d received=%0d read_cmds=%0d write_cmds=%0d urgent_read_events=%0d",
                    test_kind_name, sim_view_count, sent_count, recv_count,
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
        // The downstream consumer wakes every 90us and drains one slice frame.
        if (reset) begin
            read_window_active     <= 1'b0;
            read_window_period_cnt <= '0;
            read_window_beat_cnt   <= '0;
            read_window_count      <= 0;
        end
        else if (stream_start) begin
            read_window_active     <= 1'b0;
            read_window_period_cnt <= '0;
            read_window_beat_cnt   <= '0;
            read_window_count      <= 0;
        end
        else if (send_done && (recv_count == sent_count)) begin
            read_window_active     <= 1'b0;
            read_window_period_cnt <= '0;
            read_window_beat_cnt   <= '0;
        end
        else if (read_window_active) begin
            if (read_window_read_fire) begin
                if (read_window_beat_cnt == (SLICE_TOTAL_BEATS - 1)) begin
                    if (log_fd != 0) begin
                        $fdisplay(log_fd,
                                  "READ_WINDOW: done index=%0d time=%0t beats=%0d recv=%0d sent=%0d",
                                  read_window_count - 1, $time,
                                  SLICE_TOTAL_BEATS, recv_count + 1, sent_count);
                    end
                    read_window_active     <= 1'b0;
                    read_window_period_cnt <= '0;
                    read_window_beat_cnt   <= '0;
                end
                else begin
                    read_window_beat_cnt <= read_window_beat_cnt + 1;
                end
            end
        end
        else if (read_window_period_cnt >= (READ_ENABLE_PERIOD_CYCLES - 1)) begin
            if (log_fd != 0) begin
                $fdisplay(log_fd,
                          "READ_WINDOW: start index=%0d time=%0t period_cycles=%0d target_beats=%0d",
                          read_window_count, $time,
                          READ_ENABLE_PERIOD_CYCLES, SLICE_TOTAL_BEATS);
            end
            read_window_active     <= 1'b1;
            read_window_period_cnt <= '0;
            read_window_beat_cnt   <= '0;
            read_window_count      <= read_window_count + 1;
        end
        else begin
            read_window_period_cnt <= read_window_period_cnt + 1;
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
        wait (timeout_cycle_limit > 0);
        repeat (timeout_cycle_limit) @(posedge clk);
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

`ifdef MIG
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
                        RD_CMD: DDR4_ADRMOD[rnk] =
                            c0_ddr4_adr_sdram[rnk] & 17'h1c7ff;
                        default: DDR4_ADRMOD[rnk] = c0_ddr4_adr_sdram[rnk];
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
`endif

endmodule
