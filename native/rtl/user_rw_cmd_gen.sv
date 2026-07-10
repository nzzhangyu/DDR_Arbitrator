`timescale 1ns/1ps

module user_rw_cmd_gen #(
   parameter int ADDR_WIDTH     = 24,
   parameter int APP_ADDR_WIDTH = ADDR_WIDTH + 3
) (
    // Native app interface.
    output logic [APP_ADDR_WIDTH-1:0] app_addr,
    output logic [2:0]                app_cmd,
    output logic                      app_en,
    input  logic                      app_rdy,
    output logic [127:0]              app_wdf_data,
    output logic [15:0]               app_wdf_mask,
    output logic                      app_wdf_wren,
    output logic                      app_wdf_end,
    input  logic                      app_wdf_rdy,
    input  logic [127:0]              app_rd_data,
    input  logic                      app_rd_data_valid,
    input  logic                      app_rd_data_end,

    output logic                      make_data_p_edge_ddr_clk,
    output logic                      ddr_rd_empty,
    output logic                      ddr_overrun,
    output logic                      ddr_warning,               // warning for overrunning
    output logic                      wr_fifo_rd_en,
    output logic [127:0]              rd_fifo_din,
    output logic                      rd_fifo_wr_en,

    input  logic                      init_calib_complete,
    input  logic                      ui_clk,
    input  logic                      ui_clk_sync_rst,
    input  logic                      ddr_rd_req,
    input  logic                      req_stop,
    input  logic                      make_data_on,
    input  logic [15:0]               view_size,
    input  logic                      rst_local_t_ddr_clk,
    input  logic                      fault_ddr_overrun,
    input  logic                      fault_ddr_warning,
    input  logic                      wr_fifo_empty,
    input  logic                      wr_fifo_full,
    input  logic                      wr_fifo_valid,
    input  logic                      wr_fifo_prog_empty,
    input  logic [14:0]               wr_fifo_rd_data_count,
    input  logic                      wr_fifo_overrun,
    input  logic [127:0]              wr_fifo_dout,
    input  logic                      rd_fifo_prog_full,
    input  logic                      rd_fifo_almost_empty,
    input  logic [15:0]               rd_fifo_data_count,
    input  logic                      rd_fifo_full,
    input  logic                      rp_back_en,
    input  logic [ADDR_WIDTH-1:0]     rp_back_view_addr
);

    // Watermark thresholds.
    localparam logic [14:0] WR_LEVEL_URGENT   = 15'd6144;   // Force writes, block reads.
    localparam logic [14:0] WR_LEVEL_LOW      = 15'd4096;   // Release write urgent.

    localparam logic [15:0] RD_LEVEL_URGENT   = 16'd4096;   // Refill reads urgently.
    localparam logic [15:0] RD_LEVEL_HIGH     = 16'd6144;   // Stop read prefetch.
    
    localparam logic [15:0] RD_FIFO_DEPTH     = 16'd8192;

    localparam logic [8:0]  WR_BURST_NUM      = 9'd256;
    localparam logic [9:0]  RD_BURST_NUM      = 10'd512;

    localparam logic [10:0] WR_TAIL_AGE_LIMIT = 11'd1024;
    
    localparam logic [2:0]  APP_CMD_WRITE     = 3'b000;
    localparam logic [2:0]  APP_CMD_READ      = 3'b001;

    typedef enum logic [3:0] {
        RW_IDLE,      // Wait/blocked.
        RW_ARB,       // 2:1 write/read arbitration.
        RW_WRITE_REQ, // Native write beat.
        RW_READ_CMD,  // Native read command.
        RW_READ_DATA  // Native read data.
    } rw_state_t;

    typedef enum logic [1:0] {
        GRANT_NONE,
        GRANT_WRITE,
        GRANT_READ
    } grant_t;

    typedef struct packed {
        logic       valid;
        logic       urgent;
        logic [9:0] len;
    } rw_req_t;

    // CDC edge detect.
    (* ASYNC_REG = "true" *) logic make_data_on_rcom_cdc_to_d;
    (* ASYNC_REG = "true" *) logic make_data_on_dd;
    (* ASYNC_REG = "true" *) logic make_data_on_ddd;
    logic make_data_on_edge;

    always_ff @(posedge ui_clk) begin
        if (ui_clk_sync_rst) begin
            make_data_on_rcom_cdc_to_d <= '0;
            make_data_on_dd            <= '0;
            make_data_on_ddd           <= '0;
        end
        else begin
            make_data_on_rcom_cdc_to_d <= make_data_on;
            make_data_on_dd            <= make_data_on_rcom_cdc_to_d;
            make_data_on_ddd           <= make_data_on_dd;
        end
    end

    assign make_data_on_edge        = make_data_on_dd & (~make_data_on_ddd);
    assign make_data_p_edge_ddr_clk = make_data_on_edge;

    // Replay settle window.
    logic [7:0] rp_back_en_dly_cnt;
    logic       block_for_replay;

    always_ff @(posedge ui_clk) begin
        if (ui_clk_sync_rst) begin
            rp_back_en_dly_cnt <= '0;
        end
        else if (rp_back_en) begin
            rp_back_en_dly_cnt <= 8'd1;
        end
        else if (rp_back_en_dly_cnt != 8'd0) begin
            rp_back_en_dly_cnt <= rp_back_en_dly_cnt + 8'd1;
        end
    end

    assign block_for_replay = rp_back_en || (rp_back_en_dly_cnt != 8'd0);

    // write requestion generation
    logic        ddr_wr_req;
    logic        clr_wr_wait_age;
    logic        wr_has_full_burst;
    logic [10:0] wr_tail_age_cnt;
    logic        wr_tail_age_reached;

    // Partial-write tail aging.
    always_ff @(posedge ui_clk) begin
        if (ui_clk_sync_rst) begin
            wr_tail_age_cnt <= '0;
        end
        else if (clr_wr_wait_age || (~wr_fifo_valid)) begin
            wr_tail_age_cnt <= '0;
        end
        else if (wr_tail_age_cnt < WR_TAIL_AGE_LIMIT) begin
            wr_tail_age_cnt <= wr_tail_age_cnt + 11'd1;
        end
    end

    assign wr_has_full_burst  = ~wr_fifo_prog_empty;
    assign wr_tail_age_reached = (wr_tail_age_cnt >= WR_TAIL_AGE_LIMIT);
    assign ddr_wr_req = wr_fifo_valid & (wr_has_full_burst | wr_tail_age_reached);

    // read request generation
    logic        ddr_rd_req_d;
    logic        ddr_rd_req_dd;
    logic        ddr_rd_req_qual;

    // Read request sync.
    always_ff @(posedge ui_clk) begin
        if (ui_clk_sync_rst || rst_local_t_ddr_clk) begin
            ddr_rd_req_d  <= '0;
            ddr_rd_req_dd <= '0;
        end
        else begin
            ddr_rd_req_d  <= ddr_rd_req;
            ddr_rd_req_dd <= ddr_rd_req_d;
        end
    end

    logic  rd_fifo_can_prefetch;
    assign rd_fifo_can_prefetch = (~rd_fifo_prog_full) &
                                (~rd_fifo_full) &
                                (rd_fifo_data_count < RD_LEVEL_HIGH);
    assign ddr_rd_req_qual = (~ddr_rd_empty) & ddr_rd_req_dd & rd_fifo_can_prefetch;

    // FIFO pressure watermarks.
    logic        pressure_rst;
    logic        pressure_clear;

    assign pressure_rst       = ui_clk_sync_rst | rst_local_t_ddr_clk;
    assign pressure_clear     = make_data_on_edge | rp_back_en;

    logic        wr_level_urgent;
    logic        rd_level_urgent;

    // FIFO pressure control.
    rw_pressure_ctrl #(
        .WR_LEVEL_URGENT   (WR_LEVEL_URGENT),
        .WR_LEVEL_LOW      (WR_LEVEL_LOW),
        .RD_LEVEL_URGENT   (RD_LEVEL_URGENT),
        .RD_LEVEL_HIGH     (RD_LEVEL_HIGH)
    ) pressure_ctrl_u (
        .i_ui_clk                 (ui_clk),
        .i_pressure_rst           (pressure_rst),
        .i_pressure_clear         (pressure_clear),
        .i_wr_fifo_rd_data_count  (wr_fifo_rd_data_count),
        .i_rd_fifo_almost_empty   (rd_fifo_almost_empty),
        .i_rd_fifo_data_count     (rd_fifo_data_count),
        .o_wr_level_urgent        (wr_level_urgent),
        .o_rd_level_urgent        (rd_level_urgent)
    );

    // Burst length calculation.
    logic [9:0] wr_req_len_calc;
    logic [9:0] rd_req_len_calc;
    logic [ADDR_WIDTH:0] ddr_cache_data_count;
    logic [9:0] rd_available_len;

    assign rd_available_len = (ddr_cache_data_count >= RD_BURST_NUM) ?
                              RD_BURST_NUM : ddr_cache_data_count[9:0];
    assign wr_req_len_calc = {1'b0, fifo_count_to_burst_len(wr_fifo_rd_data_count,
                                                            wr_fifo_valid)};
    assign rd_req_len_calc = min2_10(rd_available_len, RD_BURST_NUM);

    // Request descriptors.
    rw_req_t    wr_req;
    rw_req_t    rd_req;

    logic [16:0] rd_fifo_free_count;
    logic        rd_fifo_has_grant_space;

    assign rd_fifo_free_count  = {1'b0, RD_FIFO_DEPTH} -
                                 {1'b0, rd_fifo_data_count};
    assign rd_fifo_has_grant_space = rd_fifo_free_count >= RD_BURST_NUM;

    assign wr_req.valid  = ddr_wr_req;
    assign wr_req.urgent = wr_req.valid && wr_level_urgent;
    assign wr_req.len    = wr_req_len_calc;

    assign rd_req.len    = rd_req_len_calc;
    assign rd_req.valid  = ddr_rd_req_qual &&
                            rd_fifo_has_grant_space &&
                            (~wr_level_urgent);
    assign rd_req.urgent = rd_req.valid && rd_level_urgent;

    // Read/write arbitration.
    rw_state_t  rw_state;
    rw_state_t  rw_next_state;

    logic [1:0] arb_grant_raw;
    grant_t     arb_grant;

    logic       arbiter_rst;
    logic       arbiter_clear;

    assign arb_grant = grant_t'(arb_grant_raw);
    assign arbiter_rst   = ui_clk_sync_rst | rst_local_t_ddr_clk;
    assign arbiter_clear = make_data_on_edge;

    rw_arbiter arbiter_u (
        .i_ui_clk             (ui_clk),
        .i_arbiter_rst        (arbiter_rst),
        .i_arbiter_clear      (arbiter_clear),
        .i_in_arb             (rw_state == RW_ARB),
        .i_wr_req_valid       (wr_req.valid),
        .i_rd_req_valid       (rd_req.valid),
        .i_wr_req_urgent      (wr_req.urgent),
        .i_rd_req_urgent      (rd_req.urgent),
        .o_arb_grant          (arb_grant_raw)
    );

    logic [8:0] write_burst_len;
    logic [9:0] read_burst_len;
    logic [8:0] write_beat_cnt;
    logic [9:0] read_beat_cnt;
    logic       write_burst_done;
    logic       read_burst_done;

    logic       app_cmd_fire;
    logic       read_cmd_fire;
    logic       write_data_fire;
    logic       read_data_fire;
    logic       write_channel_ready;
    logic       read_cmd_send_en;
    logic       read_cmd_last;
    logic       read_cmd_send_done;
    logic       read_cmd_stop;
    logic       read_cmd_stop_event;
    logic       rd_outstanding_empty_next;
    logic [9:0] read_cmd_cnt;
    logic [9:0] rd_outstanding;

    // FSM state register.
    always_ff @(posedge ui_clk) begin
        if (ui_clk_sync_rst || rst_local_t_ddr_clk || make_data_on_edge) begin
            rw_state <= RW_IDLE;
        end
        else begin
            rw_state <= rw_next_state;
        end
    end

    // FSM next-state logic.
    always_comb begin
        rw_next_state = rw_state;

        if (~init_calib_complete) begin
            rw_next_state = RW_IDLE;
        end
        else begin
            unique case (rw_state)
                RW_IDLE: begin
                    rw_next_state = block_for_replay ? RW_IDLE : RW_ARB;
                end

                RW_ARB: begin
                    if (block_for_replay) begin
                        rw_next_state = RW_IDLE;
                    end
                    else begin
                        unique case (arb_grant)
                            GRANT_WRITE: begin
                                rw_next_state = RW_WRITE_REQ;
                            end

                            GRANT_READ: begin
                                rw_next_state = RW_READ_CMD;
                            end

                            default: begin
                                rw_next_state = RW_IDLE;
                            end
                        endcase
                    end
                end

                RW_WRITE_REQ: begin
                    if (write_burst_len == 0) begin
                        rw_next_state = RW_ARB;
                    end
                    else if (~wr_fifo_valid) begin
                        rw_next_state = RW_ARB;
                    end
                    else if (write_burst_done) begin
                        rw_next_state = RW_ARB;
                    end
                end

                RW_READ_CMD: begin
                    if (read_cmd_send_en) begin
                        if (read_cmd_last) begin
                            rw_next_state = RW_READ_DATA;
                        end
                        else begin
                            rw_next_state = RW_READ_CMD;
                        end
                    end
                    else if (read_cmd_stop) begin
                        rw_next_state = (rd_outstanding == 0) ? RW_ARB : RW_READ_DATA;
                    end
                end

                RW_READ_DATA: begin
                    if (rd_outstanding_empty_next) begin
                        rw_next_state = RW_ARB;
                    end
                end

                default: begin
                    rw_next_state = RW_IDLE;
                end
            endcase
        end
    end

    // FSM output logic.
    always_comb begin
        clr_wr_wait_age = init_calib_complete && (rw_state == RW_WRITE_REQ);
    end

    // Circular DDR address signals.
    logic [ADDR_WIDTH:0]   ddr_cache_wr_ptr;
    logic [ADDR_WIDTH:0]   ddr_cache_rd_ptr;
    logic [ADDR_WIDTH:0]   ddr_cache_rd_cmd_ptr;
    logic [ADDR_WIDTH-1:0] ddr_cache_wr_addr;
    logic                  ring_addr_rst;
    logic                  ring_addr_clear;

    assign ring_addr_rst   = ui_clk_sync_rst | rst_local_t_ddr_clk;
    assign ring_addr_clear = make_data_on_edge | (~init_calib_complete);

    // Circular DDR address manager.
    ddr_ring_addr_mgr #(
        .ADDR_WIDTH (ADDR_WIDTH)
    ) ring_addr_mgr_u (
        .i_ui_clk                    (ui_clk),
        .i_ring_addr_rst             (ring_addr_rst),
        .i_ring_addr_clear           (ring_addr_clear),
        .i_fault_ddr_overrun         (fault_ddr_overrun),
        .i_fault_ddr_warning         (fault_ddr_warning),
        .i_wr_fire                   (write_data_fire),
        .i_rd_fire                   (read_data_fire),
        .i_rd_cmd_fire               (read_cmd_fire),
        .i_replay_en                 (rp_back_en),
        .i_replay_addr               (rp_back_view_addr),
        .o_wr_ptr                    (ddr_cache_wr_ptr),
        .o_rd_ptr                    (ddr_cache_rd_ptr),
        .o_rd_cmd_ptr                (ddr_cache_rd_cmd_ptr),
        .o_wr_addr                   (ddr_cache_wr_addr),
        .o_empty                     (ddr_rd_empty),
        .o_data_count                (ddr_cache_data_count),
        .o_ddr_cache_overrun         (ddr_overrun),
        .o_ddr_cache_overrun_warning (ddr_warning)
    );

    // Burst progress tracking.
    always_ff @(posedge ui_clk) begin
        if (ui_clk_sync_rst || rst_local_t_ddr_clk || make_data_on_edge) begin
            write_burst_len <= '0;
        end
        else if (rw_state == RW_ARB) begin
            write_burst_len <= wr_req.len[8:0];
        end
    end

    always_ff @(posedge ui_clk) begin
        if (ui_clk_sync_rst || rst_local_t_ddr_clk || make_data_on_edge) begin
            read_burst_len <= '0;
        end
        else if (rw_state == RW_ARB) begin
            read_burst_len <= rd_req.len;
        end
    end

    always_ff @(posedge ui_clk) begin
        if (ui_clk_sync_rst || rst_local_t_ddr_clk || make_data_on_edge) begin
            write_beat_cnt <= '0;
        end
        else if (rw_state != RW_WRITE_REQ) begin
            write_beat_cnt <= '0;
        end
        else if (write_data_fire) begin
            write_beat_cnt <= write_beat_cnt + 1'b1;
        end
    end

    always_ff @(posedge ui_clk) begin
        if (ui_clk_sync_rst || rst_local_t_ddr_clk || make_data_on_edge) begin
            read_beat_cnt <= '0;
        end
        else if ((rw_state != RW_READ_CMD) && (rw_state != RW_READ_DATA)) begin
            read_beat_cnt <= '0;
        end
        else if (read_data_fire) begin
            read_beat_cnt <= read_beat_cnt + 1'b1;
        end
    end

    assign write_burst_done = write_data_fire &&
                              (write_beat_cnt == (write_burst_len - 1'b1));
    assign read_burst_done  = read_data_fire &&
                              (read_beat_cnt == (read_burst_len - 1'b1));
    
    // Handshake and service conditions.
    assign app_cmd_fire        = app_en && app_rdy;
    assign read_cmd_fire       = (rw_state == RW_READ_CMD) && app_cmd_fire;
    assign write_channel_ready = app_rdy && app_wdf_rdy;
    assign write_data_fire     = (rw_state == RW_WRITE_REQ) &&
                                 wr_fifo_valid &&
                                 (write_burst_len != 0) &&
                                 (write_beat_cnt < write_burst_len) &&
                                 write_channel_ready;
    assign read_data_fire      = app_rd_data_valid && (~rd_fifo_full) &&
                                 (rd_outstanding != 0);
    assign read_cmd_send_en    = (rw_state == RW_READ_CMD) &&
                                 (read_burst_len != 0) &&
                                 (read_cmd_cnt < read_burst_len) &&
                                 (ddr_cache_rd_cmd_ptr != ddr_cache_wr_ptr) &&
                                 (rd_fifo_free_count > {7'd0, rd_outstanding}) &&
                                 (~wr_level_urgent) &&
                                 (~req_stop) &&
                                 (~block_for_replay);
    assign read_cmd_last       = read_cmd_fire &&
                                 (read_cmd_cnt == (read_burst_len - 1'b1));
    assign read_cmd_send_done  = (read_cmd_cnt >= read_burst_len) || read_cmd_last;
    assign read_cmd_stop       = (read_burst_len == 0) ||
                                 read_cmd_send_done ||
                                 (ddr_cache_rd_cmd_ptr == ddr_cache_wr_ptr) ||
                                 (rd_fifo_free_count <= {7'd0, rd_outstanding}) ||
                                 wr_level_urgent ||
                                 req_stop ||
                                 block_for_replay;
    assign read_cmd_stop_event = (rw_state == RW_READ_CMD) &&
                                 (read_cmd_cnt < read_burst_len) &&
                                 ((rd_fifo_free_count <= {7'd0, rd_outstanding}) ||
                                  wr_level_urgent || req_stop || block_for_replay);
    
    always_ff @(posedge ui_clk) begin
        if (ui_clk_sync_rst || rst_local_t_ddr_clk || make_data_on_edge ||
            rp_back_en || block_for_replay) begin
            read_cmd_cnt <= '0;
        end
        else if ((rw_state != RW_READ_CMD) && (rw_state != RW_READ_DATA)) begin
            read_cmd_cnt <= '0;
        end
        else if (read_cmd_fire) begin
            read_cmd_cnt <= read_cmd_cnt + 1'b1;
        end
    end

    always_ff @(posedge ui_clk) begin
        if (ui_clk_sync_rst || rst_local_t_ddr_clk || make_data_on_edge ||
            rp_back_en || block_for_replay) begin
            rd_outstanding <= '0;
        end
        else begin
            unique case ({read_cmd_fire, read_data_fire})
                2'b10: rd_outstanding <= rd_outstanding + 1'b1;
                2'b01: rd_outstanding <= (rd_outstanding == 0) ? '0 :
                                          (rd_outstanding - 1'b1);
                default: rd_outstanding <= rd_outstanding;
            endcase
        end
    end
    
    assign rd_outstanding_empty_next = (rd_outstanding == 0) ||
                                        ((rd_outstanding == 10'd1) && read_data_fire && (!read_cmd_fire));
    
    // Native app channel drive.
    assign wr_fifo_rd_en = write_data_fire;
    assign app_addr      = (rw_state == RW_READ_CMD) ?
                           beat_to_app_addr(ddr_cache_rd_cmd_ptr[ADDR_WIDTH-1:0]) :
                           beat_to_app_addr(ddr_cache_wr_addr);
    assign app_cmd       = (rw_state == RW_READ_CMD) ? APP_CMD_READ : APP_CMD_WRITE;
    assign app_en        = write_data_fire || read_cmd_send_en;
    assign app_wdf_data  = wr_fifo_dout;
    assign app_wdf_mask  = 16'h0000;
    assign app_wdf_wren  = write_data_fire;
    assign app_wdf_end   = app_wdf_wren;
    assign rd_fifo_din   = app_rd_data;
    assign rd_fifo_wr_en = read_data_fire;

    // Helper functions.
    function automatic logic [APP_ADDR_WIDTH-1:0] beat_to_app_addr(
        input logic [ADDR_WIDTH-1:0] beat_addr
    );
        // Beat to x16-word address.
        beat_to_app_addr = ({ {(APP_ADDR_WIDTH-ADDR_WIDTH){1'b0}}, beat_addr } << 3);
    endfunction

    function automatic logic [8:0] fifo_count_to_burst_len(
        input logic [14:0] fifo_count,
        input logic        fifo_valid
    );
        if (fifo_count >= WR_BURST_NUM) begin
            fifo_count_to_burst_len = WR_BURST_NUM;
        end
        else if (fifo_count != 0) begin
            fifo_count_to_burst_len = {1'b0, fifo_count[7:0]};
        end
        else if (fifo_valid) begin
            fifo_count_to_burst_len = 9'd1;
        end
        else begin
            fifo_count_to_burst_len = '0;
        end
    endfunction

    function automatic logic [9:0] min2_10(
        input logic [9:0] a,
        input logic [9:0] b
    );
        min2_10 = (a < b) ? a : b;
    endfunction

    // Debug-only ILA counters.
    localparam int DBG_CNT_WIDTH = 32;

    logic dbg_cnt_reset;
    (* mark_debug = "true" *) logic dbg_wr_no_service;
    (* mark_debug = "true" *) logic dbg_rd_no_service;
    (* mark_debug = "true" *) logic dbg_replay_block;
    (* mark_debug = "true" *) logic dbg_wr_app_rdy_wait;
    (* mark_debug = "true" *) logic dbg_wr_wdf_rdy_wait;
    (* mark_debug = "true" *) logic dbg_rd_cmd_wait;
    (* mark_debug = "true" *) logic dbg_rd_data_wait;

    (* mark_debug = "true" *) logic [DBG_CNT_WIDTH-1:0] dbg_wr_no_service_cur;
    (* mark_debug = "true" *) logic [DBG_CNT_WIDTH-1:0] dbg_wr_no_service_max;
    (* mark_debug = "true" *) logic [DBG_CNT_WIDTH-1:0] dbg_rd_no_service_cur;
    (* mark_debug = "true" *) logic [DBG_CNT_WIDTH-1:0] dbg_rd_no_service_max;
    (* mark_debug = "true" *) logic [DBG_CNT_WIDTH-1:0] dbg_replay_block_cur;
    (* mark_debug = "true" *) logic [DBG_CNT_WIDTH-1:0] dbg_replay_block_max;
    (* mark_debug = "true" *) logic [DBG_CNT_WIDTH-1:0] dbg_wr_app_rdy_wait_cur;
    (* mark_debug = "true" *) logic [DBG_CNT_WIDTH-1:0] dbg_wr_app_rdy_wait_max;
    (* mark_debug = "true" *) logic [DBG_CNT_WIDTH-1:0] dbg_wr_wdf_rdy_wait_cur;
    (* mark_debug = "true" *) logic [DBG_CNT_WIDTH-1:0] dbg_wr_wdf_rdy_wait_max;
    (* mark_debug = "true" *) logic [DBG_CNT_WIDTH-1:0] dbg_rd_cmd_wait_cur;
    (* mark_debug = "true" *) logic [DBG_CNT_WIDTH-1:0] dbg_rd_cmd_wait_max;
    (* mark_debug = "true" *) logic [DBG_CNT_WIDTH-1:0] dbg_rd_data_wait_cur;
    (* mark_debug = "true" *) logic [DBG_CNT_WIDTH-1:0] dbg_rd_data_wait_max;

    assign dbg_cnt_reset = ui_clk_sync_rst || rst_local_t_ddr_clk ||
                           make_data_on_edge || (~init_calib_complete);

    rw_cmd_debug_monitor #(
        .DBG_CNT_WIDTH      (DBG_CNT_WIDTH),
        .PERF_COUNTER_WIDTH (48),
        .PERF_WINDOW_CYCLES (139200)
    ) debug_monitor_u (
        .ui_clk                      (ui_clk),
        .rst                         (dbg_cnt_reset),
        .ddr_wr_req                  (ddr_wr_req),
        .ddr_rd_req_qual             (ddr_rd_req_qual),
        .write_data_fire             (write_data_fire),
        .read_cmd_fire               (read_cmd_fire),
        .read_data_fire              (read_data_fire),
        .block_for_replay            (block_for_replay),
        .in_idle                     (rw_state == RW_IDLE),
        .in_arb                      (rw_state == RW_ARB),
        .in_write_req                (rw_state == RW_WRITE_REQ),
        .in_read_cmd                 (rw_state == RW_READ_CMD),
        .in_read_data                (rw_state == RW_READ_DATA),
        .grant_write                 (arb_grant == GRANT_WRITE),
        .grant_read                  (arb_grant == GRANT_READ),
        .wr_fifo_valid               (wr_fifo_valid),
        .write_burst_len             (write_burst_len),
        .read_burst_len              (read_burst_len),
        .read_cmd_send_en            (read_cmd_send_en),
        .app_rdy                     (app_rdy),
        .app_wdf_rdy                 (app_wdf_rdy),
        .app_rd_data_valid           (app_rd_data_valid),
        .rd_fifo_full                (rd_fifo_full),
        .rd_fifo_has_grant_space     (rd_fifo_has_grant_space),
        .wr_level_urgent             (wr_level_urgent),
        .rd_level_urgent             (rd_level_urgent),
        .req_stop                    (req_stop),
        .wr_fifo_full                (wr_fifo_full),
        .wr_fifo_data_count          (wr_fifo_rd_data_count),
        .rd_fifo_data_count          (rd_fifo_data_count),
        .write_burst_done            (write_burst_done),
        .read_burst_done             (read_burst_done),
        .read_cmd_stop_event         (read_cmd_stop_event),
        .rd_outstanding              (rd_outstanding),
        .dbg_wr_no_service           (dbg_wr_no_service),
        .dbg_rd_no_service           (dbg_rd_no_service),
        .dbg_replay_block            (dbg_replay_block),
        .dbg_wr_app_rdy_wait         (dbg_wr_app_rdy_wait),
        .dbg_wr_wdf_rdy_wait         (dbg_wr_wdf_rdy_wait),
        .dbg_rd_cmd_wait             (dbg_rd_cmd_wait),
        .dbg_rd_data_wait            (dbg_rd_data_wait),
        .dbg_wr_no_service_cur       (dbg_wr_no_service_cur),
        .dbg_wr_no_service_max       (dbg_wr_no_service_max),
        .dbg_rd_no_service_cur       (dbg_rd_no_service_cur),
        .dbg_rd_no_service_max       (dbg_rd_no_service_max),
        .dbg_replay_block_cur        (dbg_replay_block_cur),
        .dbg_replay_block_max        (dbg_replay_block_max),
        .dbg_wr_app_rdy_wait_cur     (dbg_wr_app_rdy_wait_cur),
        .dbg_wr_app_rdy_wait_max     (dbg_wr_app_rdy_wait_max),
        .dbg_wr_wdf_rdy_wait_cur     (dbg_wr_wdf_rdy_wait_cur),
        .dbg_wr_wdf_rdy_wait_max     (dbg_wr_wdf_rdy_wait_max),
        .dbg_rd_cmd_wait_cur         (dbg_rd_cmd_wait_cur),
        .dbg_rd_cmd_wait_max         (dbg_rd_cmd_wait_max),
        .dbg_rd_data_wait_cur        (dbg_rd_data_wait_cur),
        .dbg_rd_data_wait_max        (dbg_rd_data_wait_max)
    );

endmodule
