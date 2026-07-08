`timescale 1ns/1ps

// DDR circular beat-address manager.
// - Tracks write, read-consume, and read-command pointers.
// - Applies replay backtracking.
// - Reports cached-data availability.
// - Raises ring-buffer status pulses.
module ddr_ring_addr_mgr #(
    parameter int ADDR_WIDTH = 24
) (
    input  logic                  i_ui_clk,
    input  logic                  i_ring_addr_rst,
    input  logic                  i_ring_addr_clear,

    input  logic                  i_wr_fire,
    input  logic                  i_rd_fire,
    input  logic                  i_rd_cmd_fire,
    input  logic                  i_replay_en,
    input  logic [ADDR_WIDTH-1:0] i_replay_addr,

    input  logic                  i_fault_ddr_overrun,
    input  logic                  i_fault_ddr_warning,

    output logic [ADDR_WIDTH:0]   o_wr_ptr,
    output logic [ADDR_WIDTH:0]   o_rd_ptr,
    output logic [ADDR_WIDTH:0]   o_rd_cmd_ptr,
    output logic [ADDR_WIDTH-1:0] o_wr_addr,
    output logic                  o_empty,
    output logic [ADDR_WIDTH:0]   o_data_count,
    output logic                  o_ddr_cache_overrun,
    output logic                  o_ddr_cache_overrun_warning
);

    logic [ADDR_WIDTH:0] same_wrap_data_count;
    logic [ADDR_WIDTH:0] diff_wrap_data_count;
    logic                ptr_same_wrap;
    logic                ptr_diff_wrap;
    logic                cache_full_overrun;

    assign o_wr_addr    = o_wr_ptr[ADDR_WIDTH-1:0];
    assign o_empty      = (o_wr_ptr == o_rd_ptr);
    assign o_data_count = o_wr_ptr - o_rd_ptr;

    // Pointer distance checks.
    assign ptr_same_wrap      = (o_wr_ptr[ADDR_WIDTH] == o_rd_ptr[ADDR_WIDTH]);
    assign ptr_diff_wrap      = (o_wr_ptr[ADDR_WIDTH] ^ o_rd_ptr[ADDR_WIDTH]);
    assign cache_full_overrun = ptr_diff_wrap &
                                (o_wr_ptr[ADDR_WIDTH-1:0] == o_rd_ptr[ADDR_WIDTH-1:0]);

    assign same_wrap_data_count = {1'b0, o_wr_ptr[ADDR_WIDTH-1:0]} - {1'b0, o_rd_ptr[ADDR_WIDTH-1:0]};
    assign diff_wrap_data_count = {1'b1, o_wr_ptr[ADDR_WIDTH-1:0]} - {1'b0, o_rd_ptr[ADDR_WIDTH-1:0]};

    // Write boundary.
    always_ff @(posedge i_ui_clk) begin
        if (i_ring_addr_rst || i_ring_addr_clear) begin
            o_wr_ptr <= '0;
        end
        else if (i_wr_fire) begin
            o_wr_ptr <= o_wr_ptr + 1'b1;
        end
    end

    // Returned-data boundary.
    always_ff @(posedge i_ui_clk) begin
        if (i_ring_addr_rst || i_ring_addr_clear) begin
            o_rd_ptr <= '0;
        end
        else if (i_replay_en) begin
            o_rd_ptr <= {1'b0, i_replay_addr};
        end
        else if (i_rd_fire) begin
            o_rd_ptr <= o_rd_ptr + 1'b1;
        end
    end

    // Read-command boundary.
    always_ff @(posedge i_ui_clk) begin
        if (i_ring_addr_rst || i_ring_addr_clear) begin
            o_rd_cmd_ptr <= '0;
        end
        else if (i_replay_en) begin
            o_rd_cmd_ptr <= {1'b0, i_replay_addr};
        end
        else if (i_rd_cmd_fire) begin
            o_rd_cmd_ptr <= o_rd_cmd_ptr + 1'b1;
        end
    end

    // Overrun pulse.
    always_ff @(posedge i_ui_clk) begin
        if (i_ring_addr_rst || i_ring_addr_clear) begin
            o_ddr_cache_overrun <= '0;
        end
        else if (i_fault_ddr_overrun || cache_full_overrun) begin
            o_ddr_cache_overrun <= 1'b1;
        end
        else begin
            o_ddr_cache_overrun <= '0;
        end
    end

    // Warning pulse.
    always_ff @(posedge i_ui_clk) begin
        if (i_ring_addr_rst || i_ring_addr_clear) begin
            o_ddr_cache_overrun_warning <= '0;
        end
        else if (i_fault_ddr_warning) begin
            o_ddr_cache_overrun_warning <= 1'b1;
        end
        else if (ptr_same_wrap && (|same_wrap_data_count[ADDR_WIDTH:ADDR_WIDTH-2])) begin
            o_ddr_cache_overrun_warning <= 1'b1;
        end
        else if (ptr_diff_wrap && (|diff_wrap_data_count[ADDR_WIDTH:ADDR_WIDTH-2])) begin
            o_ddr_cache_overrun_warning <= 1'b1;
        end
        else begin
            o_ddr_cache_overrun_warning <= '0;
        end
    end

endmodule
