`timescale 1ns/1ps

// Read/write command debug monitor.
// - Builds debug active conditions.
// - Tracks current and maximum stalls.
// - Keeps ILA-friendly counter outputs.
module rw_cmd_debug_monitor #(
    parameter int DBG_CNT_WIDTH      = 32,
    parameter int PERF_COUNTER_WIDTH = 48,
    parameter int PERF_WINDOW_CYCLES = 139200
) (
    input  logic                       ui_clk,
    input  logic                       rst,
    input  logic                       ddr_wr_req,
    input  logic                       ddr_rd_req_qual,
    input  logic                       write_data_fire,
    input  logic                       read_cmd_fire,
    input  logic                       read_data_fire,
    input  logic                       block_for_replay,
    input  logic                       in_idle,
    input  logic                       in_arb,
    input  logic                       in_write_req,
    input  logic                       in_read_cmd,
    input  logic                       in_read_data,
    input  logic                       grant_write,
    input  logic                       grant_read,
    input  logic                       wr_fifo_valid,
    input  logic [8:0]                 write_burst_len,
    input  logic [9:0]                 read_burst_len,
    input  logic                       read_cmd_send_en,
    input  logic                       app_rdy,
    input  logic                       app_wdf_rdy,
    input  logic                       app_rd_data_valid,
    input  logic                       rd_fifo_full,
    input  logic                       rd_fifo_has_grant_space,
    input  logic                       wr_level_urgent,
    input  logic                       rd_level_urgent,
    input  logic                       req_stop,
    input  logic                       wr_fifo_full,
    input  logic [14:0]                wr_fifo_data_count,
    input  logic [15:0]                rd_fifo_data_count,
    input  logic                       write_burst_done,
    input  logic                       read_burst_done,
    input  logic                       read_cmd_stop_event,
    input  logic [9:0]                 rd_outstanding,

    output logic                       dbg_wr_no_service,
    output logic                       dbg_rd_no_service,
    output logic                       dbg_replay_block,
    output logic                       dbg_wr_app_rdy_wait,
    output logic                       dbg_wr_wdf_rdy_wait,
    output logic                       dbg_rd_cmd_wait,
    output logic                       dbg_rd_data_wait,
    output logic [DBG_CNT_WIDTH-1:0]   dbg_wr_no_service_cur,
    output logic [DBG_CNT_WIDTH-1:0]   dbg_wr_no_service_max,
    output logic [DBG_CNT_WIDTH-1:0]   dbg_rd_no_service_cur,
    output logic [DBG_CNT_WIDTH-1:0]   dbg_rd_no_service_max,
    output logic [DBG_CNT_WIDTH-1:0]   dbg_replay_block_cur,
    output logic [DBG_CNT_WIDTH-1:0]   dbg_replay_block_max,
    output logic [DBG_CNT_WIDTH-1:0]   dbg_wr_app_rdy_wait_cur,
    output logic [DBG_CNT_WIDTH-1:0]   dbg_wr_app_rdy_wait_max,
    output logic [DBG_CNT_WIDTH-1:0]   dbg_wr_wdf_rdy_wait_cur,
    output logic [DBG_CNT_WIDTH-1:0]   dbg_wr_wdf_rdy_wait_max,
    output logic [DBG_CNT_WIDTH-1:0]   dbg_rd_cmd_wait_cur,
    output logic [DBG_CNT_WIDTH-1:0]   dbg_rd_cmd_wait_max,
    output logic [DBG_CNT_WIDTH-1:0]   dbg_rd_data_wait_cur,
    output logic [DBG_CNT_WIDTH-1:0]   dbg_rd_data_wait_max
);

    assign dbg_wr_no_service   = ddr_wr_req && (~write_data_fire);
    assign dbg_rd_no_service   = ddr_rd_req_qual && (~read_data_fire);
    assign dbg_replay_block    = block_for_replay;
    assign dbg_wr_app_rdy_wait = in_write_req &&
                                 wr_fifo_valid &&
                                 (write_burst_len != 0) &&
                                 app_wdf_rdy &&
                                 (~app_rdy);
    assign dbg_wr_wdf_rdy_wait = in_write_req &&
                                 wr_fifo_valid &&
                                 (write_burst_len != 0) &&
                                 (~app_wdf_rdy);
    assign dbg_rd_cmd_wait     = in_read_cmd &&
                                 (read_burst_len != 0) &&
                                 rd_fifo_has_grant_space &&
                                 (~wr_level_urgent) &&
                                 (~app_rdy);
    assign dbg_rd_data_wait    = in_read_data &&
                                 (~app_rd_data_valid) &&
                                 (~rd_fifo_full);

    native_dbg_streak_counter #(.CNT_WIDTH(DBG_CNT_WIDTH)) u_dbg_wr_no_service (
        .clk    (ui_clk),
        .rst    (rst),
        .active (dbg_wr_no_service),
        .cur    (dbg_wr_no_service_cur),
        .max    (dbg_wr_no_service_max)
    );

    native_dbg_streak_counter #(.CNT_WIDTH(DBG_CNT_WIDTH)) u_dbg_rd_no_service (
        .clk    (ui_clk),
        .rst    (rst),
        .active (dbg_rd_no_service),
        .cur    (dbg_rd_no_service_cur),
        .max    (dbg_rd_no_service_max)
    );

    native_dbg_streak_counter #(.CNT_WIDTH(DBG_CNT_WIDTH)) u_dbg_replay_block (
        .clk    (ui_clk),
        .rst    (rst),
        .active (dbg_replay_block),
        .cur    (dbg_replay_block_cur),
        .max    (dbg_replay_block_max)
    );

    native_dbg_streak_counter #(.CNT_WIDTH(DBG_CNT_WIDTH)) u_dbg_wr_app_rdy_wait (
        .clk    (ui_clk),
        .rst    (rst),
        .active (dbg_wr_app_rdy_wait),
        .cur    (dbg_wr_app_rdy_wait_cur),
        .max    (dbg_wr_app_rdy_wait_max)
    );

    native_dbg_streak_counter #(.CNT_WIDTH(DBG_CNT_WIDTH)) u_dbg_wr_wdf_rdy_wait (
        .clk    (ui_clk),
        .rst    (rst),
        .active (dbg_wr_wdf_rdy_wait),
        .cur    (dbg_wr_wdf_rdy_wait_cur),
        .max    (dbg_wr_wdf_rdy_wait_max)
    );

    native_dbg_streak_counter #(.CNT_WIDTH(DBG_CNT_WIDTH)) u_dbg_rd_cmd_wait (
        .clk    (ui_clk),
        .rst    (rst),
        .active (dbg_rd_cmd_wait),
        .cur    (dbg_rd_cmd_wait_cur),
        .max    (dbg_rd_cmd_wait_max)
    );

    native_dbg_streak_counter #(.CNT_WIDTH(DBG_CNT_WIDTH)) u_dbg_rd_data_wait (
        .clk    (ui_clk),
        .rst    (rst),
        .active (dbg_rd_data_wait),
        .cur    (dbg_rd_data_wait_cur),
        .max    (dbg_rd_data_wait_max)
    );

    native_perf_monitor #(
        .COUNTER_WIDTH      (PERF_COUNTER_WIDTH),
        .PERF_WINDOW_CYCLES (PERF_WINDOW_CYCLES)
    ) perf_monitor_u (
        .ui_clk                    (ui_clk),
        .rst                       (rst),
        .ddr_wr_req                (ddr_wr_req),
        .ddr_rd_req_qual           (ddr_rd_req_qual),
        .write_data_fire           (write_data_fire),
        .read_cmd_fire             (read_cmd_fire),
        .read_data_fire            (read_data_fire),
        .block_for_replay          (block_for_replay),
        .in_idle                   (in_idle),
        .in_arb                    (in_arb),
        .in_write_req              (in_write_req),
        .in_read_cmd               (in_read_cmd),
        .in_read_data              (in_read_data),
        .grant_write               (grant_write),
        .grant_read                (grant_read),
        .wr_fifo_valid             (wr_fifo_valid),
        .write_burst_len           (write_burst_len),
        .read_cmd_send_en          (read_cmd_send_en),
        .app_rdy                   (app_rdy),
        .app_wdf_rdy               (app_wdf_rdy),
        .app_rd_data_valid         (app_rd_data_valid),
        .rd_fifo_has_grant_space   (rd_fifo_has_grant_space),
        .wr_level_urgent           (wr_level_urgent),
        .rd_level_urgent           (rd_level_urgent),
        .req_stop                  (req_stop),
        .wr_fifo_full              (wr_fifo_full),
        .rd_fifo_full              (rd_fifo_full),
        .wr_fifo_data_count        (wr_fifo_data_count),
        .rd_fifo_data_count        (rd_fifo_data_count),
        .write_burst_done          (write_burst_done),
        .read_burst_done           (read_burst_done),
        .read_cmd_stop_event       (read_cmd_stop_event),
        .rd_outstanding            (rd_outstanding)
    );

endmodule
