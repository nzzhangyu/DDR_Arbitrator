//--------------------------------------------------------------------------------
// Company: Neusoft Medical Systems
// Module Name: aurora_tx_top
// Description: Buffer DDR read data and drive Aurora TX frame generation.
//--------------------------------------------------------------------------------

`include "h80_define.sv"
`timescale 1ns/1ps

module aurora_tx_top (
    input  logic         ui_clk,
    input  logic         ddr_user_rst,
    input  logic         rst_local_t_ddr_clk,

    input  logic         gtx_user_clk_in,
    input  logic         rst_local_t_gtx_clk,
    input  logic         clk_40mhz_1us_in,

    input  logic         console_reset_in,
    input  logic         aurora_tx_reset,
    input  logic         TX_CHANNEL_UP_in,
    input  logic         m_axis_tx_tready,

    input  logic [127:0] user_r_data,
    input  logic         user_r_valid,

    input  logic         refresh_process_en,
    input  logic         Fault_inject_en,
    input  logic [8:0]   slice_sel,
    input  logic [11:0]  slice_length_odd,
    input  logic [11:0]  slice_length_even,

    input  logic [7:0]   DMS_Type,
    input  logic [15:0]  L_FTP_temp,
    input  logic [15:0]  R_FTP_temp,
    input  logic         make_data_on,
    input  logic         sampling_data_on,
    input  logic         conv,
    input  logic         gtx_clk_last_view_trans_fsh,
    input  logic         rp_back_en_rst,

`ifdef TX_DATA_WIDTH_32
    output logic [3:0]   m_axis_tx_tkeep,
    output logic [31:0]  m_axis_tx_tdata,
`else
    output logic [7:0]   m_axis_tx_tkeep,
    output logic [63:0]  m_axis_tx_tdata,
`endif
    output logic         m_axis_tx_tvalid,
    output logic         m_axis_tx_tlast,

    output logic         aurora_asy_fifo_almost_full,
    output logic         aurora_frame_fifo_empty,
    output logic         aurora_frame_fifo_prog_empty,
    output logic         aurora_tx_fifo_overflow,
    output logic         aurora_tx_fifo_underflow,

    output logic         Diag_aurora_data_err_out,
    output logic         Diag_aurora_header_err_out,
    output logic         Diag_auroradata_en_rise_flag_out,
    output logic         idle_process_en,
    output logic         view_tx_done,
    output logic         aurora_first_view,
    output logic         crc_error,
    output logic [3:0]   auro_frame_state_test,
    output logic         make_data_p_rst_gtx
);

`ifdef TX_DATA_WIDTH_32
    logic [31:0] aurora_frame_fifo_dout;
    logic [31:0] idle_data_out;
`else
    logic [63:0] aurora_frame_fifo_dout;
    logic [63:0] idle_data_out;
`endif

    logic [127:0] din;
    logic [11:0]  slice_length_min;
    logic [12:0]  prog_empty_thresh;

    logic         aurora_sw_rst;
    logic         crc_rst;
    logic         rst_local;
    logic         rst_local_t_gtx_clk_n;
    logic         rst_idle_process_n;
    logic         rst_idle_frame_gen_n;

    logic         fifo_wr_en;
    logic         fifo_rd_en;
    logic         full;
    logic         valid;
    logic         prog_full;
    logic         wr_rst_busy;
    logic         rd_rst_busy;

    (* ASYNC_REG = "true" *) logic make_data_on_d;
    (* ASYNC_REG = "true" *) logic make_data_on_dd;
    (* ASYNC_REG = "true" *) logic make_data_on_ddd;
    logic [5:0] make_data_dly_cnt;
    logic       make_data_p_edge_gtx;
    logic       make_data_p_rst;
    logic       make_data_dly_cnt_rch;

    (* ASYNC_REG = "true" *) logic rp_back_en_rst_d;
    (* ASYNC_REG = "true" *) logic rp_back_en_rst_dd;

    logic       clear_crc;
    logic       crc_en;
    logic       crc_tx_1_en;
    logic       crc_tx_2_en;
    logic       footer_1_en;
    logic       footer_en;
    logic       gtx_refresh_process_en;
    logic       header_cmd_1_en;
    logic       header_cmd_2_en;
    logic [7:0] header_cnt;
    logic       header_en;
    logic       idle_frame_ind;
    logic       idle_header_ctl_word_en_out;
    logic       idle_process_active_debug_out;
    logic       idle_process_active_out;
    logic       idle_slice_data_en;
    logic       idle_slice_trans_start;
    logic       idle_trig;
    logic       axis_frame_sof;
    logic       slice_cmd_1_en;
    logic       slice_cmd_2_en;
    logic [7:0] slice_cnt;
    logic [9:0] slice_data_cnt;
    logic       view_start_cnt_half;

    assign slice_length_min             = (slice_length_odd < slice_length_even) ? slice_length_odd : slice_length_even;
    assign aurora_asy_fifo_almost_full  = prog_full;
    assign aurora_sw_rst                = aurora_tx_reset;
    assign fifo_wr_en                   = user_r_valid;
    assign crc_rst                      = rst_local | aurora_tx_reset;

    // Synchronize make_data_on to GTX clock and stretch a local reset window.
    always_ff @(posedge gtx_user_clk_in) begin
        make_data_on_d   <= make_data_on;
        make_data_on_dd  <= make_data_on_d;
        make_data_on_ddd <= make_data_on_dd;
    end

    assign make_data_p_edge_gtx = make_data_on_dd && (~make_data_on_ddd);
    assign make_data_dly_cnt_rch = make_data_dly_cnt[5];
    assign make_data_p_rst       = ~make_data_dly_cnt_rch;
    assign make_data_p_rst_gtx   = make_data_p_rst;

    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_tx_reset) begin
            make_data_dly_cnt <= '0;
        end
        else if (make_data_p_edge_gtx) begin
            make_data_dly_cnt <= '0;
        end
        else if (~make_data_dly_cnt_rch) begin
            make_data_dly_cnt <= make_data_dly_cnt + 6'h1;
        end
    end

    // Replay reset is generated in UI clock and used in GTX clock domain.
    always_ff @(posedge gtx_user_clk_in) begin
        rp_back_en_rst_d  <= rp_back_en_rst;
        rp_back_en_rst_dd <= rp_back_en_rst_d;
    end

    assign rst_local_t_gtx_clk_n = rst_local_t_gtx_clk & (~rp_back_en_rst_dd) & (~make_data_p_rst);
    assign rst_local             = ~rst_local_t_gtx_clk_n;
    assign rst_idle_process_n    = rst_local_t_gtx_clk & (~make_data_p_rst);
    assign rst_idle_frame_gen_n  = ~rst_local_t_gtx_clk;

