`timescale 1ns/1ps

// Native circular-buffer status monitor.
// - Detects DDR ring-buffer overrun.
// - Raises high-occupancy warning pulses.
// - Preserves fault-injection status paths.
module ddr_overrun_monitor #(
    parameter int ADDR_WIDTH = 24
) (
    input  logic                  ui_clk,
    input  logic                  ui_clk_sync_rst,
    input  logic                  rst_local_t_ddr_clk,
    input  logic                  init_calib_complete,
    input  logic                  make_data_on_edge,
    input  logic                  fault_ddr_overrun,
    input  logic                  fault_ddr_warning,
    input  logic [ADDR_WIDTH:0]   user_ad_wr_i,
    input  logic [ADDR_WIDTH:0]   user_ad_rd_i,
    output logic                  ddr_overrun,
    output logic                  ddr_warning
);

    logic [ADDR_WIDTH:0] wr_sub_rd;
    logic [ADDR_WIDTH:0] wr_sub_rd_diff;
    logic                wr_rd_same_signal;
    logic                wr_rd_diff_signal;
    logic                set_ddr_overrun;

    // Pointer distance checks.
    assign wr_rd_same_signal = (user_ad_wr_i[ADDR_WIDTH] == user_ad_rd_i[ADDR_WIDTH]);
    assign wr_rd_diff_signal = (user_ad_wr_i[ADDR_WIDTH] ^ user_ad_rd_i[ADDR_WIDTH]);
    assign set_ddr_overrun   = wr_rd_diff_signal &
                                (user_ad_wr_i[ADDR_WIDTH-1:0] ==
                                 user_ad_rd_i[ADDR_WIDTH-1:0]);

    assign wr_sub_rd      = {1'b0, user_ad_wr_i[ADDR_WIDTH-1:0]} -
                            {1'b0, user_ad_rd_i[ADDR_WIDTH-1:0]};
    assign wr_sub_rd_diff = {1'b1, user_ad_wr_i[ADDR_WIDTH-1:0]} -
                            {1'b0, user_ad_rd_i[ADDR_WIDTH-1:0]};

    // Overrun pulse.
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

    // Warning pulse.
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

endmodule
