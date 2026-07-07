`timescale 1ns/1ps

// Native read/write pressure control.
// - Tracks replay settle blocking.
// - Generates write/read request eligibility.
// - Holds write and read urgent hysteresis.
// - Reports read FIFO space and available DDR data.
module rw_pressure_ctrl #(
    parameter int ADDR_WIDTH = 24,

    parameter logic [14:0] WR_LEVEL_URGENT   = 15'd6144,
    parameter logic [14:0] WR_LEVEL_LOW      = 15'd4096,

    parameter logic [15:0] RD_LEVEL_URGENT   = 16'd4096,
    parameter logic [15:0] RD_LEVEL_HIGH     = 16'd6144,
    parameter logic [15:0] RD_FIFO_DEPTH     = 16'd8192,

    parameter logic [8:0]  WR_BURST_NUM      = 9'd256,
    parameter logic [9:0]  RD_BURST_NUM      = 10'd512,
    parameter logic [10:0] WR_TAIL_AGE_LIMIT = 11'd1024
) (
    input  logic                  ui_clk,
    input  logic                  ui_clk_sync_rst,
    input  logic                  rst_local_t_ddr_clk,
    input  logic                  make_data_on_edge,
    input  logic                  rp_back_en,

    input  logic                  wr_fifo_valid,
    input  logic                  wr_fifo_prog_empty,
    input  logic [14:0]           wr_fifo_rd_data_count,

    input  logic                  rd_fifo_prog_full,
    input  logic                  rd_fifo_full,
    input  logic                  rd_fifo_almost_empty,
    input  logic [15:0]           rd_fifo_data_count,

    input  logic                  ddr_rd_req,
    input  logic                  ddr_rd_empty,
    input  logic [ADDR_WIDTH:0]   ddr_rd_avail_count,

    input  logic                  clr_wr_wait_age,

    output logic                  ddr_wr_req,
    output logic                  ddr_rd_req_qual,
    output logic                  wr_level_urgent,
    output logic                  wr_has_full_burst,
    output logic                  rd_level_urgent,
    output logic                  rd_fifo_can_prefetch,
    output logic                  rd_fifo_has_grant_space,
    output logic [16:0]           rd_fifo_free_count,
    output logic [9:0]            rd_available_len,
    output logic                  block_for_replay
);

    logic [7:0]  rp_back_en_dly_cnt;
    logic [10:0] wr_tail_age_cnt;
    logic        wr_tail_age_reached;
    logic        rd_low_water;
    logic        rd_high_water;
    logic        rd_cache_armed;
    logic        rd_refill_urgent;
    logic        ddr_rd_req_d;
    logic        ddr_rd_req_dd;

    assign wr_tail_age_reached = (wr_tail_age_cnt >= WR_TAIL_AGE_LIMIT);
    assign wr_has_full_burst   = ~wr_fifo_prog_empty;

    assign rd_low_water         = rd_fifo_almost_empty |
                                  (rd_fifo_data_count <= RD_LEVEL_URGENT);
    assign rd_high_water        = rd_fifo_data_count >= RD_LEVEL_HIGH;
    assign rd_level_urgent      = rd_refill_urgent;
    assign rd_fifo_free_count   = {1'b0, RD_FIFO_DEPTH} -
                                  {1'b0, rd_fifo_data_count};
    assign rd_fifo_can_prefetch = (~rd_fifo_prog_full) &
                                  (~rd_fifo_full) &
                                  (rd_fifo_data_count < RD_LEVEL_HIGH);
    assign rd_fifo_has_grant_space = rd_fifo_free_count >= RD_BURST_NUM;
    assign rd_available_len = (ddr_rd_avail_count >= RD_BURST_NUM) ?
                              RD_BURST_NUM : ddr_rd_avail_count[9:0];

    assign block_for_replay = rp_back_en || (rp_back_en_dly_cnt != 8'd0);
    assign ddr_wr_req       = wr_fifo_valid &
                              (wr_has_full_burst | wr_tail_age_reached);
    assign ddr_rd_req_qual  = (~ddr_rd_empty) &
                              ddr_rd_req_dd &
                              rd_fifo_can_prefetch;

    // Replay settle window.
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

    // Write urgent hysteresis.
    always_ff @(posedge ui_clk) begin
        if (ui_clk_sync_rst || rst_local_t_ddr_clk ||
            make_data_on_edge || rp_back_en) begin
            wr_level_urgent <= 1'b0;
        end
        else if (wr_fifo_rd_data_count >= WR_LEVEL_URGENT) begin
            wr_level_urgent <= 1'b1;
        end
        else if (wr_fifo_rd_data_count <= WR_LEVEL_LOW) begin
            wr_level_urgent <= 1'b0;
        end
    end

    // Read refill hysteresis.
    always_ff @(posedge ui_clk) begin
        if (ui_clk_sync_rst || rst_local_t_ddr_clk ||
            make_data_on_edge || rp_back_en) begin
            rd_cache_armed   <= 1'b0;
            rd_refill_urgent <= 1'b0;
        end
        else if (rd_high_water) begin
            rd_cache_armed   <= 1'b1;
            rd_refill_urgent <= 1'b0;
        end
        else if (rd_cache_armed && rd_low_water) begin
            rd_refill_urgent <= 1'b1;
        end
    end

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

endmodule
