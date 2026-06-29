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
    input  logic                      wr_fifo_valid,
    input  logic                      wr_fifo_prog_empty,
    input  logic [13:0]               wr_fifo_rd_data_count,
    input  logic                      wr_fifo_overrun,
    input  logic [127:0]              wr_fifo_dout,
    input  logic                      rd_fifo_prog_full,
    input  logic                      rd_fifo_almost_empty,
    input  logic [13:0]               rd_fifo_data_count,
    input  logic                      rd_fifo_full,
    input  logic                      rp_back_en,
    input  logic [ADDR_WIDTH-1:0]     rp_back_view_addr
);

    // Watermark thresholds.
    localparam logic [13:0] WR_LEVEL_URGENT   = 14'd2560;   // Force writes, block reads.

    localparam logic [13:0] RD_LEVEL_URGENT   = 14'd1024;   // Refill reads urgently.
    localparam logic [13:0] RD_LEVEL_HIGH     = 14'd3072;   // Stop read prefetch.
    
    localparam logic [13:0] RD_FIFO_DEPTH     = 14'd4095;

    localparam logic [8:0]  WR_BURST_NUM      = 9'd256;
    localparam logic [9:0]  RD_BURST_NUM      = 10'd512;

    localparam logic [10:0] WR_TAIL_AGE_LIMIT = 11'd1024;
    localparam logic [11:0] RD_WAIT_AGE_LIMIT = 12'd2048;

    localparam logic [2:0]  APP_CMD_WRITE     = 3'b000;
    localparam logic [2:0]  APP_CMD_READ      = 3'b001;

    typedef enum logic [3:0] {
        RW_IDLE,      // Wait/blocked.
        RW_ARB,       // Fixed-priority arbitration with read aging.
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

    // Start pulse CDC and edge detect.
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

    assign make_data_on_edge         = make_data_on_dd & (~make_data_on_ddd);
    assign make_data_p_edge_ddr_clk  = make_data_on_edge;

    // Replay settle delay.
    logic [7:0] rp_back_en_dly_cnt;

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

    logic [10:0] wr_tail_age_cnt;
    logic        wr_tail_age_reached;
    logic        clr_wr_wait_age;
    logic        clr_rd_wait_age;

    assign wr_tail_age_reached = (wr_tail_age_cnt >= WR_TAIL_AGE_LIMIT);

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

    // FIFO pressure flags.
    logic        wr_level_urgent;
    logic        wr_has_full_burst;
    logic        rd_level_urgent;
    logic        rd_fifo_can_prefetch;
    logic [14:0] rd_fifo_free_count;

    assign wr_level_urgent       = wr_fifo_rd_data_count >= WR_LEVEL_URGENT;
    assign wr_has_full_burst     = ~wr_fifo_prog_empty;                       // wr_fifo has WR_BURST_NUM beats.
    
    assign rd_level_urgent       = rd_fifo_almost_empty | (rd_fifo_data_count <= RD_LEVEL_URGENT);
    assign rd_fifo_free_count    = {1'b0, RD_FIFO_DEPTH} - {1'b0, rd_fifo_data_count};         // Free read FIFO slots.
    assign rd_fifo_can_prefetch  = (~rd_fifo_prog_full) & (~rd_fifo_full) & (rd_fifo_data_count < RD_LEVEL_HIGH); // Allow read prefetch.

    // Request gating.
    logic ddr_wr_req;
    logic ddr_rd_req_d;
    logic ddr_rd_req_dd;
    logic ddr_rd_req_qual;

    // Full burst or aged partial tail.
    assign ddr_wr_req = wr_fifo_valid & (wr_has_full_burst | wr_tail_age_reached);

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

    assign ddr_rd_req_qual = (~ddr_rd_empty) & ddr_rd_req_dd & rd_fifo_can_prefetch;

    // Burst/service tracking.
    // Selected service length for the active native service, in 128-bit beats.
    logic [8:0] write_burst_len;
    logic [9:0] read_burst_len;
    // Completed beat count within the active service; done fires on len - 1.
    logic [8:0] write_beat_cnt;
    logic [9:0] read_beat_cnt;
    logic       write_burst_done;
    logic       read_burst_done;

    logic [9:0] rd_available_len;
    logic [ADDR_WIDTH:0] ddr_rd_avail_count;

    logic       app_cmd_fire;
    logic       read_cmd_fire;
    logic       write_data_fire;
    logic       read_data_fire;
    logic       write_channel_ready;
    logic       block_for_replay;
    logic       rd_fifo_has_grant_space;
    logic       read_cmd_send_en;
    logic       read_cmd_last;
    logic       read_cmd_send_done;
    logic       read_cmd_stop;
    logic       rd_outstanding_empty_next;
    logic [9:0] read_cmd_cnt;
    logic [9:0] rd_outstanding;

    // Keep the read service window fixed; FIFO space is only a hard gate.
    assign rd_available_len = (ddr_rd_avail_count >= RD_BURST_NUM) ?
                              RD_BURST_NUM : ddr_rd_avail_count[9:0];
    assign rd_fifo_has_grant_space = rd_fifo_free_count >= RD_BURST_NUM;
    // Replay blocks arbitration.
    assign block_for_replay = rp_back_en || (rp_back_en_dly_cnt != 8'd0);

    // Request descriptors and grant selection.
    rw_req_t wr_req;
    rw_req_t rd_req;

    grant_t arb_grant;
    logic [11:0] rd_wait_age_cnt;
    logic        rd_wait_age_reached;

    assign rd_wait_age_reached = (rd_wait_age_cnt >= RD_WAIT_AGE_LIMIT);

    always_ff @(posedge ui_clk) begin
        if (ui_clk_sync_rst || rst_local_t_ddr_clk || make_data_on_edge) begin
            rd_wait_age_cnt <= '0;
        end
        else if (clr_rd_wait_age || read_data_fire || (~ddr_rd_req_qual)) begin
            rd_wait_age_cnt <= '0;
        end
        else if (rd_wait_age_cnt < RD_WAIT_AGE_LIMIT) begin
            rd_wait_age_cnt <= rd_wait_age_cnt + 12'd1;
        end
    end

    assign wr_req = build_write_req(ddr_wr_req,
                                    wr_level_urgent,
                                    fifo_count_to_burst_len(wr_fifo_rd_data_count,
                                                            wr_fifo_valid));
    assign rd_req = build_read_req(ddr_rd_req_qual,
                                   rd_fifo_has_grant_space,
                                   wr_level_urgent,
                                   rd_level_urgent,
                                   min2_10(rd_available_len,
                                           RD_BURST_NUM));
    assign arb_grant = choose_grant(wr_req, rd_req, rd_wait_age_reached);

    // RW arbitration FSM.
    rw_state_t rw_state;
    rw_state_t rw_next_state;

    always_ff @(posedge ui_clk) begin
        if (ui_clk_sync_rst || rst_local_t_ddr_clk || make_data_on_edge) begin
            rw_state <= RW_IDLE;
        end
        else begin
            rw_state <= rw_next_state;
        end
    end

    // Arbitration priority: write urgent, read urgent, aged read, normal write, normal read.
    always_comb begin
        rw_next_state      = rw_state;
        clr_wr_wait_age    = 1'b0;
        clr_rd_wait_age    = 1'b0;

        if (~init_calib_complete) begin
            rw_next_state = RW_IDLE;
        end
        else begin
            unique case (rw_state)
                RW_IDLE: begin
                    rw_next_state = block_for_replay ? RW_IDLE : RW_ARB;
                end

                RW_ARB: begin
                    // Replay has priority.
                    if (block_for_replay) begin
                        rw_next_state = RW_IDLE;
                    end
                    else begin
                        unique case (arb_grant)
                            GRANT_WRITE: begin
                                rw_next_state = RW_WRITE_REQ;
                            end

                            GRANT_READ: begin
                                rw_next_state   = RW_READ_CMD;
                                clr_rd_wait_age = 1'b1;
                            end

                            default: begin
                                rw_next_state = RW_IDLE;
                            end
                        endcase
                    end
                end

                RW_WRITE_REQ: begin
                    clr_wr_wait_age = 1'b1;
                    if (write_burst_len == 0) begin
                        rw_next_state = RW_ARB;
                    end
                    else if (~wr_fifo_valid) begin
                        rw_next_state = RW_ARB;
                    end
                    // Native write command/data handshake.
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
                    // Accepted reads must drain even if writes become urgent.
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

    // Circular DDR address pointers.
    logic [ADDR_WIDTH:0]   user_ad_wr_i;
    logic [ADDR_WIDTH:0]   user_ad_rd_i;
    logic [ADDR_WIDTH:0]   rd_cmd_ptr;
    logic [ADDR_WIDTH-1:0] user_ad_wr;
    logic [ADDR_WIDTH-1:0] user_ad_rd;

    assign user_ad_wr               = user_ad_wr_i[ADDR_WIDTH-1:0];
    assign user_ad_rd               = user_ad_rd_i[ADDR_WIDTH-1:0];
    assign ddr_rd_empty             = (user_ad_wr_i == user_ad_rd_i);
    assign ddr_rd_avail_count       = user_ad_wr_i - user_ad_rd_i;

    // Handshake pulses.
    assign app_cmd_fire        = app_en && app_rdy;
    assign read_cmd_fire       = (rw_state == RW_READ_CMD) && app_cmd_fire;
    assign write_channel_ready = app_rdy && app_wdf_rdy;
    assign write_data_fire     = (rw_state == RW_WRITE_REQ) &&
                                wr_fifo_valid &&
                                (write_burst_len != 0) &&
                                (write_beat_cnt < write_burst_len) &&
                                write_channel_ready;
    assign read_data_fire      = app_rd_data_valid && (~rd_fifo_full) && (rd_outstanding != 0);
    assign read_cmd_send_en    = (rw_state == RW_READ_CMD) &&
                                (read_burst_len != 0) &&
                                (read_cmd_cnt < read_burst_len) &&
                                (rd_cmd_ptr != user_ad_wr_i) &&
                                (rd_fifo_free_count > {5'd0, rd_outstanding}) &&
                                (~wr_level_urgent) &&
                                (~req_stop) &&
                                (~block_for_replay);
    assign read_cmd_last       = read_cmd_fire &&
                                 (read_cmd_cnt == (read_burst_len - 1'b1));
    assign read_cmd_send_done  = (read_cmd_cnt >= read_burst_len) || read_cmd_last;
    assign read_cmd_stop       = (read_burst_len == 0) ||
                                 read_cmd_send_done ||
                                 (rd_cmd_ptr == user_ad_wr_i) ||
                                 (rd_fifo_free_count <= {5'd0, rd_outstanding}) ||
                                 wr_level_urgent ||
                                 req_stop ||
                                 block_for_replay;
    assign rd_outstanding_empty_next =
        (rd_outstanding == 0) ||
        ((rd_outstanding == 10'd1) && read_data_fire && (!read_cmd_fire));

    always_ff @(posedge ui_clk) begin
        if (ui_clk_sync_rst || rst_local_t_ddr_clk || make_data_on_edge) begin
            user_ad_wr_i <= '0;
        end
        else if (write_data_fire) begin
            user_ad_wr_i <= user_ad_wr_i + 1'b1;
        end
    end

    always_ff @(posedge ui_clk) begin
        if (ui_clk_sync_rst || rst_local_t_ddr_clk || make_data_on_edge) begin
            user_ad_rd_i <= '0;
        end
        // Returned-data pointer. Keep user_ad_rd_i as the consumed boundary.
        else if (rp_back_en) begin
            user_ad_rd_i <= {1'b0, rp_back_view_addr};
        end
        else if (read_data_fire) begin
            user_ad_rd_i <= user_ad_rd_i + 1'b1;
        end
    end

    always_ff @(posedge ui_clk) begin
        if (ui_clk_sync_rst || rst_local_t_ddr_clk || make_data_on_edge) begin
            rd_cmd_ptr <= '0;
        end
        else if (rp_back_en) begin
            rd_cmd_ptr <= {1'b0, rp_back_view_addr};
        end
        else if (read_cmd_fire) begin
            rd_cmd_ptr <= rd_cmd_ptr + 1'b1;
        end
    end

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

    assign write_burst_done = write_data_fire && (write_beat_cnt == (write_burst_len - 1'b1));
    assign read_burst_done  = read_data_fire && (read_beat_cnt == (read_burst_len - 1'b1));

    assign wr_fifo_rd_en = write_data_fire;

    // Native app channel drive.

    assign app_addr     = (rw_state == RW_READ_CMD) ?
                            beat_to_app_addr(rd_cmd_ptr[ADDR_WIDTH-1:0]) :
                            beat_to_app_addr(user_ad_wr);
    assign app_cmd      = (rw_state == RW_READ_CMD) ? APP_CMD_READ : APP_CMD_WRITE;
    assign app_en       = write_data_fire || read_cmd_send_en;

    assign app_wdf_data = wr_fifo_dout;
    assign app_wdf_mask = 16'h0000;
    assign app_wdf_wren = write_data_fire;
    assign app_wdf_end  = app_wdf_wren;

    assign rd_fifo_din   = app_rd_data;
    assign rd_fifo_wr_en = read_data_fire;

    // Circular-buffer warning/overrun.
    logic [ADDR_WIDTH:0] wr_sub_rd;
    logic [ADDR_WIDTH:0] wr_sub_rd_diff;
    logic                wr_rd_same_signal;
    logic                wr_rd_diff_signal;
    logic                set_ddr_overrun;

    assign wr_rd_same_signal = (user_ad_wr_i[ADDR_WIDTH] == user_ad_rd_i[ADDR_WIDTH]);
    assign wr_rd_diff_signal = (user_ad_wr_i[ADDR_WIDTH] ^ user_ad_rd_i[ADDR_WIDTH]);
    assign set_ddr_overrun   = wr_rd_diff_signal &
                                (user_ad_wr_i[ADDR_WIDTH-1:0] == user_ad_rd_i[ADDR_WIDTH-1:0]);

    always_ff @(posedge ui_clk) begin
        if (ui_clk_sync_rst) begin
            ddr_overrun <= '0;
        end
        else if (rst_local_t_ddr_clk || (~init_calib_complete) || make_data_on_edge) begin
            ddr_overrun <= '0;
        end
        else if (fault_ddr_overrun || set_ddr_overrun) begin
            ddr_overrun <= 1'b1;
        end
        else begin
            ddr_overrun <= '0;
        end
    end

    assign wr_sub_rd      = {1'b0, user_ad_wr_i[ADDR_WIDTH-1:0]} -
                            {1'b0, user_ad_rd_i[ADDR_WIDTH-1:0]};
    assign wr_sub_rd_diff = {1'b1, user_ad_wr_i[ADDR_WIDTH-1:0]} -
                            {1'b0, user_ad_rd_i[ADDR_WIDTH-1:0]};

    always_ff @(posedge ui_clk) begin
        if (ui_clk_sync_rst) begin
            ddr_warning <= '0;
        end
        else if (rst_local_t_ddr_clk || (~init_calib_complete) || make_data_on_edge) begin
            ddr_warning <= '0;
        end
        else if (fault_ddr_warning) begin
            ddr_warning <= 1'b1;
        end
        else if (wr_rd_same_signal && (|wr_sub_rd[ADDR_WIDTH:ADDR_WIDTH-2])) begin
            ddr_warning <= 1'b1;
        end
        else if (wr_rd_diff_signal && (|wr_sub_rd_diff[ADDR_WIDTH:ADDR_WIDTH-2])) begin
            ddr_warning <= 1'b1;
        end
        else begin
            ddr_warning <= '0;
        end
    end

    // Helper functions.
    function automatic logic [APP_ADDR_WIDTH-1:0] beat_to_app_addr(
        input logic [ADDR_WIDTH-1:0] beat_addr
    );
        // Beat to x16-word address.
        beat_to_app_addr = ({ {(APP_ADDR_WIDTH-ADDR_WIDTH){1'b0}}, beat_addr } << 3);
    endfunction

    function automatic logic [8:0] fifo_count_to_burst_len(
        input logic [13:0] fifo_count,
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

    function automatic rw_req_t build_write_req(
        input logic       raw_valid,
        input logic       level_urgent,
        input logic [8:0] burst_len
    );
        build_write_req.valid         = raw_valid;
        build_write_req.urgent        = raw_valid && level_urgent;
        build_write_req.len           = {1'b0, burst_len};
    endfunction

    function automatic rw_req_t build_read_req(
        input logic       raw_valid,
        input logic       has_grant_space,
        input logic       write_urgent,
        input logic       level_urgent,
        input logic [9:0] service_len
    );
        logic allowed;

        allowed = raw_valid && has_grant_space && (~write_urgent);
        build_read_req.valid         = allowed;
        build_read_req.urgent        = allowed && level_urgent;
        build_read_req.len           = service_len;
    endfunction

    function automatic grant_t choose_grant(
        input rw_req_t wr,
        input rw_req_t rd,
        input logic    rd_wait_aged
    );
        choose_grant = GRANT_NONE;

        if (wr.urgent) begin
            choose_grant = GRANT_WRITE;
        end
        else if (rd.urgent) begin
            choose_grant = GRANT_READ;
        end
        else if (rd.valid && rd_wait_aged) begin
            choose_grant = GRANT_READ;
        end
        else if (wr.valid) begin
            choose_grant = GRANT_WRITE;
        end
        else if (rd.valid) begin
            choose_grant = GRANT_READ;
        end
    endfunction

    // Debug-only ILA counters.
    // Keep this section at the end so release builds can remove/comment it as one block.
    localparam int DBG_CNT_WIDTH = 32;

    logic dbg_cnt_reset;
    logic dbg_wr_no_service;
    logic dbg_rd_no_service;
    logic dbg_replay_block;
    logic dbg_wr_app_rdy_wait;
    logic dbg_wr_wdf_rdy_wait;
    logic dbg_rd_cmd_wait;
    logic dbg_rd_data_wait;

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

    assign dbg_cnt_reset         = ui_clk_sync_rst || rst_local_t_ddr_clk ||
                                   make_data_on_edge || (~init_calib_complete);
    assign dbg_wr_no_service     = ddr_wr_req && (~write_data_fire);
    assign dbg_rd_no_service     = ddr_rd_req_qual && (~read_data_fire);
    assign dbg_replay_block      = block_for_replay;
    assign dbg_wr_app_rdy_wait   = (rw_state == RW_WRITE_REQ) &&
                                   wr_fifo_valid &&
                                   (write_burst_len != 0) &&
                                   app_wdf_rdy &&
                                   (~app_rdy);
    assign dbg_wr_wdf_rdy_wait   = (rw_state == RW_WRITE_REQ) &&
                                   wr_fifo_valid &&
                                   (write_burst_len != 0) &&
                                   (~app_wdf_rdy);
    assign dbg_rd_cmd_wait       = (rw_state == RW_READ_CMD) &&
                                   (read_burst_len != 0) &&
                                   rd_fifo_has_grant_space &&
                                   (~wr_level_urgent) &&
                                   (~app_rdy);
    assign dbg_rd_data_wait      = (rw_state == RW_READ_DATA) &&
                                   (~app_rd_data_valid) &&
                                   (~rd_fifo_full);

    native_dbg_streak_counter #(.CNT_WIDTH(DBG_CNT_WIDTH)) u_dbg_wr_no_service (
        .clk    (ui_clk),
        .rst    (dbg_cnt_reset),
        .active (dbg_wr_no_service),
        .cur    (dbg_wr_no_service_cur),
        .max    (dbg_wr_no_service_max)
    );

    native_dbg_streak_counter #(.CNT_WIDTH(DBG_CNT_WIDTH)) u_dbg_rd_no_service (
        .clk    (ui_clk),
        .rst    (dbg_cnt_reset),
        .active (dbg_rd_no_service),
        .cur    (dbg_rd_no_service_cur),
        .max    (dbg_rd_no_service_max)
    );

    native_dbg_streak_counter #(.CNT_WIDTH(DBG_CNT_WIDTH)) u_dbg_replay_block (
        .clk    (ui_clk),
        .rst    (dbg_cnt_reset),
        .active (dbg_replay_block),
        .cur    (dbg_replay_block_cur),
        .max    (dbg_replay_block_max)
    );

    native_dbg_streak_counter #(.CNT_WIDTH(DBG_CNT_WIDTH)) u_dbg_wr_app_rdy_wait (
        .clk    (ui_clk),
        .rst    (dbg_cnt_reset),
        .active (dbg_wr_app_rdy_wait),
        .cur    (dbg_wr_app_rdy_wait_cur),
        .max    (dbg_wr_app_rdy_wait_max)
    );

    native_dbg_streak_counter #(.CNT_WIDTH(DBG_CNT_WIDTH)) u_dbg_wr_wdf_rdy_wait (
        .clk    (ui_clk),
        .rst    (dbg_cnt_reset),
        .active (dbg_wr_wdf_rdy_wait),
        .cur    (dbg_wr_wdf_rdy_wait_cur),
        .max    (dbg_wr_wdf_rdy_wait_max)
    );

    native_dbg_streak_counter #(.CNT_WIDTH(DBG_CNT_WIDTH)) u_dbg_rd_cmd_wait (
        .clk    (ui_clk),
        .rst    (dbg_cnt_reset),
        .active (dbg_rd_cmd_wait),
        .cur    (dbg_rd_cmd_wait_cur),
        .max    (dbg_rd_cmd_wait_max)
    );

    native_dbg_streak_counter #(.CNT_WIDTH(DBG_CNT_WIDTH)) u_dbg_rd_data_wait (
        .clk    (ui_clk),
        .rst    (dbg_cnt_reset),
        .active (dbg_rd_data_wait),
        .cur    (dbg_rd_data_wait_cur),
        .max    (dbg_rd_data_wait_max)
    );

endmodule
