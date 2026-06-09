`timescale 1ns/1ps
`include "h80_define.sv"

module ddr_cache_and_frame_gen #(
    parameter ADDR_WIDTH                  = 24,
    parameter SYS_CLK2UI_CLK_PULSE_WIDTH = 'h8,
    parameter GTX_CLK2UI_CLK_PULSE_WIDTH = 'h8,
    parameter UI_CLK2SYS_CLK_PULSE_WIDTH = 'h8,
    parameter UI_CLK2GTX_CLK_PULSE_WIDTH = 'hc
) (
    input  logic                  ui_clk,
    input  logic                  ddr_user_rst,
    input  logic                  rst_local_t_ddr_clk,

    input  logic                  gtx_user_clk_in,
    input  logic                  rst_local_t_gtx_clk,

    input  logic                  clk_sysclk_in,
    input  logic                  sys_rst,
    input  logic                  clk_40mhz_1us_in,
    input  logic                  clk_40m,
    input  logic                  rst_40m,

    input  logic                  ddr_rd_empty,
    input  logic [127:0]          user_r_data,
    input  logic                  user_r_valid,

    input  logic                  make_data_on,
    input  logic                  sampling_data_on,
    input  logic                  conv,
    input  logic [15:0]           view_size,
    input  logic                  view_Reading_Done,
    input  logic                  last_view_wr_done,

    input  logic                  aurora_tx_reset_n,
    input  logic                  TX_CHANNEL_UP_in,
    input  logic                  tx_dst_rdy_n_in,
    input  logic                  console_reset_in,
    input  logic                  Fault_inject_en,

    input  logic [7:0]            DMS_Type,
    input  logic [15:0]           L_FTP_temp,
    input  logic [15:0]           R_FTP_temp,
    input  logic [8:0]            slice_sel,
    input  logic [11:0]           slice_length_odd,
    input  logic [11:0]           slice_length_even,

    input  logic                  comm_ok_disable,
    input  logic                  comm_ok,
    input  logic                  dms_err_rst,

`ifdef TX_DATA_WIDTH_32
    output logic [1:0]            tx_rem_out,
    output logic [31:0]           tx_d_out,
`else
    output logic [2:0]            tx_rem_out,
    output logic [63:0]           tx_d_out,
`endif
    output logic                  tx_sof_n_out,
    output logic                  tx_eof_n_out,
    output logic                  tx_src_rdy_n_out,

    output logic                  ddr_rd_req,
    output logic                  req_stop,
    output logic                  rp_back_en,
    output logic [ADDR_WIDTH-1:0] rp_back_view_addr,
    output logic                  sysclk_rp_back_en,

    output logic                  aurora_tx_fifo_overflow,
    output logic                  aurora_tx_fifo_underflow,
    output logic                  aurora_asy_fifo_almost_full,
    output logic                  Diag_aurora_data_err_out,
    output logic                  Diag_aurora_header_err_out,
    output logic                  Diag_auroradata_en_rise_flag_out,
    output logic                  aurora_first_view,
    output logic                  crc_error,

    output logic                  refresh_process_en,
    output logic [1:0]            rd_cache_state,
    output logic                  rd_wr_num_equ,
    output logic [3:0]            cache_tp,
    output logic [15:0]           auro_tx_status_reg_out,
    output logic                  idle_process_en_out
);

    logic [3:0] auro_frame_state_test;

    logic       aurora_frame_fifo_empty;
    logic       aurora_frame_fifo_prog_empty;
    logic       aurora_tx_reset;

    logic       idle_process_en;
    logic       idle_process_en_rcom_cdc_to_d;
    logic       idle_process_en_dd;

    logic       last_view_trans_ok;
    logic       make_data_p_rst_gtx;
    logic       rp_back_cnt_add_en;
    logic       rp_back_en_i;
    logic       rp_back_en_rst;
    logic       sample_frame_rd_done;
    logic       uiclk_pulse_1us;
    logic       view_trans_ok;
    logic       view_tx_done;

    logic       ui_clk_rd_view_pulse;
    logic       gtx_clk_last_view_trans_fsh;

    assign aurora_tx_reset = ~aurora_tx_reset_n;
    assign cache_tp        = {2'h0, last_view_trans_ok, 1'h0};

    // CDC: idle mode indicator from GTX clock to DDR UI clock.
    always_ff @(posedge ui_clk) begin
        if (ddr_user_rst) begin
            idle_process_en_rcom_cdc_to_d <= 1'b0;
            idle_process_en_dd            <= 1'b0;
        end
        else begin
            idle_process_en_rcom_cdc_to_d <= idle_process_en;
            idle_process_en_dd            <= idle_process_en_rcom_cdc_to_d;
        end
    end

    rd_cache_ctrl #(
        .ADDR_WIDTH                 (ADDR_WIDTH),
        .GTX_CLK2UI_CLK_PULSE_WIDTH (GTX_CLK2UI_CLK_PULSE_WIDTH),
        .SYS_CLK2UI_CLK_PULSE_WIDTH (SYS_CLK2UI_CLK_PULSE_WIDTH),
        .UI_CLK2GTX_CLK_PULSE_WIDTH (UI_CLK2GTX_CLK_PULSE_WIDTH)
    ) rd_cache_ctrl (
        .ui_clk                  (ui_clk),
        .ddr_user_rst            (ddr_user_rst),
        .rst_local_t_ddr_clk     (rst_local_t_ddr_clk),
        .clk_sysclk_in           (clk_sysclk_in),
        .sys_rst                 (sys_rst),

        .view_Reading_Done       (view_Reading_Done),
        .last_view_wr_done       (last_view_wr_done),
        .view_size               (view_size[15:0]),
        .user_r_valid            (user_r_valid),

        .refresh_process_en      (refresh_process_en),
        .TX_CHANNEL_UP_in        (TX_CHANNEL_UP_in),
        .aurora_asy_fifo_almost_full(aurora_asy_fifo_almost_full),
        .ddr_rd_empty            (ddr_rd_empty),
        .make_data_on            (make_data_on),
        .idle_process_en         (idle_process_en_dd),

        .rp_back_en_i            (rp_back_en_i),
        .rp_back_en_rst          (rp_back_en_rst),
        .uiclk_pulse_1us         (uiclk_pulse_1us),
        .view_trans_ok           (view_trans_ok),

        .ddr_rd_req              (ddr_rd_req),
        .req_stop                (req_stop),
        .rp_back_view_addr       (rp_back_view_addr[ADDR_WIDTH-1:0]),
        .last_view_trans_ok      (last_view_trans_ok),
        .sample_frame_rd_done    (sample_frame_rd_done),
        .rd_cache_state          (rd_cache_state[1:0]),
        .rd_wr_num_equ           (rd_wr_num_equ)
    );

    aurora_tx_top aurora_tx_top (
        .user_r_data              (user_r_data[127:0]),
        .user_r_valid             (user_r_valid),
        .ui_clk                   (ui_clk),
        .ddr_user_rst             (ddr_user_rst),
        .console_reset_in         (console_reset_in),
        .aurora_tx_reset          (aurora_tx_reset),
        .TX_CHANNEL_UP_in         (TX_CHANNEL_UP_in),
        .rst_local_t_ddr_clk      (rst_local_t_ddr_clk),
        .rst_local_t_gtx_clk      (rst_local_t_gtx_clk),
        .refresh_process_en       (refresh_process_en),
        .gtx_user_clk_in          (gtx_user_clk_in),
        .clk_40mhz_1us_in         (clk_40mhz_1us_in),
        .Fault_inject_en          (Fault_inject_en),
        .slice_sel                (slice_sel[8:0]),
        .tx_dst_rdy_n_in          (tx_dst_rdy_n_in),
        .DMS_Type                 (DMS_Type[7:0]),
        .L_FTP_temp               (L_FTP_temp[15:0]),
        .R_FTP_temp               (R_FTP_temp[15:0]),
        .make_data_on             (make_data_on),
        .sampling_data_on         (sampling_data_on),
        .conv                     (conv),
        .gtx_clk_last_view_trans_fsh(gtx_clk_last_view_trans_fsh),
        .rp_back_en_rst           (rp_back_en_rst),
        .slice_length_odd         (slice_length_odd[11:0]),
        .slice_length_even        (slice_length_even[11:0]),

`ifdef TX_DATA_WIDTH_32
        .tx_rem_out               (tx_rem_out[1:0]),
        .tx_d_out                 (tx_d_out[31:0]),
`else
        .tx_rem_out               (tx_rem_out[2:0]),
        .tx_d_out                 (tx_d_out[63:0]),
`endif
        .aurora_asy_fifo_almost_full(aurora_asy_fifo_almost_full),
        .Diag_aurora_data_err_out (Diag_aurora_data_err_out),
        .Diag_aurora_header_err_out(Diag_aurora_header_err_out),
        .Diag_auroradata_en_rise_flag_out(Diag_auroradata_en_rise_flag_out),
        .tx_sof_n_out             (tx_sof_n_out),
        .tx_eof_n_out             (tx_eof_n_out),
        .tx_src_rdy_n_out         (tx_src_rdy_n_out),
        .aurora_tx_fifo_overflow  (aurora_tx_fifo_overflow),
        .aurora_tx_fifo_underflow (aurora_tx_fifo_underflow),
        .idle_process_en          (idle_process_en),
        .view_tx_done             (view_tx_done),
        .aurora_first_view        (aurora_first_view),
        .crc_error                (crc_error),
        .auro_frame_state_test    (auro_frame_state_test[3:0]),
        .make_data_p_rst_gtx      (make_data_p_rst_gtx),
        .aurora_frame_fifo_empty  (aurora_frame_fifo_empty),
        .aurora_frame_fifo_prog_empty(aurora_frame_fifo_prog_empty)
    );

    commok_check #(
        .ADDR_WIDTH (ADDR_WIDTH)
    ) commok_check (
        .ui_clk                  (ui_clk),
        .ddr_user_rst            (ddr_user_rst),
        .rst_local_t_ddr_clk     (rst_local_t_ddr_clk),
        .clk_40mhz_1us_in        (clk_40mhz_1us_in),
        .comm_ok_disable         (comm_ok_disable),
        .comm_ok                 (comm_ok),
        .ui_clk_rd_view_pulse    (ui_clk_rd_view_pulse),
        .sample_frame_rd_done    (sample_frame_rd_done),
        .idle_process_en         (idle_process_en_dd),

        .rp_back_en_rst          (rp_back_en_rst),
        .rp_back_en              (rp_back_en),
        .rp_back_en_i            (rp_back_en_i),
        .rp_back_cnt_add_en      (rp_back_cnt_add_en),
        .view_trans_ok           (view_trans_ok),
        .refresh_process_en      (refresh_process_en),
        .uiclk_pulse_1us         (uiclk_pulse_1us)
    );

    cross_clk_pulse #(
        .PULSE_WIDTH (UI_CLK2SYS_CLK_PULSE_WIDTH)
    ) rp_back_en_sys_gen_dut (
        .i     (rp_back_cnt_add_en),
        .i_clk (ui_clk),
        .i_rst (ddr_user_rst),
        .o_clk (clk_sysclk_in),
        .o_rst (sys_rst),
        .o     (sysclk_rp_back_en)
    );

    cross_clk_pulse #(
        .PULSE_WIDTH (UI_CLK2GTX_CLK_PULSE_WIDTH)
    ) last_view_trans_fsh_gen_dut (
        .i     (last_view_trans_ok),
        .i_clk (ui_clk),
        .i_rst (ddr_user_rst),
        .o_clk (gtx_user_clk_in),
        .o_rst (aurora_tx_reset),
        .o     (gtx_clk_last_view_trans_fsh)
    );

    cross_clk_pulse #(
        .PULSE_WIDTH (GTX_CLK2UI_CLK_PULSE_WIDTH)
    ) rd_view_pulse_gen_dut (
        .i     (view_tx_done),
        .i_clk (gtx_user_clk_in),
        .i_rst (aurora_tx_reset),
        .o_clk (ui_clk),
        .o_rst (ddr_user_rst),
        .o     (ui_clk_rd_view_pulse)
    );

    gtx_status_reg gtx_status_reg (
        .clk_40m                      (clk_40m),
        .rst_40m                      (rst_40m),
        .dms_err_rst                  (dms_err_rst),
        .gtx_user_clk_in              (gtx_user_clk_in),
        .aurora_tx_reset              (aurora_tx_reset),
        .make_data_p_rst_gtx          (make_data_p_rst_gtx),
        .aurora_tx_fifo_underflow     (aurora_tx_fifo_underflow),
        .idle_process_en              (idle_process_en),
        .aurora_frame_fifo_prog_empty (aurora_frame_fifo_prog_empty),
        .aurora_frame_fifo_empty      (aurora_frame_fifo_empty),
        .crc_error                    (crc_error),
        .auro_frame_state_test        (auro_frame_state_test[3:0]),
        .Diag_aurora_data_err_out     (Diag_aurora_data_err_out),
        .Diag_aurora_header_err_out   (Diag_aurora_header_err_out),
        .Diag_auroradata_en_rise_flag_out(Diag_auroradata_en_rise_flag_out),

        .auro_tx_status_reg_out       (auro_tx_status_reg_out[15:0]),
        .idle_process_en_out          (idle_process_en_out)
    );

endmodule
