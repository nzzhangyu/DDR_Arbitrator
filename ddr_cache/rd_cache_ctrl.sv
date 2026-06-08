`timescale 1ns/1ps

module rd_cache_ctrl #(
    parameter int ADDR_WIDTH                 = 24,
    parameter int GTX_CLK2UI_CLK_PULSE_WIDTH = 'h3,
    parameter int SYS_CLK2UI_CLK_PULSE_WIDTH = 'h3,
    parameter int UI_CLK2GTX_CLK_PULSE_WIDTH = 'h3
) (
    input  logic                  ui_clk,
    input  logic                  ddr_user_rst,
    input  logic                  rst_local_t_ddr_clk,

    input  logic                  clk_sysclk_in,
    input  logic                  sys_rst,
    input  logic                  view_Reading_Done,
    input  logic                  last_view_wr_done,

    input  logic                  idle_process_en,
    input  logic                  refresh_process_en,
    input  logic                  TX_CHANNEL_UP_in,
    input  logic                  aurora_asy_fifo_almost_full,
    input  logic                  ddr_rd_empty,

    input  logic                  make_data_on,
    input  logic [15:0]           view_size,
    input  logic                  user_r_valid,

    input  logic                  rp_back_en_i,
    input  logic                  rp_back_en_rst,
    input  logic                  uiclk_pulse_1us,
    input  logic                  view_trans_ok,

    output logic                  ddr_rd_req,
    output logic                  req_stop,
    output logic [ADDR_WIDTH-1:0] rp_back_view_addr,
    output logic                  last_view_trans_ok,
    output logic                  sample_frame_rd_done,
    output logic [1:0]            rd_cache_state,
    output logic                  rd_wr_num_equ
);

    typedef enum logic [1:0] {
        RD_IDLE,
        RD_REQ_EN,
        RD_WAIT_INTERVAL
    } rd_state_t;

    localparam logic [7:0] VIEW_INTERVAL_US = 8'd90;

    // -------------------------------------------------------------------------
    // Clock-Domain Crossings
    // -------------------------------------------------------------------------
    logic wr_view_pulse;
    logic ui_clk_last_view_wr_done;

    cross_clk_pulse #(
        .PULSE_WIDTH(SYS_CLK2UI_CLK_PULSE_WIDTH)
    ) wr_view_pulse_gen_dut (
        .o     (wr_view_pulse),
        .i     (view_Reading_Done),
        .i_clk (clk_sysclk_in),
        .i_rst (sys_rst),
        .o_clk (ui_clk),
        .o_rst (ddr_user_rst)
    );

    cross_clk_pulse #(
        .PULSE_WIDTH(SYS_CLK2UI_CLK_PULSE_WIDTH)
    ) last_view_wr_done_sync_dut (
        .o     (ui_clk_last_view_wr_done),
        .i     (last_view_wr_done),
        .i_clk (clk_sysclk_in),
        .i_rst (sys_rst),
        .o_clk (ui_clk),
        .o_rst (ddr_user_rst)
    );

    (* ASYNC_REG = "true" *) logic refresh_process_en_rcom_cdc_to_d;
    (* ASYNC_REG = "true" *) logic refresh_process_en_dd;

    always_ff @(posedge ui_clk) begin
        if (ddr_user_rst) begin
            refresh_process_en_rcom_cdc_to_d <= '0;
            refresh_process_en_dd            <= '0;
        end
        else begin
            refresh_process_en_rcom_cdc_to_d <= refresh_process_en;
            refresh_process_en_dd            <= refresh_process_en_rcom_cdc_to_d;
        end
    end

    (* ASYNC_REG = "true" *) logic make_data_on_rcom_cdc_to_d;
    (* ASYNC_REG = "true" *) logic uiclk_make_data_on_dd;
    (* ASYNC_REG = "true" *) logic uiclk_make_data_on_ddd;
    logic make_data_on_r_edge;

    always_ff @(posedge ui_clk) begin
        if (ddr_user_rst) begin
            make_data_on_rcom_cdc_to_d <= '0;
            uiclk_make_data_on_dd      <= '0;
            uiclk_make_data_on_ddd     <= '0;
        end
        else begin
            make_data_on_rcom_cdc_to_d <= make_data_on;
            uiclk_make_data_on_dd      <= make_data_on_rcom_cdc_to_d;
            uiclk_make_data_on_ddd     <= uiclk_make_data_on_dd;
        end
    end

    assign make_data_on_r_edge = uiclk_make_data_on_dd & (~uiclk_make_data_on_ddd);

    (* ASYNC_REG = "true" *) logic tx_channel_up_rcom_cdc_to_d;
    (* ASYNC_REG = "true" *) logic tx_channel_up_dd;

    always_ff @(posedge ui_clk) begin
        if (ddr_user_rst) begin
            tx_channel_up_rcom_cdc_to_d <= '0;
            tx_channel_up_dd            <= '0;
        end
        else begin
            tx_channel_up_rcom_cdc_to_d <= TX_CHANNEL_UP_in;
            tx_channel_up_dd            <= tx_channel_up_rcom_cdc_to_d;
        end
    end

    // -------------------------------------------------------------------------
    // View Progress Accounting
    // -------------------------------------------------------------------------
    logic [31:0] wr_view_num;
    logic [31:0] rd_view_num;
    logic [15:0] rd_data_cnt;
    logic [1:0]  rp_back_num;
    logic        rd_data_cnt_lim;
    logic        wr_gt_rd;

    assign rd_data_cnt_lim      = (rd_data_cnt == (view_size - 16'd1));
    assign sample_frame_rd_done = user_r_valid & rd_data_cnt_lim;
    assign rd_wr_num_equ        = (rd_view_num == wr_view_num);
    assign wr_gt_rd             = (wr_view_num > rd_view_num);

    always_ff @(posedge ui_clk) begin
        if (ddr_user_rst) begin
            wr_view_num <= '0;
        end
        else if (rst_local_t_ddr_clk || make_data_on_r_edge) begin
            wr_view_num <= '0;
        end
        else if (wr_view_pulse) begin
            wr_view_num <= wr_view_num + 32'd1;
        end
    end

    always_ff @(posedge ui_clk) begin
        if (ddr_user_rst || rst_local_t_ddr_clk || make_data_on_r_edge) begin
            rd_data_cnt <= '0;
        end
        else if (sample_frame_rd_done || rp_back_en_i || rp_back_en_rst) begin
            rd_data_cnt <= '0;
        end
        else if (user_r_valid) begin
            rd_data_cnt <= rd_data_cnt + 16'd1;
        end
    end

    always_ff @(posedge ui_clk) begin
        if (ddr_user_rst) begin
            rd_view_num <= '0;
        end
        else if (rst_local_t_ddr_clk || make_data_on_r_edge) begin
            rd_view_num <= '0;
        end
        else if (rp_back_en_i) begin
            rd_view_num <= rd_view_num - {30'd0, rp_back_num};
        end
        else if (sample_frame_rd_done) begin
            rd_view_num <= rd_view_num + 32'd1;
        end
    end

    // -------------------------------------------------------------------------
    // Replay / Backtracking Address Tracking
    // -------------------------------------------------------------------------
    logic [ADDR_WIDTH-1:0] view_size_ext;
    logic [ADDR_WIDTH-1:0] back_offset;
    logic [ADDR_WIDTH-1:0] rd_latest_addr;
    logic [ADDR_WIDTH-1:0] rd_latest_addr_next;

    assign view_size_ext       = {{(ADDR_WIDTH-16){1'b0}}, view_size};
    assign rd_latest_addr_next = rd_latest_addr + view_size_ext;

    always_comb begin
        if (rp_back_num <= 2'd1) begin
            back_offset = view_size_ext;
        end
        else begin
            back_offset = view_size_ext << 1;
        end
    end

    // Track how many recent views can be replayed. The original logic caps
    // replay depth at two views.
    always_ff @(posedge ui_clk) begin
        if (ddr_user_rst) begin
            rp_back_num <= '0;
        end
        else if (rst_local_t_ddr_clk || make_data_on_r_edge) begin
            rp_back_num <= '0;
        end
        else if (rp_back_en_i) begin
            rp_back_num <= '0;
        end
        else if (sample_frame_rd_done && (~rp_back_num[1])) begin
            rp_back_num <= rp_back_num + 2'd1;
        end
    end

    always_ff @(posedge ui_clk) begin
        if (ddr_user_rst) begin
            rd_latest_addr <= '0;
        end
        else if (rst_local_t_ddr_clk || make_data_on_r_edge) begin
            rd_latest_addr <= '0;
        end
        else if (rp_back_en_i) begin
            rd_latest_addr <= rd_latest_addr - back_offset;
        end
        else if (sample_frame_rd_done) begin
            rd_latest_addr <= rd_latest_addr_next;
        end
    end

    always_ff @(posedge ui_clk) begin
        if (ddr_user_rst) begin
            rp_back_view_addr <= '0;
        end
        else if (rst_local_t_ddr_clk || make_data_on_r_edge) begin
            rp_back_view_addr <= '0;
        end
        else if (rp_back_en_i) begin
            rp_back_view_addr <= rd_latest_addr - back_offset;
        end
    end

    // -------------------------------------------------------------------------
    // DDR Read Request Pacing
    // -------------------------------------------------------------------------
    logic [7:0]  interval_cnt;
    logic        interval_cnt_lim;
    logic        ddr_rd_req_t;
    logic        req_en_state_trig;
    logic        req_enable;
    rd_state_t   req_state;
    rd_state_t   req_state_next;

    assign interval_cnt_lim = (interval_cnt == VIEW_INTERVAL_US);
    assign ddr_rd_req_t     = (~aurora_asy_fifo_almost_full) &
                              (~idle_process_en) &
                              (~refresh_process_en_dd) &
                              tx_channel_up_dd &
                              wr_gt_rd;
    assign req_en_state_trig = (req_state == RD_IDLE) & interval_cnt_lim & ddr_rd_req_t;

    // State transition.
    always_ff @(posedge ui_clk) begin
        if (ddr_user_rst) begin
            req_state <= RD_IDLE;
        end
        else begin
            req_state <= req_state_next;
        end
    end

    // Next-state decision.
    always_comb begin
        req_state_next = req_state;

        unique case (req_state)
            RD_IDLE: begin
                if (req_en_state_trig) begin
                    req_state_next = RD_REQ_EN;
                end
            end

            RD_REQ_EN: begin
                if (sample_frame_rd_done) begin
                    req_state_next = RD_WAIT_INTERVAL;
                end
            end

            RD_WAIT_INTERVAL: begin
                if (interval_cnt_lim) begin
                    req_state_next = RD_IDLE;
                end
            end

            default: begin
                req_state_next = RD_IDLE;
            end
        endcase
    end

    // State output assignment.
    assign req_enable = (req_state == RD_REQ_EN);
    assign ddr_rd_req = req_enable & ddr_rd_req_t;
    assign req_stop   = (~req_enable) | rd_wr_num_equ;

    always_ff @(posedge ui_clk) begin
        rd_cache_state <= req_state;
    end

    always_ff @(posedge ui_clk) begin
        if (ddr_user_rst) begin
            interval_cnt <= '0;
        end
        else if (idle_process_en || refresh_process_en_dd) begin
            interval_cnt <= '0;
        end
        else if (req_en_state_trig) begin
            interval_cnt <= '0;
        end
        else if ((~interval_cnt_lim) && uiclk_pulse_1us) begin
            interval_cnt <= interval_cnt + 8'd1;
        end
    end

    // -------------------------------------------------------------------------
    // Final View Completion
    // -------------------------------------------------------------------------
    logic last_view_wr_done_ind;
    logic set_last_view_trans_ok;

    assign set_last_view_trans_ok = (~idle_process_en) &
                                    last_view_wr_done_ind &
                                    ddr_rd_empty &
                                    view_trans_ok;

    always_ff @(posedge ui_clk) begin
        if (ddr_user_rst) begin
            last_view_wr_done_ind <= '0;
        end
        else if (rst_local_t_ddr_clk) begin
            last_view_wr_done_ind <= '0;
        end
        else if (set_last_view_trans_ok) begin
            last_view_wr_done_ind <= '0;
        end
        else if (ui_clk_last_view_wr_done) begin
            last_view_wr_done_ind <= 1'b1;
        end
    end

    always_ff @(posedge ui_clk) begin
        if (ddr_user_rst) begin
            last_view_trans_ok <= '0;
        end
        else if (rst_local_t_ddr_clk) begin
            last_view_trans_ok <= '0;
        end
        else begin
            last_view_trans_ok <= set_last_view_trans_ok;
        end
    end

endmodule