`ifdef TX_DATA_WIDTH_32
    assign din               = {user_r_data[31:0], user_r_data[63:32], user_r_data[95:64], user_r_data[127:96]};
    assign prog_empty_thresh = {2'h0, slice_length_min[11:1]};
`else
    assign din               = {user_r_data[63:0], user_r_data[127:64]};
    assign prog_empty_thresh = {3'h0, slice_length_min[11:2]};
`endif

`ifdef TX_DATA_WIDTH_32
    aurora_frame_fifo_32 aurora_frame_fifo (
`else
    aurora_frame_fifo aurora_frame_fifo (
`endif
        .rst               (rst_local),
        .wr_clk            (ui_clk),
        .rd_clk            (gtx_user_clk_in),
        .din               (din),
        .wr_en             (fifo_wr_en),
        .rd_en             (fifo_rd_en),
        .prog_empty_thresh (prog_empty_thresh[12:0]),

        .dout              (aurora_frame_fifo_dout),
        .full              (full),
        .empty             (aurora_frame_fifo_empty),
        .valid             (valid),
        .prog_full         (prog_full),
        .prog_empty        (aurora_frame_fifo_prog_empty),
        .wr_rst_busy       (wr_rst_busy),
        .rd_rst_busy       (rd_rst_busy)
    );

    trans_frame_type_ctrl trans_frame_type_ctrl (
        .aurora_sw_rst              (aurora_sw_rst),
        .rst_local_t_gtx_clk        (rst_idle_process_n),
        .gtx_user_clk_in            (gtx_user_clk_in),
        .sampling_data_on           (sampling_data_on),
        .view_start_cnt_half        (view_start_cnt_half),
        .view_tx_done               (view_tx_done),
        .gtx_clk_last_view_trans_fsh(gtx_clk_last_view_trans_fsh),

        .idle_process_en            (idle_process_en)
    );

    aurora_tx_frame aurora_tx_frame (
        .ui_clk                      (ui_clk),
        .ddr_user_rst                (ddr_user_rst),
        .console_reset_in            (console_reset_in),
        .aurora_sw_rst               (aurora_sw_rst),
        .TX_CHANNEL_UP_in            (TX_CHANNEL_UP_in),
        .rst_local_t_ddr_clk         (rst_local_t_ddr_clk),
        .rst_local_t_gtx_clk         (rst_local_t_gtx_clk_n),
        .refresh_process_en          (refresh_process_en),
        .gtx_user_clk_in             (gtx_user_clk_in),
        .clk_40mhz_1us_in            (clk_40mhz_1us_in),
        .Fault_inject_en             (Fault_inject_en),
        .slice_sel                   (slice_sel[8:0]),
        .m_axis_tx_tready            (m_axis_tx_tready),
        .aurora_frame_fifo_prog_empty(aurora_frame_fifo_prog_empty),
        .aurora_frame_fifo_empty     (aurora_frame_fifo_empty),
        .idle_process_en             (idle_process_en),
        .idle_trig                   (idle_trig),
`ifdef TX_DATA_WIDTH_32
        .aurora_frame_fifo_dout      (aurora_frame_fifo_dout[31:0]),
        .idle_data_out               (idle_data_out[31:0]),
`else
        .aurora_frame_fifo_dout      (aurora_frame_fifo_dout[63:0]),
        .idle_data_out               (idle_data_out[63:0]),
`endif
        .slice_length_odd            (slice_length_odd[11:0]),
        .slice_length_even           (slice_length_even[11:0]),

`ifdef TX_DATA_WIDTH_32
        .m_axis_tx_tkeep             (m_axis_tx_tkeep[3:0]),
        .m_axis_tx_tdata             (m_axis_tx_tdata[31:0]),
`else
        .m_axis_tx_tkeep             (m_axis_tx_tkeep[7:0]),
        .m_axis_tx_tdata             (m_axis_tx_tdata[63:0]),
`endif
        .Diag_aurora_data_err_out    (Diag_aurora_data_err_out),
        .Diag_aurora_header_err_out  (Diag_aurora_header_err_out),
        .Diag_auroradata_en_rise_flag_out(Diag_auroradata_en_rise_flag_out),
        .m_axis_tx_tvalid            (m_axis_tx_tvalid),
        .m_axis_tx_tlast             (m_axis_tx_tlast),
        .axis_frame_sof              (axis_frame_sof),
        .fifo_rd_en                  (fifo_rd_en),
        .view_tx_done                (view_tx_done),
        .idle_frame_ind              (idle_frame_ind),
        .header_cnt                  (header_cnt[7:0]),
        .slice_cnt                   (slice_cnt[7:0]),
        .slice_data_cnt              (slice_data_cnt[9:0]),
        .header_en                   (header_en),
        .header_cmd_1_en             (header_cmd_1_en),
        .header_cmd_2_en             (header_cmd_2_en),
        .footer_en                   (footer_en),
        .footer_1_en                 (footer_1_en),
        .slice_cmd_1_en              (slice_cmd_1_en),
        .slice_cmd_2_en              (slice_cmd_2_en),
        .crc_tx_2_en                 (crc_tx_2_en),
        .crc_tx_1_en                 (crc_tx_1_en),
        .clear_crc                   (clear_crc),
        .crc_en                      (crc_en),
        .idle_slice_data_en          (idle_slice_data_en),
        .view_start_cnt_half         (view_start_cnt_half),
        .aurora_first_view           (aurora_first_view),
        .gtx_refresh_process_en      (gtx_refresh_process_en),
        .auro_frame_state_test       (auro_frame_state_test[3:0])
    );

`ifdef TX_DATA_WIDTH_32
    idle_frame_gen_32 idle_frame_gen (
`else
    idle_frame_gen idle_frame_gen (
`endif
        .aurora_sw_rst               (aurora_sw_rst),
        .rst_local                   (rst_idle_frame_gen_n),
        .gtx_user_clk_in             (gtx_user_clk_in),
        .idle_process_en             (idle_process_en),
        .conv                        (conv),
        .DMS_Type                    (DMS_Type[7:0]),
        .L_FTP_temp                  (L_FTP_temp[15:0]),
        .R_FTP_temp                  (R_FTP_temp[15:0]),
        .idle_frame_ind              (idle_frame_ind),
        .header_cnt                  (header_cnt[7:0]),
        .slice_cnt                   (slice_cnt[7:0]),
`ifdef TX_DATA_WIDTH_32
        .slice_data_cnt              (slice_data_cnt[9:0]),
`endif
        .header_en                   (header_en),
        .idle_slice_data_en          (idle_slice_data_en),
        .header_cmd_1_en             (header_cmd_1_en),
        .header_cmd_2_en             (header_cmd_2_en),
        .footer_en                   (footer_en),
`ifdef TX_DATA_WIDTH_32
        .footer_1_en                 (footer_1_en),
`endif
        .slice_cmd_1_en              (slice_cmd_1_en),
        .slice_cmd_2_en              (slice_cmd_2_en),
        .crc_tx_1_en                 (crc_tx_1_en),
        .crc_tx_2_en                 (crc_tx_2_en),
        .clear_crc                   (clear_crc),
        .crc_en                      (crc_en),
        .gtx_refresh_process_en      (gtx_refresh_process_en),

        .idle_process_active_out     (idle_process_active_out),
        .idle_process_active_debug_out(idle_process_active_debug_out),
        .idle_header_ctl_word_en_out (idle_header_ctl_word_en_out),
        .idle_slice_trans_start      (idle_slice_trans_start),
        .idle_trig                   (idle_trig),
`ifdef TX_DATA_WIDTH_32
        .idle_data_out               (idle_data_out[31:0])
`else
        .idle_data_out               (idle_data_out[63:0])
`endif
    );

`ifdef TX_DATA_WIDTH_32
    crc_chk_32 crc_chk (
        .axis_frame_sof   (axis_frame_sof),
        .m_axis_tx_tlast  (m_axis_tx_tlast),
        .m_axis_tx_tvalid (m_axis_tx_tvalid),
        .m_axis_tx_tready (m_axis_tx_tready),
        .m_axis_tx_tdata  (m_axis_tx_tdata[31:0]),
        .crc_rst          (crc_rst),
        .gtx_user_clk_in  (gtx_user_clk_in),
        .crc_error        (crc_error)
    );
`else
    crc_chk crc_chk (
        .axis_frame_sof   (axis_frame_sof),
        .m_axis_tx_tlast  (m_axis_tx_tlast),
        .m_axis_tx_tvalid (m_axis_tx_tvalid),
        .m_axis_tx_tready (m_axis_tx_tready),
        .m_axis_tx_tdata  (m_axis_tx_tdata[63:0]),
        .crc_rst          (crc_rst),
        .gtx_user_clk_in  (gtx_user_clk_in),
        .crc_error        (crc_error)
    );
`endif

    // FIFO overflow and underflow monitors are one-cycle diagnostic pulses.
    always_ff @(posedge ui_clk) begin
        if (ddr_user_rst || rst_local_t_ddr_clk || rp_back_en_rst) begin
            aurora_tx_fifo_overflow <= 1'b0;
        end
        else if (full && fifo_wr_en) begin
            aurora_tx_fifo_overflow <= 1'b1;
        end
        else begin
            aurora_tx_fifo_overflow <= 1'b0;
        end
    end

    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_tx_reset) begin
            aurora_tx_fifo_underflow <= 1'b0;
        end
        else if (rst_local) begin
            aurora_tx_fifo_underflow <= 1'b0;
        end
        else if (aurora_frame_fifo_empty && fifo_rd_en) begin
            aurora_tx_fifo_underflow <= 1'b1;
        end
        else begin
            aurora_tx_fifo_underflow <= 1'b0;
        end
    end

endmodule
