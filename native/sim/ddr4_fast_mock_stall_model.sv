`timescale 1ns/1ps

// Coarse pressure model for the DDR fast mock.
//
// global_stall_active models full DDR/MIG unavailability caused by refresh,
// ZQ/maintenance, calibration, or long internal service windows.
// cmd_stall_active models command/write-data backpressure caused by command
// queues, bank/row timing, bank-group timing, turnaround, or scheduler limits.
// read_stall_active models read-return gaps caused by read latency variation,
// outstanding/pending read pressure, read datapath backpressure, or refresh.
module ddr4_fast_mock_stall_model #(
    parameter int GLOBAL_STALL_INTERVAL_CYCLES = 0,
    parameter int GLOBAL_STALL_CYCLES          = 0,
    parameter int CMD_STALL_INTERVAL_CYCLES    = 0,
    parameter int CMD_STALL_CYCLES             = 0,
    parameter int READ_STALL_INTERVAL_CYCLES   = 0,
    parameter int READ_STALL_CYCLES            = 0
) (
    input  logic       clk,
    input  logic       reset,
    input  logic       init_calib_complete,
    input  logic       read_pipe_output_valid,
    output logic       global_stall_active,
    output logic       cmd_stall_active,
    output logic       read_stall_active,
    output logic       data_stall_active,
    output logic       read_pipe_stall
);

    int   global_stall_interval_cfg;   // Global pressure period.
    int   global_stall_block_cfg;      // Global pressure length.
    int   cmd_stall_interval_cfg;      // Command pressure period.
    int   cmd_stall_block_cfg;         // Command pressure length.
    int   read_stall_interval_cfg;     // Read-return pressure period.
    int   read_stall_block_cfg;        // Read-return pressure length.
    bit   plusarg_seen;                // Plusarg return sink.

    initial begin
        global_stall_interval_cfg = GLOBAL_STALL_INTERVAL_CYCLES;
        global_stall_block_cfg    = GLOBAL_STALL_CYCLES;
        cmd_stall_interval_cfg    = CMD_STALL_INTERVAL_CYCLES;
        cmd_stall_block_cfg       = CMD_STALL_CYCLES;
        read_stall_interval_cfg   = READ_STALL_INTERVAL_CYCLES;
        read_stall_block_cfg      = READ_STALL_CYCLES;

        plusarg_seen = $value$plusargs("mock_global_stall_interval=%d",
                                       global_stall_interval_cfg);
        plusarg_seen = $value$plusargs("mock_global_stall_block=%d",
                                       global_stall_block_cfg);
        plusarg_seen = $value$plusargs("mock_cmd_stall_interval=%d",
                                       cmd_stall_interval_cfg);
        plusarg_seen = $value$plusargs("mock_cmd_stall_block=%d",
                                       cmd_stall_block_cfg);
        plusarg_seen = $value$plusargs("mock_read_stall_interval=%d",
                                       read_stall_interval_cfg);
        plusarg_seen = $value$plusargs("mock_read_stall_block=%d",
                                       read_stall_block_cfg);
    end

    ddr4_fast_mock_periodic_stall global_stall_u (
        .clk                 (clk),
        .reset               (reset),
        .enable              (init_calib_complete),
        .interval_cycles_cfg (global_stall_interval_cfg),
        .block_cycles_cfg    (global_stall_block_cfg),
        .active              (global_stall_active)
    );

    ddr4_fast_mock_periodic_stall cmd_stall_u (
        .clk                 (clk),
        .reset               (reset),
        .enable              (init_calib_complete),
        .interval_cycles_cfg (cmd_stall_interval_cfg),
        .block_cycles_cfg    (cmd_stall_block_cfg),
        .active              (cmd_stall_active)
    );

    ddr4_fast_mock_periodic_stall read_stall_u (
        .clk                 (clk),
        .reset               (reset),
        .enable              (init_calib_complete),
        .interval_cycles_cfg (read_stall_interval_cfg),
        .block_cycles_cfg    (read_stall_block_cfg),
        .active              (read_stall_active)
    );

    assign data_stall_active = global_stall_active || read_stall_active;
    assign read_pipe_stall   = read_pipe_output_valid && data_stall_active;

endmodule
