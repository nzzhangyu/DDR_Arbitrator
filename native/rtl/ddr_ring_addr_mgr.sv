`timescale 1ns/1ps

// DDR circular beat-address manager.
// - Tracks write, read-consume, and read-command pointers.
// - Applies replay backtracking.
// - Reports cached-data availability.
module ddr_ring_addr_mgr #(
    parameter int ADDR_WIDTH = 24
) (
    input  logic                  ui_clk,
    input  logic                  ui_clk_sync_rst,
    input  logic                  rst_local_t_ddr_clk,
    input  logic                  make_data_on_edge,
    input  logic                  write_data_fire,
    input  logic                  read_data_fire,
    input  logic                  read_cmd_fire,
    input  logic                  rp_back_en,
    input  logic [ADDR_WIDTH-1:0] rp_back_view_addr,

    output logic [ADDR_WIDTH:0]   user_ad_wr_i,
    output logic [ADDR_WIDTH:0]   user_ad_rd_i,
    output logic [ADDR_WIDTH:0]   rd_cmd_ptr,
    output logic [ADDR_WIDTH-1:0] user_ad_wr,
    output logic [ADDR_WIDTH-1:0] user_ad_rd,
    output logic                  ddr_rd_empty,
    output logic [ADDR_WIDTH:0]   ddr_rd_avail_count
);

    assign user_ad_wr         = user_ad_wr_i[ADDR_WIDTH-1:0];
    assign user_ad_rd         = user_ad_rd_i[ADDR_WIDTH-1:0];
    assign ddr_rd_empty       = (user_ad_wr_i == user_ad_rd_i);
    assign ddr_rd_avail_count = user_ad_wr_i - user_ad_rd_i;

    // Write boundary.
    always_ff @(posedge ui_clk) begin
        if (ui_clk_sync_rst || rst_local_t_ddr_clk || make_data_on_edge) begin
            user_ad_wr_i <= '0;
        end
        else if (write_data_fire) begin
            user_ad_wr_i <= user_ad_wr_i + 1'b1;
        end
    end

    // Returned-data boundary.
    always_ff @(posedge ui_clk) begin
        if (ui_clk_sync_rst || rst_local_t_ddr_clk || make_data_on_edge) begin
            user_ad_rd_i <= '0;
        end
        else if (rp_back_en) begin
            user_ad_rd_i <= {1'b0, rp_back_view_addr};
        end
        else if (read_data_fire) begin
            user_ad_rd_i <= user_ad_rd_i + 1'b1;
        end
    end

    // Read-command boundary.
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

endmodule
