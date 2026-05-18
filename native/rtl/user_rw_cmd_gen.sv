`timescale 1ns/1ps

module user_rw_cmd_gen #(
    parameter int ADDR_WIDTH     = 24,
    parameter int APP_ADDR_WIDTH = ADDR_WIDTH + 4
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
    output logic                      ddr_warning,
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
    localparam logic [13:0] WR_LEVEL_HIGH     = 14'd8192;
    localparam logic [13:0] WR_LEVEL_URGENT   = 14'd12288;

    localparam logic [13:0] RD_LEVEL_URGENT   = 14'd4096;
    localparam logic [13:0] RD_LEVEL_LOW      = 14'd8192;
    localparam logic [13:0] RD_LEVEL_HIGH     = 14'd12288;
    localparam logic [13:0] RD_FIFO_DEPTH     = 14'd16383;

    localparam logic [9:0]  RD_SERVICE_MAX     = 10'd512;
    localparam logic [9:0]  RD_SERVICE_WR_HIGH = 10'd128;

    localparam logic [2:0]  APP_CMD_WRITE     = 3'b000;
    localparam logic [2:0]  APP_CMD_READ      = 3'b001;

    typedef enum logic [3:0] {
        RW_IDLE,      // Wait/blocked.
        RW_ARB_PRE,   // Fast arbitration.
        RW_ARB,       // Fair arbitration.
        RW_WRITE_REQ, // Native write beat.
        RW_READ_CMD,  // Native read command.
        RW_READ_DATA  // Native read data.
    } rw_state_t;

    typedef enum logic [1:0] {
        GRANT_NONE,
        GRANT_WRITE,
        GRANT_READ
    } grant_t;

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
        else if (|rp_back_en_dly_cnt) begin
            rp_back_en_dly_cnt <= rp_back_en_dly_cnt + 8'd1;
        end
    end

    logic [10:0] wr_tail_age_cnt;
    logic        wr_tail_age_reached;
    logic        clr_wr_wait_age;

    // Partial-write aging.
    localparam logic [10:0] WR_TAIL_AGE_LIMIT = 11'd1024;

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
    logic        wr_level_high;
    logic        wr_level_urgent;
    logic        wr_has_full_burst;
    logic        rd_level_low;
    logic        rd_level_urgent;
    logic        rd_fifo_can_prefetch;
    logic [14:0] rd_fifo_free_count;

    assign wr_level_high         = wr_fifo_rd_data_count >= WR_LEVEL_HIGH;
    assign wr_level_urgent       = wr_fifo_rd_data_count >= WR_LEVEL_URGENT;
    assign wr_has_full_burst     = ~wr_fifo_prog_empty;
    
    assign rd_level_urgent       = rd_fifo_almost_empty |
                                    (rd_fifo_data_count <= RD_LEVEL_URGENT);
    assign rd_level_low          = rd_fifo_data_count <= RD_LEVEL_LOW;
    assign rd_fifo_free_count    = {1'b0, RD_FIFO_DEPTH} - {1'b0, rd_fifo_data_count};
    assign rd_fifo_can_prefetch  = (~rd_fifo_prog_full) &
                                    (~rd_fifo_full) &
                                    (rd_fifo_data_count < RD_LEVEL_HIGH);

    // Request gating.
    logic ddr_wr_req;
    logic ddr_rd_req_d;
    logic ddr_rd_req_dd;
    logic ddr_rd_req_qual;

    // Full group or aged tail.
    assign ddr_wr_req = wr_fifo_valid &
                        (wr_has_full_burst | wr_tail_age_reached);

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

    // Fair-grant history.
    logic set_last_wr;
    logic set_last_rd;
    logic clr_last_grant;
    logic last_was_wr;
    logic last_was_rd;

    always_ff @(posedge ui_clk) begin
        if (ui_clk_sync_rst) begin
            last_was_wr <= '0;
        end
        else if (clr_last_grant || set_last_rd) begin
            last_was_wr <= '0;
        end
        else if (set_last_wr) begin
            last_was_wr <= 1'b1;
        end
    end

    always_ff @(posedge ui_clk) begin
        if (ui_clk_sync_rst) begin
            last_was_rd <= '0;
        end
        else if (clr_last_grant || set_last_wr) begin
            last_was_rd <= '0;
        end
        else if (set_last_rd) begin
            last_was_rd <= 1'b1;
        end
    end

    // Burst/service tracking.
    logic [8:0] write_burst_len;
    logic [9:0] read_burst_len;
    logic [8:0] write_beat_cnt;
    logic [9:0] read_beat_cnt;
    logic       write_burst_done;
    logic       read_burst_done;

    logic [9:0] rd_service_limit;
    logic [9:0] rd_available_len;
    logic [ADDR_WIDTH:0] ddr_rd_avail_count;

    logic       app_cmd_fire;
    logic       write_data_fire;
    logic       read_data_fire;
    logic       block_for_replay;
    logic       rd_fifo_has_grant_space;

    // Read service budget.
    assign rd_service_limit = wr_level_high ? RD_SERVICE_WR_HIGH : RD_SERVICE_MAX;
    assign rd_available_len = (|ddr_rd_avail_count[ADDR_WIDTH:9]) ?
                                RD_SERVICE_MAX : ddr_rd_avail_count[9:0];
    assign rd_fifo_has_grant_space = (~rd_fifo_full) && (rd_fifo_free_count != 0);
    // Replay blocks arbitration.
    assign block_for_replay = rp_back_en || (|rp_back_en_dly_cnt);

    // Request classes.
    logic wr_urgent_req;
    logic wr_high_req;
    logic wr_fair_req;

    logic rd_req_with_space;
    logic rd_req_allowed;
    logic rd_urgent_req;
    logic rd_low_or_urgent_req;
    logic rd_fair_req;
    logic both_rw_req;

    assign wr_urgent_req        = wr_level_urgent && ddr_wr_req;
    assign wr_high_req          = wr_level_high && ddr_wr_req;
    assign rd_req_with_space    = ddr_rd_req_qual && rd_fifo_has_grant_space;
    assign rd_req_allowed       = rd_req_with_space && (~wr_level_urgent);
    assign rd_urgent_req        = rd_level_urgent && rd_req_allowed;
    assign rd_low_or_urgent_req = (rd_level_low || rd_level_urgent) && rd_req_allowed;
    assign both_rw_req          = ddr_wr_req && ddr_rd_req_qual;
    assign wr_fair_req          = ddr_wr_req && (~last_was_wr);
    assign rd_fair_req          = rd_req_allowed && (~last_was_rd);

    // Grant selection.
    grant_t arb_pre_grant;      // Pre-arbitration grant.
    grant_t arb_fair_grant;     // Fair grant.
    
    always_comb begin
        arb_pre_grant = GRANT_NONE;

        if (wr_urgent_req) begin
            arb_pre_grant = GRANT_WRITE;
        end
        else if (rd_urgent_req) begin
            arb_pre_grant = GRANT_READ;
        end
        else if (both_rw_req) begin
            arb_pre_grant = GRANT_NONE;
        end
        else if (rd_req_allowed) begin
            arb_pre_grant = GRANT_READ;
        end
        else if (ddr_wr_req) begin
            arb_pre_grant = GRANT_WRITE;
        end
    end

    always_comb begin
        arb_fair_grant = GRANT_NONE;

        if (wr_urgent_req) begin
            arb_fair_grant = GRANT_WRITE;
        end
        else if (rd_low_or_urgent_req) begin
            arb_fair_grant = GRANT_READ;
        end
        else if (wr_high_req && (~last_was_wr)) begin
            arb_fair_grant = GRANT_WRITE;
        end
        else if (wr_fair_req) begin
            arb_fair_grant = GRANT_WRITE;
        end
        else if (rd_fair_req) begin
            arb_fair_grant = GRANT_READ;
        end
        else if (ddr_wr_req) begin
            arb_fair_grant = GRANT_WRITE;
        end
        else if (rd_req_allowed) begin
            arb_fair_grant = GRANT_READ;
        end
    end

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

    // Urgent writes protect FIFO space; fair grants avoid one-sided service.
    always_comb begin
        rw_next_state      = rw_state;
        set_last_wr        = 1'b0;
        set_last_rd        = 1'b0;
        clr_last_grant     = 1'b0;
        clr_wr_wait_age    = 1'b0;

        if (~init_calib_complete) begin
            rw_next_state   = RW_IDLE;
            clr_last_grant  = 1'b1;
        end
        else begin
            unique case (rw_state)
                RW_IDLE: begin
                    clr_last_grant = 1'b1;
                    rw_next_state  = block_for_replay ? RW_IDLE : RW_ARB_PRE;
                end

                RW_ARB_PRE: begin
                    // Replay has priority.
                    if (block_for_replay) begin
                        rw_next_state  = RW_IDLE;
                        clr_last_grant = 1'b1;
                    end
                    else begin
                        unique case (arb_pre_grant)
                            GRANT_WRITE: begin
                                rw_next_state  = RW_WRITE_REQ;
                                clr_last_grant = 1'b1;
                            end

                            GRANT_READ: begin
                                rw_next_state  = RW_READ_CMD;
                                clr_last_grant = 1'b1;
                            end

                            default: begin
                                // Use fair grant.
                                if (both_rw_req) begin
                                rw_next_state = RW_ARB;
                                end
                            end
                        endcase
                    end
                end

                RW_ARB: begin
                    unique case (arb_fair_grant)
                        GRANT_WRITE: begin
                            rw_next_state = RW_WRITE_REQ;
                            set_last_wr   = 1'b1;
                        end

                        GRANT_READ: begin
                            rw_next_state = RW_READ_CMD;
                            set_last_rd   = 1'b1;
                        end

                        default: begin
                            rw_next_state  = RW_ARB_PRE;
                            clr_last_grant = 1'b1;
                        end
                    endcase
                end

                RW_WRITE_REQ: begin
                    clr_wr_wait_age = 1'b1;
                    if (write_burst_len == 0) begin
                        rw_next_state = RW_ARB_PRE;
                    end
                    else if (~wr_fifo_valid) begin
                        rw_next_state = RW_ARB_PRE;
                    end
                    // Native write command/data handshake.
                    else if (write_burst_done) begin
                        rw_next_state = RW_ARB_PRE;
                    end
                end

                RW_READ_CMD: begin
                    if ((read_burst_len == 0) || (~rd_fifo_has_grant_space) || wr_level_urgent) begin
                        rw_next_state = RW_ARB_PRE;
                    end
                    // Unaccepted reads may be aborted by urgent write.
                    else if (app_cmd_fire) begin
                        rw_next_state = RW_READ_DATA;
                    end
                end

                RW_READ_DATA: begin
                    // Accepted reads wait for their return beat.
                    if (read_burst_done || wr_level_urgent) begin
                        rw_next_state = RW_ARB_PRE;
                    end
                    else if (read_data_fire) begin
                        rw_next_state = RW_READ_CMD;
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
    logic [ADDR_WIDTH-1:0] user_ad_wr;
    logic [ADDR_WIDTH-1:0] user_ad_rd;

    assign user_ad_wr               = user_ad_wr_i[ADDR_WIDTH-1:0];
    assign user_ad_rd               = user_ad_rd_i[ADDR_WIDTH-1:0];
    assign ddr_rd_empty             = (user_ad_wr_i == user_ad_rd_i);
    assign ddr_rd_avail_count       = user_ad_wr_i - user_ad_rd_i;

    // Handshake pulses.
    assign app_cmd_fire    = app_en && app_rdy;
    assign write_data_fire = (rw_state == RW_WRITE_REQ) &&
                                app_en &&
                                app_rdy &&
                                app_wdf_wren &&
                                app_wdf_rdy;
    assign read_data_fire  = app_rd_data_valid && (~rd_fifo_full);

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
        // Replay read pointer.
        else if (rp_back_en) begin
            user_ad_rd_i <= {1'b0, rp_back_view_addr};
        end
        else if (read_data_fire) begin
            user_ad_rd_i <= user_ad_rd_i + 1'b1;
        end
    end

    always_ff @(posedge ui_clk) begin
        if (ui_clk_sync_rst || rst_local_t_ddr_clk || make_data_on_edge) begin
            write_burst_len <= '0;
        end
        else if (rw_state == RW_ARB_PRE || rw_state == RW_ARB) begin
            // Clamp write group to 256 beats.
            if (wr_fifo_rd_data_count >= 14'd256) begin
                write_burst_len <= 9'd256;
            end
            else if (wr_fifo_rd_data_count != 0) begin
                write_burst_len <= {1'b0, wr_fifo_rd_data_count[7:0]};
            end
            else if (wr_fifo_valid) begin
                write_burst_len <= 9'd1;
            end
            else begin
                write_burst_len <= '0;
            end
        end
    end

    always_ff @(posedge ui_clk) begin
        if (ui_clk_sync_rst || rst_local_t_ddr_clk || make_data_on_edge) begin
            read_burst_len <= '0;
        end
        else if (rw_state == RW_ARB_PRE || rw_state == RW_ARB) begin
            // Clamp read service by availability.
            read_burst_len <= (rd_available_len < rd_service_limit) ?
                                rd_available_len : rd_service_limit;
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

    assign write_burst_done = write_data_fire && (write_beat_cnt == (write_burst_len - 1'b1));
    assign read_burst_done  = read_data_fire && (read_beat_cnt == (read_burst_len - 1'b1));

    assign wr_fifo_rd_en = write_data_fire;

    // Native app channel drive.

    assign app_addr     = (rw_state == RW_READ_CMD) ?
                            beat_to_app_addr(user_ad_rd) :
                            beat_to_app_addr(user_ad_wr);
    assign app_cmd      = (rw_state == RW_READ_CMD) ? APP_CMD_READ : APP_CMD_WRITE;
    assign app_en       = ((rw_state == RW_WRITE_REQ) &&
                            (write_burst_len != 0) &&
                            wr_fifo_valid &&
                            app_wdf_rdy) ||
                            ((rw_state == RW_READ_CMD) &&
                            (read_burst_len != 0) &&
                            rd_fifo_has_grant_space &&
                            (~wr_level_urgent));

    assign app_wdf_data = wr_fifo_dout;
    assign app_wdf_mask = 16'h0000;
    assign app_wdf_wren = (rw_state == RW_WRITE_REQ) &&
                            wr_fifo_valid &&
                            app_rdy &&
                            (write_beat_cnt < write_burst_len);
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
        // Beat address to byte address.
        beat_to_app_addr = ({ {(APP_ADDR_WIDTH-ADDR_WIDTH){1'b0}}, beat_addr } << 4);
    endfunction

endmodule
