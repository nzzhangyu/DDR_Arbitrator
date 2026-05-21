`timescale 1ns/1ps

// Periodic active-high pressure window; interval/block <= 0 disables it.
module ddr4_fast_mock_periodic_stall (
    input  logic clk,
    input  logic reset,
    input  logic enable,
    input  int   interval_cycles_cfg,
    input  int   block_cycles_cfg,
    output logic active
);

    int interval_cnt_q;    // Time until next pressure window.
    int active_left_q;     // Remaining active cycles.

    // Count idle cycles until the interval expires, then hold active for block.
    always_ff @(posedge clk) begin
        if (reset || (~enable) ||
            (interval_cycles_cfg <= 0) || (block_cycles_cfg <= 0)) begin
            interval_cnt_q <= 0;
            active_left_q  <= 0;
            active         <= 1'b0;
        end
        else if (active) begin
            if (active_left_q <= 1) begin
                interval_cnt_q <= 0;
                active_left_q  <= 0;
                active         <= 1'b0;
            end
            else begin
                active_left_q <= active_left_q - 1;
            end
        end
        else if (interval_cnt_q >= (interval_cycles_cfg - 1)) begin
            interval_cnt_q <= 0;
            active_left_q  <= block_cycles_cfg;
            active         <= 1'b1;
        end
        else begin
            interval_cnt_q <= interval_cnt_q + 1;
        end
    end

endmodule
