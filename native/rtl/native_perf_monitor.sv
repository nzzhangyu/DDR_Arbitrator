`timescale 1ns/1ps

// Rolling, snapshot-based performance monitor for the native MIG app interface.
// Counters contain raw events only; bandwidth and efficiency are calculated offline.
module native_perf_monitor #(
    parameter int COUNTER_WIDTH      = 48,
    parameter int PERF_WINDOW_CYCLES = 139200
) (
    input logic        ui_clk,
    input logic        rst,
    input logic        ddr_wr_req,
    input logic        ddr_rd_req_qual,
    input logic        write_data_fire,
    input logic        read_cmd_fire,
    input logic        read_data_fire,
    input logic        block_for_replay,
    input logic        in_idle,
    input logic        in_arb,
    input logic        in_write_req,
    input logic        in_read_cmd,
    input logic        in_read_data,
    input logic        grant_write,
    input logic        grant_read,
    input logic        wr_fifo_valid,
    input logic [8:0]  write_burst_len,
    input logic        read_cmd_send_en,
    input logic        app_rdy,
    input logic        app_wdf_rdy,
    input logic        app_rd_data_valid,
    input logic        rd_fifo_has_grant_space,
    input logic        wr_level_urgent,
    input logic        rd_level_urgent,
    input logic        req_stop,
    input logic        wr_fifo_full,
    input logic        rd_fifo_full,
    input logic [14:0] wr_fifo_data_count,
    input logic [15:0] rd_fifo_data_count,
    input logic        write_burst_done,
    input logic        read_burst_done,
    input logic        read_cmd_stop_event,
    input logic [9:0]  rd_outstanding
);

    localparam int METRIC_COUNT = 37;
    localparam int WINDOW_COUNT_WIDTH = (PERF_WINDOW_CYCLES <= 1) ? 1 :
                                        $clog2(PERF_WINDOW_CYCLES);

    localparam int M_WR_FIRE          = 0;
    localparam int M_RD_CMD_FIRE      = 1;
    localparam int M_RD_DATA_FIRE     = 2;
    localparam int M_CMD_FIRE         = 3;
    localparam int M_PAYLOAD          = 4;
    localparam int M_WR_DEMAND        = 5;
    localparam int M_RD_DEMAND        = 6;
    localparam int M_BOTH_DEMAND      = 7;
    localparam int M_NO_DEMAND        = 8;
    localparam int M_WR_NO_SERVICE    = 9;
    localparam int M_RD_NO_SERVICE    = 10;
    localparam int M_IDLE             = 11;
    localparam int M_ARB              = 12;
    localparam int M_WRITE_STATE      = 13;
    localparam int M_RD_CMD_STATE     = 14;
    localparam int M_RD_DATA_STATE    = 15;
    localparam int M_WR_APP_RDY_WAIT  = 16;
    localparam int M_WR_WDF_WAIT      = 17;
    localparam int M_RD_CMD_RDY_WAIT  = 18;
    localparam int M_RD_DATA_WAIT     = 19;
    localparam int M_RD_SPACE_BLOCK   = 20;
    localparam int M_WR_URGENT_BLOCK  = 21;
    localparam int M_REQ_STOP         = 22;
    localparam int M_REPLAY_BLOCK     = 23;
    localparam int M_RD_FULL_RISK     = 24;
    localparam int M_WR_URG_CYCLES    = 25;
    localparam int M_RD_URG_CYCLES    = 26;
    localparam int M_WR_URG_EVENTS    = 27;
    localparam int M_RD_URG_EVENTS    = 28;
    localparam int M_WR_FULL_CYCLES   = 29;
    localparam int M_RD_FULL_CYCLES   = 30;
    localparam int M_RD_EMPTY_CYCLES  = 31;
    localparam int M_WR_GRANTS        = 32;
    localparam int M_RD_GRANTS        = 33;
    localparam int M_WR_BURST_DONE    = 34;
    localparam int M_RD_BURST_DONE    = 35;
    localparam int M_RD_CMD_STOP      = 36;

    logic [COUNTER_WIDTH-1:0] live_count [0:METRIC_COUNT-1];
    logic [COUNTER_WIDTH-1:0] snapshot_count [0:METRIC_COUNT-1];
    logic [1:0]               metric_delta [0:METRIC_COUNT-1];
    logic [WINDOW_COUNT_WIDTH-1:0] window_cycle_count;
    logic wr_urgent_d;
    logic rd_urgent_d;
    logic live_overflow;
    logic [14:0] live_wr_fifo_max;
    logic [14:0] live_wr_fifo_min;
    logic [15:0] live_rd_fifo_max;
    logic [15:0] live_rd_fifo_min;
    logic [9:0]  live_rd_outstanding_max;
    integer i;

    wire window_last = (window_cycle_count == PERF_WINDOW_CYCLES - 1);

    always_comb begin
        for (int j = 0; j < METRIC_COUNT; j++) begin
            metric_delta[j] = 2'd0;
        end
        metric_delta[M_WR_FIRE]         = {1'b0, write_data_fire};
        metric_delta[M_RD_CMD_FIRE]     = {1'b0, read_cmd_fire};
        metric_delta[M_RD_DATA_FIRE]    = {1'b0, read_data_fire};
        metric_delta[M_CMD_FIRE]        = {1'b0, write_data_fire || read_cmd_fire};
        metric_delta[M_PAYLOAD]         = write_data_fire + read_data_fire;
        metric_delta[M_WR_DEMAND]       = {1'b0, ddr_wr_req};
        metric_delta[M_RD_DEMAND]       = {1'b0, ddr_rd_req_qual};
        metric_delta[M_BOTH_DEMAND]     = {1'b0, ddr_wr_req && ddr_rd_req_qual};
        metric_delta[M_NO_DEMAND]       = {1'b0, !ddr_wr_req && !ddr_rd_req_qual};
        metric_delta[M_WR_NO_SERVICE]   = {1'b0, ddr_wr_req && !write_data_fire};
        metric_delta[M_RD_NO_SERVICE]   = {1'b0, ddr_rd_req_qual && !read_data_fire};
        metric_delta[M_IDLE]            = {1'b0, in_idle};
        metric_delta[M_ARB]             = {1'b0, in_arb};
        metric_delta[M_WRITE_STATE]     = {1'b0, in_write_req};
        metric_delta[M_RD_CMD_STATE]    = {1'b0, in_read_cmd};
        metric_delta[M_RD_DATA_STATE]   = {1'b0, in_read_data};
        metric_delta[M_WR_APP_RDY_WAIT] = {1'b0, in_write_req && wr_fifo_valid &&
                                                   (write_burst_len != 0) &&
                                                   app_wdf_rdy && !app_rdy};
        metric_delta[M_WR_WDF_WAIT]     = {1'b0, in_write_req && wr_fifo_valid &&
                                                   (write_burst_len != 0) &&
                                                   !app_wdf_rdy};
        metric_delta[M_RD_CMD_RDY_WAIT] = {1'b0, read_cmd_send_en && !app_rdy};
        metric_delta[M_RD_DATA_WAIT]    = {1'b0, in_read_data &&
                                                   !app_rd_data_valid && !rd_fifo_full};
        metric_delta[M_RD_SPACE_BLOCK]  = {1'b0, ddr_rd_req_qual &&
                                                   !rd_fifo_has_grant_space};
        metric_delta[M_WR_URGENT_BLOCK] = {1'b0, ddr_rd_req_qual && wr_level_urgent};
        metric_delta[M_REQ_STOP]        = {1'b0, in_read_cmd && req_stop};
        metric_delta[M_REPLAY_BLOCK]    = {1'b0, block_for_replay};
        metric_delta[M_RD_FULL_RISK]    = {1'b0, app_rd_data_valid && rd_fifo_full};
        metric_delta[M_WR_URG_CYCLES]   = {1'b0, wr_level_urgent};
        metric_delta[M_RD_URG_CYCLES]   = {1'b0, rd_level_urgent};
        metric_delta[M_WR_URG_EVENTS]   = {1'b0, wr_level_urgent && !wr_urgent_d};
        metric_delta[M_RD_URG_EVENTS]   = {1'b0, rd_level_urgent && !rd_urgent_d};
        metric_delta[M_WR_FULL_CYCLES]  = {1'b0, wr_fifo_full};
        metric_delta[M_RD_FULL_CYCLES]  = {1'b0, rd_fifo_full};
        metric_delta[M_RD_EMPTY_CYCLES] = {1'b0, rd_fifo_data_count == 0};
        metric_delta[M_WR_GRANTS]       = {1'b0, in_arb && grant_write};
        metric_delta[M_RD_GRANTS]       = {1'b0, in_arb && grant_read};
        metric_delta[M_WR_BURST_DONE]   = {1'b0, write_burst_done};
        metric_delta[M_RD_BURST_DONE]   = {1'b0, read_burst_done};
        metric_delta[M_RD_CMD_STOP]     = {1'b0, read_cmd_stop_event};
    end

    (* mark_debug = "true" *) logic perf_snapshot_valid;
    (* mark_debug = "true" *) logic [31:0] perf_snapshot_seq;
    (* mark_debug = "true" *) logic [COUNTER_WIDTH-1:0] perf_window_cycles;
    (* mark_debug = "true" *) logic perf_counter_overflow;
    (* mark_debug = "true" *) logic [14:0] perf_wr_fifo_max, perf_wr_fifo_min;
    (* mark_debug = "true" *) logic [15:0] perf_rd_fifo_max, perf_rd_fifo_min;
    (* mark_debug = "true" *) logic [9:0] perf_rd_outstanding_max, perf_rd_outstanding_end;

    // Named aliases keep ILA probe selection and exported-wave analysis readable.
    (* mark_debug = "true" *) wire [COUNTER_WIDTH-1:0] perf_wr_fire_count             = snapshot_count[M_WR_FIRE];
    (* mark_debug = "true" *) wire [COUNTER_WIDTH-1:0] perf_rd_cmd_fire_count         = snapshot_count[M_RD_CMD_FIRE];
    (* mark_debug = "true" *) wire [COUNTER_WIDTH-1:0] perf_rd_data_fire_count        = snapshot_count[M_RD_DATA_FIRE];
    (* mark_debug = "true" *) wire [COUNTER_WIDTH-1:0] perf_cmd_fire_count            = snapshot_count[M_CMD_FIRE];
    (* mark_debug = "true" *) wire [COUNTER_WIDTH-1:0] perf_payload_count             = snapshot_count[M_PAYLOAD];
    (* mark_debug = "true" *) wire [COUNTER_WIDTH-1:0] perf_wr_demand_cycles          = snapshot_count[M_WR_DEMAND];
    (* mark_debug = "true" *) wire [COUNTER_WIDTH-1:0] perf_rd_demand_cycles          = snapshot_count[M_RD_DEMAND];
    (* mark_debug = "true" *) wire [COUNTER_WIDTH-1:0] perf_both_demand_cycles        = snapshot_count[M_BOTH_DEMAND];
    (* mark_debug = "true" *) wire [COUNTER_WIDTH-1:0] perf_no_demand_cycles          = snapshot_count[M_NO_DEMAND];
    (* mark_debug = "true" *) wire [COUNTER_WIDTH-1:0] perf_wr_no_service_cycles      = snapshot_count[M_WR_NO_SERVICE];
    (* mark_debug = "true" *) wire [COUNTER_WIDTH-1:0] perf_rd_no_service_cycles      = snapshot_count[M_RD_NO_SERVICE];
    (* mark_debug = "true" *) wire [COUNTER_WIDTH-1:0] perf_idle_cycles               = snapshot_count[M_IDLE];
    (* mark_debug = "true" *) wire [COUNTER_WIDTH-1:0] perf_arb_cycles                = snapshot_count[M_ARB];
    (* mark_debug = "true" *) wire [COUNTER_WIDTH-1:0] perf_write_state_cycles        = snapshot_count[M_WRITE_STATE];
    (* mark_debug = "true" *) wire [COUNTER_WIDTH-1:0] perf_read_cmd_state_cycles     = snapshot_count[M_RD_CMD_STATE];
    (* mark_debug = "true" *) wire [COUNTER_WIDTH-1:0] perf_read_data_state_cycles    = snapshot_count[M_RD_DATA_STATE];
    (* mark_debug = "true" *) wire [COUNTER_WIDTH-1:0] perf_wr_app_rdy_wait_cycles    = snapshot_count[M_WR_APP_RDY_WAIT];
    (* mark_debug = "true" *) wire [COUNTER_WIDTH-1:0] perf_wr_wdf_wait_cycles        = snapshot_count[M_WR_WDF_WAIT];
    (* mark_debug = "true" *) wire [COUNTER_WIDTH-1:0] perf_rd_cmd_rdy_wait_cycles    = snapshot_count[M_RD_CMD_RDY_WAIT];
    (* mark_debug = "true" *) wire [COUNTER_WIDTH-1:0] perf_rd_data_wait_cycles       = snapshot_count[M_RD_DATA_WAIT];
    (* mark_debug = "true" *) wire [COUNTER_WIDTH-1:0] perf_rd_space_block_cycles     = snapshot_count[M_RD_SPACE_BLOCK];
    (* mark_debug = "true" *) wire [COUNTER_WIDTH-1:0] perf_wr_urgent_block_cycles    = snapshot_count[M_WR_URGENT_BLOCK];
    (* mark_debug = "true" *) wire [COUNTER_WIDTH-1:0] perf_req_stop_cycles          = snapshot_count[M_REQ_STOP];
    (* mark_debug = "true" *) wire [COUNTER_WIDTH-1:0] perf_replay_block_cycles       = snapshot_count[M_REPLAY_BLOCK];
    (* mark_debug = "true" *) wire [COUNTER_WIDTH-1:0] perf_rd_fifo_full_drop_risk    = snapshot_count[M_RD_FULL_RISK];
    (* mark_debug = "true" *) wire [COUNTER_WIDTH-1:0] perf_wr_urgent_cycles          = snapshot_count[M_WR_URG_CYCLES];
    (* mark_debug = "true" *) wire [COUNTER_WIDTH-1:0] perf_rd_urgent_cycles          = snapshot_count[M_RD_URG_CYCLES];
    (* mark_debug = "true" *) wire [COUNTER_WIDTH-1:0] perf_wr_urgent_events          = snapshot_count[M_WR_URG_EVENTS];
    (* mark_debug = "true" *) wire [COUNTER_WIDTH-1:0] perf_rd_urgent_events          = snapshot_count[M_RD_URG_EVENTS];
    (* mark_debug = "true" *) wire [COUNTER_WIDTH-1:0] perf_wr_fifo_full_cycles       = snapshot_count[M_WR_FULL_CYCLES];
    (* mark_debug = "true" *) wire [COUNTER_WIDTH-1:0] perf_rd_fifo_full_cycles       = snapshot_count[M_RD_FULL_CYCLES];
    (* mark_debug = "true" *) wire [COUNTER_WIDTH-1:0] perf_rd_fifo_empty_cycles      = snapshot_count[M_RD_EMPTY_CYCLES];
    (* mark_debug = "true" *) wire [COUNTER_WIDTH-1:0] perf_wr_grant_count            = snapshot_count[M_WR_GRANTS];
    (* mark_debug = "true" *) wire [COUNTER_WIDTH-1:0] perf_rd_grant_count            = snapshot_count[M_RD_GRANTS];
    (* mark_debug = "true" *) wire [COUNTER_WIDTH-1:0] perf_wr_burst_done_count       = snapshot_count[M_WR_BURST_DONE];
    (* mark_debug = "true" *) wire [COUNTER_WIDTH-1:0] perf_rd_burst_done_count       = snapshot_count[M_RD_BURST_DONE];
    (* mark_debug = "true" *) wire [COUNTER_WIDTH-1:0] perf_rd_cmd_stop_count         = snapshot_count[M_RD_CMD_STOP];

    always_ff @(posedge ui_clk) begin
        if (rst) begin
            window_cycle_count       <= '0;
            perf_snapshot_valid      <= 1'b0;
            perf_snapshot_seq        <= '0;
            perf_window_cycles       <= '0;
            live_overflow            <= 1'b0;
            perf_counter_overflow    <= 1'b0;
            wr_urgent_d              <= 1'b0;
            rd_urgent_d              <= 1'b0;
            live_wr_fifo_max         <= '0;
            live_wr_fifo_min         <= {15{1'b1}};
            live_rd_fifo_max         <= '0;
            live_rd_fifo_min         <= {16{1'b1}};
            live_rd_outstanding_max  <= '0;
            perf_wr_fifo_max         <= '0;
            perf_wr_fifo_min         <= '0;
            perf_rd_fifo_max         <= '0;
            perf_rd_fifo_min         <= '0;
            perf_rd_outstanding_max  <= '0;
            perf_rd_outstanding_end  <= '0;
            for (i = 0; i < METRIC_COUNT; i = i + 1) begin
                live_count[i]     <= '0;
                snapshot_count[i] <= '0;
            end
        end
        else begin
            wr_urgent_d <= wr_level_urgent;
            rd_urgent_d <= rd_level_urgent;

            if (window_last) begin
                window_cycle_count      <= '0;
                perf_snapshot_valid     <= 1'b1;
                perf_snapshot_seq       <= perf_snapshot_seq + 1'b1;
                perf_window_cycles      <= PERF_WINDOW_CYCLES;
                perf_counter_overflow   <= live_overflow;
                perf_wr_fifo_max        <= (wr_fifo_data_count > live_wr_fifo_max) ?
                                           wr_fifo_data_count : live_wr_fifo_max;
                perf_wr_fifo_min        <= (wr_fifo_data_count < live_wr_fifo_min) ?
                                           wr_fifo_data_count : live_wr_fifo_min;
                perf_rd_fifo_max        <= (rd_fifo_data_count > live_rd_fifo_max) ?
                                           rd_fifo_data_count : live_rd_fifo_max;
                perf_rd_fifo_min        <= (rd_fifo_data_count < live_rd_fifo_min) ?
                                           rd_fifo_data_count : live_rd_fifo_min;
                perf_rd_outstanding_max <= (rd_outstanding > live_rd_outstanding_max) ?
                                           rd_outstanding : live_rd_outstanding_max;
                perf_rd_outstanding_end <= rd_outstanding;
                live_wr_fifo_max        <= '0;
                live_wr_fifo_min        <= {15{1'b1}};
                live_rd_fifo_max        <= '0;
                live_rd_fifo_min        <= {16{1'b1}};
                live_rd_outstanding_max <= '0;
                live_overflow           <= 1'b0;
                for (i = 0; i < METRIC_COUNT; i = i + 1) begin
                    snapshot_count[i] <= live_count[i] + metric_delta[i];
                    live_count[i]     <= '0;
                    if ((metric_delta[i] != 0) &&
                        (live_count[i] > ({COUNTER_WIDTH{1'b1}} - metric_delta[i]))) begin
                        perf_counter_overflow <= 1'b1;
                    end
                end
            end
            else begin
                window_cycle_count <= window_cycle_count + 1'b1;
                if (wr_fifo_data_count > live_wr_fifo_max)
                    live_wr_fifo_max <= wr_fifo_data_count;
                if (wr_fifo_data_count < live_wr_fifo_min)
                    live_wr_fifo_min <= wr_fifo_data_count;
                if (rd_fifo_data_count > live_rd_fifo_max)
                    live_rd_fifo_max <= rd_fifo_data_count;
                if (rd_fifo_data_count < live_rd_fifo_min)
                    live_rd_fifo_min <= rd_fifo_data_count;
                if (rd_outstanding > live_rd_outstanding_max)
                    live_rd_outstanding_max <= rd_outstanding;
                for (i = 0; i < METRIC_COUNT; i = i + 1) begin
                    live_count[i] <= live_count[i] + metric_delta[i];
                    if ((metric_delta[i] != 0) &&
                        (live_count[i] > ({COUNTER_WIDTH{1'b1}} - metric_delta[i]))) begin
                        live_overflow <= 1'b1;
                    end
                end
            end
        end
    end

endmodule
