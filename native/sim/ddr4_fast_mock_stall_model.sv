`timescale 1ns/1ps

// Event-style native-app stall model for the DDR fast mock.
module ddr4_fast_mock_stall_model #(
    parameter int REFRESH_INTERVAL_CYCLES = 0,
    parameter int REFRESH_BLOCK_CYCLES    = 0,
    parameter int MAINT_INTERVAL_CYCLES   = 0,
    parameter int MAINT_BLOCK_CYCLES      = 0,
    parameter int READY_STALL_INTERVAL_CYCLES = 0,
    parameter int READY_STALL_CYCLES          = 0,
    parameter int READ_DATA_GAP_INTERVAL_CYCLES = 0,
    parameter int READ_DATA_GAP_CYCLES          = 0,
    parameter int TURNAROUND_CYCLES     = 0,
    parameter int RTW_TURNAROUND_CYCLES = TURNAROUND_CYCLES,
    parameter int WTR_TURNAROUND_CYCLES = TURNAROUND_CYCLES,
    parameter int CMD_QUEUE_DEPTH = 0,
    parameter int CMD_DRAIN_INTERVAL_CYCLES = 1
) (
    input  logic       clk,
    input  logic       reset,
    input  logic       init_calib_complete,
    input  logic       app_en,
    input  logic [2:0] app_cmd,
    input  logic       app_rdy,
    input  logic       read_pipe_output_valid,
    output logic       cmd_stall_active,
    output logic       data_stall_active,
    output logic       read_pipe_stall,
    output logic       turn_write_block,
    output logic       turn_read_block,
    output logic       refresh_active,
    output logic       maint_active,
    output logic       ready_stall_active,
    output logic       read_gap_active,
    output logic       turnaround_active,
    output logic       cmd_queue_full_active
);

    localparam logic [2:0] APP_CMD_WRITE = 3'b000;
    localparam logic [2:0] APP_CMD_READ  = 3'b001;

    int   refresh_interval_cfg;        // Refresh stall period.
    int   refresh_block_cfg;           // Refresh stall length.
    int   maint_interval_cfg;          // Maintenance period.
    int   maint_block_cfg;             // Maintenance length.
    int   ready_stall_interval_cfg;    // Ready stall period.
    int   ready_stall_block_cfg;       // Ready stall length.
    int   read_gap_interval_cfg;       // Read gap period.
    int   read_gap_block_cfg;          // Read gap length.
    int   rtw_turnaround_cycles_cfg;   // Read-to-write block cycles.
    int   wtr_turnaround_cycles_cfg;   // Write-to-read block cycles.
    int   cmd_queue_depth_cfg;         // Command queue depth.
    int   cmd_drain_interval_cfg;      // Command drain period.
    bit   plusarg_seen;                // Plusarg return sink.

    int   refresh_cnt_q;               // Refresh interval count.
    int   refresh_left_q;              // Refresh active count.
    int   maint_cnt_q;                 // Maintenance interval count.
    int   maint_left_q;                // Maintenance active count.
    int   ready_stall_cnt_q;           // Ready stall interval count.
    int   ready_stall_left_q;          // Ready stall active count.
    int   read_gap_cnt_q;              // Read gap interval count.
    int   read_gap_left_q;             // Read gap active count.
    int   cmd_queue_level_q;           // Command queue level.
    int   cmd_drain_cnt_q;             // Command drain count.

    logic refresh_active_q;            // Refresh active state.
    logic maint_active_q;              // Maintenance active state.
    logic ready_stall_active_q;        // Ready stall active state.
    logic read_gap_active_q;           // Read gap active state.

    logic [15:0] turnaround_cnt_q;            // Turnaround countdown.
    logic        last_cmd_valid_q;            // Direction valid flag.
    logic        last_cmd_was_read_q;         // Last command direction.
    logic        turnaround_pending_q;        // Pending direction switch.
    logic        turnaround_target_is_read_q; // Pending target direction.
    logic        write_turn_request;          // Write turn request.
    logic        read_turn_request;           // Read turn request.
    logic        write_cmd_fire;              // Accepted write command.
    logic        read_cmd_fire;               // Accepted read command.
    logic        cmd_queue_enabled;           // Queue model enable.
    logic        cmd_queue_push;              // Accepted command push.
    logic        cmd_queue_drain;             // Internal command drain.
    logic        cmd_queue_drain_blocked;     // Drain pause reason.

    initial begin
        refresh_interval_cfg      = REFRESH_INTERVAL_CYCLES;
        refresh_block_cfg         = REFRESH_BLOCK_CYCLES;
        maint_interval_cfg        = MAINT_INTERVAL_CYCLES;
        maint_block_cfg           = MAINT_BLOCK_CYCLES;
        ready_stall_interval_cfg  = READY_STALL_INTERVAL_CYCLES;
        ready_stall_block_cfg     = READY_STALL_CYCLES;
        read_gap_interval_cfg     = READ_DATA_GAP_INTERVAL_CYCLES;
        read_gap_block_cfg        = READ_DATA_GAP_CYCLES;
        rtw_turnaround_cycles_cfg = RTW_TURNAROUND_CYCLES;
        wtr_turnaround_cycles_cfg = WTR_TURNAROUND_CYCLES;
        cmd_queue_depth_cfg       = CMD_QUEUE_DEPTH;
        cmd_drain_interval_cfg    = CMD_DRAIN_INTERVAL_CYCLES;

        plusarg_seen = $value$plusargs("mock_refresh_interval=%d", refresh_interval_cfg);
        plusarg_seen = $value$plusargs("mock_refresh_block=%d", refresh_block_cfg);
        plusarg_seen = $value$plusargs("mock_maint_interval=%d", maint_interval_cfg);
        plusarg_seen = $value$plusargs("mock_maint_block=%d", maint_block_cfg);
        plusarg_seen = $value$plusargs("mock_ready_stall_interval=%d", ready_stall_interval_cfg);
        plusarg_seen = $value$plusargs("mock_ready_stall_block=%d", ready_stall_block_cfg);
        plusarg_seen = $value$plusargs("mock_read_gap_interval=%d", read_gap_interval_cfg);
        plusarg_seen = $value$plusargs("mock_read_gap_block=%d", read_gap_block_cfg);
        if ($value$plusargs("mock_turnaround=%d", rtw_turnaround_cycles_cfg)) begin
            wtr_turnaround_cycles_cfg = rtw_turnaround_cycles_cfg;
        end
        plusarg_seen = $value$plusargs("mock_rtw_turnaround=%d", rtw_turnaround_cycles_cfg);
        plusarg_seen = $value$plusargs("mock_wtr_turnaround=%d", wtr_turnaround_cycles_cfg);
        plusarg_seen = $value$plusargs("mock_cmd_queue_depth=%d", cmd_queue_depth_cfg);
        plusarg_seen = $value$plusargs("mock_cmd_drain_interval=%d", cmd_drain_interval_cfg);
    end

    // Periodic refresh event; active holds for the configured block length.
    always_ff @(posedge clk) begin
        if (reset || (~init_calib_complete) ||
            (refresh_interval_cfg <= 0) || (refresh_block_cfg <= 0)) begin
            refresh_cnt_q    <= 0;
            refresh_left_q   <= 0;
            refresh_active_q <= 1'b0;
        end
        else if (refresh_active_q) begin
            if (refresh_left_q <= 1) begin
                refresh_cnt_q    <= 0;
                refresh_left_q   <= 0;
                refresh_active_q <= 1'b0;
            end
            else begin
                refresh_left_q <= refresh_left_q - 1;
            end
        end
        else if (refresh_cnt_q >= (refresh_interval_cfg - 1)) begin
            refresh_cnt_q    <= 0;
            refresh_left_q   <= refresh_block_cfg;
            refresh_active_q <= 1'b1;
        end
        else begin
            refresh_cnt_q <= refresh_cnt_q + 1;
        end
    end

    // Periodic maintenance event; active holds for the configured block length.
    always_ff @(posedge clk) begin
        if (reset || (~init_calib_complete) ||
            (maint_interval_cfg <= 0) || (maint_block_cfg <= 0)) begin
            maint_cnt_q    <= 0;
            maint_left_q   <= 0;
            maint_active_q <= 1'b0;
        end
        else if (maint_active_q) begin
            if (maint_left_q <= 1) begin
                maint_cnt_q    <= 0;
                maint_left_q   <= 0;
                maint_active_q <= 1'b0;
            end
            else begin
                maint_left_q <= maint_left_q - 1;
            end
        end
        else if (maint_cnt_q >= (maint_interval_cfg - 1)) begin
            maint_cnt_q    <= 0;
            maint_left_q   <= maint_block_cfg;
            maint_active_q <= 1'b1;
        end
        else begin
            maint_cnt_q <= maint_cnt_q + 1;
        end
    end

    // Periodic ready stall event; active holds for the configured block length.
    always_ff @(posedge clk) begin
        if (reset || (~init_calib_complete) ||
            (ready_stall_interval_cfg <= 0) || (ready_stall_block_cfg <= 0)) begin
            ready_stall_cnt_q    <= 0;
            ready_stall_left_q   <= 0;
            ready_stall_active_q <= 1'b0;
        end
        else if (ready_stall_active_q) begin
            if (ready_stall_left_q <= 1) begin
                ready_stall_cnt_q    <= 0;
                ready_stall_left_q   <= 0;
                ready_stall_active_q <= 1'b0;
            end
            else begin
                ready_stall_left_q <= ready_stall_left_q - 1;
            end
        end
        else if (ready_stall_cnt_q >= (ready_stall_interval_cfg - 1)) begin
            ready_stall_cnt_q    <= 0;
            ready_stall_left_q   <= ready_stall_block_cfg;
            ready_stall_active_q <= 1'b1;
        end
        else begin
            ready_stall_cnt_q <= ready_stall_cnt_q + 1;
        end
    end

    // Periodic read-data gap event; active holds for the configured block length.
    always_ff @(posedge clk) begin
        if (reset || (~init_calib_complete) ||
            (read_gap_interval_cfg <= 0) || (read_gap_block_cfg <= 0)) begin
            read_gap_cnt_q    <= 0;
            read_gap_left_q   <= 0;
            read_gap_active_q <= 1'b0;
        end
        else if (read_gap_active_q) begin
            if (read_gap_left_q <= 1) begin
                read_gap_cnt_q    <= 0;
                read_gap_left_q   <= 0;
                read_gap_active_q <= 1'b0;
            end
            else begin
                read_gap_left_q <= read_gap_left_q - 1;
            end
        end
        else if (read_gap_cnt_q >= (read_gap_interval_cfg - 1)) begin
            read_gap_cnt_q    <= 0;
            read_gap_left_q   <= read_gap_block_cfg;
            read_gap_active_q <= 1'b1;
        end
        else begin
            read_gap_cnt_q <= read_gap_cnt_q + 1;
        end
    end

    assign refresh_active     = refresh_active_q;
    assign maint_active       = maint_active_q;
    assign ready_stall_active = ready_stall_active_q;
    assign read_gap_active    = read_gap_active_q;

    assign cmd_stall_active  = refresh_active || maint_active ||
                                ready_stall_active || cmd_queue_full_active;
    assign data_stall_active = refresh_active || maint_active || read_gap_active;
    assign read_pipe_stall   = read_pipe_output_valid && data_stall_active;

    // Block a new direction before accepting it.
    assign write_turn_request = app_en &&
                                (app_cmd == APP_CMD_WRITE) &&
                                last_cmd_valid_q &&
                                last_cmd_was_read_q &&
                                (~turnaround_pending_q) &&
                                (rtw_turnaround_cycles_cfg > 0);
    assign read_turn_request  = app_en &&
                                (app_cmd == APP_CMD_READ) &&
                                last_cmd_valid_q &&
                                (~last_cmd_was_read_q) &&
                                (~turnaround_pending_q) &&
                                (wtr_turnaround_cycles_cfg > 0);

    assign turn_write_block = write_turn_request ||
                              (turnaround_pending_q &&
                               (~turnaround_target_is_read_q) &&
                               (turnaround_cnt_q != 0));
    assign turn_read_block  = read_turn_request ||
                              (turnaround_pending_q &&
                               turnaround_target_is_read_q &&
                               (turnaround_cnt_q != 0));
    assign turnaround_active = turn_write_block || turn_read_block;

    assign write_cmd_fire = app_en && app_rdy && (app_cmd == APP_CMD_WRITE);
    assign read_cmd_fire  = app_en && app_rdy && (app_cmd == APP_CMD_READ);
    assign cmd_queue_enabled = (cmd_queue_depth_cfg > 0) && (cmd_drain_interval_cfg > 0);
    assign cmd_queue_push = cmd_queue_enabled && (write_cmd_fire || read_cmd_fire);
    assign cmd_queue_drain_blocked = refresh_active || maint_active || turnaround_active;
    assign cmd_queue_drain = cmd_queue_enabled &&
                             (~cmd_queue_drain_blocked) &&
                             (cmd_queue_level_q != 0) &&
                             (cmd_drain_cnt_q >= (cmd_drain_interval_cfg - 1));
    assign cmd_queue_full_active = cmd_queue_enabled &&
                                   (cmd_queue_level_q >= cmd_queue_depth_cfg);

    // Accepted commands fill a small queue; internal drain frees space over time.
    always_ff @(posedge clk) begin
        if (reset || (~init_calib_complete) || (~cmd_queue_enabled)) begin
            cmd_queue_level_q <= 0;
            cmd_drain_cnt_q   <= 0;
        end
        else begin
            if (cmd_queue_drain_blocked || (cmd_queue_level_q == 0)) begin
                cmd_drain_cnt_q <= 0;
            end
            else if (cmd_queue_drain) begin
                cmd_drain_cnt_q <= 0;
            end
            else begin
                cmd_drain_cnt_q <= cmd_drain_cnt_q + 1;
            end

            unique case ({cmd_queue_push, cmd_queue_drain})
                2'b10: begin
                    if (cmd_queue_level_q < cmd_queue_depth_cfg) begin
                        cmd_queue_level_q <= cmd_queue_level_q + 1;
                    end
                end

                2'b01: begin
                    cmd_queue_level_q <= cmd_queue_level_q - 1;
                end

                default: begin
                    cmd_queue_level_q <= cmd_queue_level_q;
                end
            endcase
        end
    end

    // Track read/write direction and block the first opposite-direction request.
    always_ff @(posedge clk) begin
        if (reset || (~init_calib_complete)) begin
            turnaround_cnt_q            <= '0;
            last_cmd_valid_q            <= 1'b0;
            last_cmd_was_read_q         <= 1'b0;
            turnaround_pending_q        <= 1'b0;
            turnaround_target_is_read_q <= 1'b0;
        end
        else begin
            if (turnaround_cnt_q != 0) begin
                turnaround_cnt_q <= turnaround_cnt_q - 16'd1;
            end

            if (write_turn_request) begin
                turnaround_cnt_q            <= 16'(rtw_turnaround_cycles_cfg - 1);
                turnaround_pending_q        <= 1'b1;
                turnaround_target_is_read_q <= 1'b0;
            end
            else if (read_turn_request) begin
                turnaround_cnt_q            <= 16'(wtr_turnaround_cycles_cfg - 1);
                turnaround_pending_q        <= 1'b1;
                turnaround_target_is_read_q <= 1'b1;
            end

            if (write_cmd_fire) begin
                last_cmd_valid_q     <= 1'b1;
                last_cmd_was_read_q  <= 1'b0;
                turnaround_pending_q <= 1'b0;
            end
            else if (read_cmd_fire) begin
                last_cmd_valid_q     <= 1'b1;
                last_cmd_was_read_q  <= 1'b1;
                turnaround_pending_q <= 1'b0;
            end
        end
    end

endmodule
