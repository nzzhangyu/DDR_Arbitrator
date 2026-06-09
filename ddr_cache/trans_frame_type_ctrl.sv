//--------------------------------------------------------------------------------
// Company: Neusoft Medical Systems
// Module Name: trans_frame_type_ctrl
// Description: Generate idle_process_en according to view transmission activity.
//--------------------------------------------------------------------------------

`timescale 1ns/1ps

module trans_frame_type_ctrl (
    input  logic aurora_sw_rst,
    input  logic rst_local_t_gtx_clk,
    input  logic gtx_user_clk_in,

    input  logic sampling_data_on,
    input  logic view_start_cnt_half,
    input  logic view_tx_done,
    input  logic gtx_clk_last_view_trans_fsh,

    output logic idle_process_en
);

    logic sampling_data_on_d;
    logic sampling_data_on_dd;
    logic busy_process_en;

    assign idle_process_en = ~busy_process_en;

    always_ff @(posedge gtx_user_clk_in) begin
        sampling_data_on_d  <= sampling_data_on;
        sampling_data_on_dd <= sampling_data_on_d;
    end

    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            busy_process_en <= 1'b0;
        end
        else if (~rst_local_t_gtx_clk) begin
            busy_process_en <= 1'b0;
        end
        else if (busy_process_en && gtx_clk_last_view_trans_fsh) begin
            busy_process_en <= 1'b0;
        end
        else if (sampling_data_on_dd && view_start_cnt_half) begin
            busy_process_en <= 1'b1;
        end
    end

endmodule
