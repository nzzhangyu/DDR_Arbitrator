`timescale 1ns/1ps

// Native read/write FIFO watermark control.
// - Holds write and read urgent hysteresis.
module rw_pressure_ctrl #(
    parameter logic [14:0] WR_LEVEL_URGENT = 15'd6144,
    parameter logic [14:0] WR_LEVEL_LOW    = 15'd4096,

    parameter logic [15:0] RD_LEVEL_URGENT = 16'd4096,
    parameter logic [15:0] RD_LEVEL_HIGH   = 16'd6144
) (
    input  logic        i_ui_clk,
    input  logic        i_pressure_rst,
    input  logic        i_pressure_clear,

    input  logic [14:0] i_wr_fifo_rd_data_count,

    input  logic        i_rd_fifo_almost_empty,
    input  logic [15:0] i_rd_fifo_data_count,

    output logic        o_wr_level_urgent,
    output logic        o_rd_level_urgent
);

    logic rd_low_water;
    logic rd_high_water;
    logic rd_cache_armed;
    logic rd_refill_urgent;

    assign rd_low_water       = i_rd_fifo_almost_empty | (i_rd_fifo_data_count <= RD_LEVEL_URGENT);
    assign rd_high_water      = i_rd_fifo_data_count >= RD_LEVEL_HIGH;
    assign o_rd_level_urgent  = rd_refill_urgent;

    // Write urgent hysteresis.
    always_ff @(posedge i_ui_clk) begin
        if (i_pressure_rst || i_pressure_clear) begin
            o_wr_level_urgent <= 1'b0;
        end
        else if (i_wr_fifo_rd_data_count >= WR_LEVEL_URGENT) begin
            o_wr_level_urgent <= 1'b1;
        end
        else if (i_wr_fifo_rd_data_count <= WR_LEVEL_LOW) begin
            o_wr_level_urgent <= 1'b0;
        end
    end

    // Read refill hysteresis.
    always_ff @(posedge i_ui_clk) begin
        if (i_pressure_rst || i_pressure_clear) begin
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

endmodule
