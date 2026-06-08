// Aurora TX frame generator.
// Generates header, slice, idle, and refresh frames from DDR cache FIFO data.
`include "h80_define.sv"
`timescale 1ns/1ps
module aurora_tx_frame (
    input  logic        ui_clk,
    input  logic        ddr_user_rst,
    input  logic        gtx_user_clk_in,
    input  logic        aurora_sw_rst,
    input  logic        rst_local_t_ddr_clk,
    input  logic        rst_local_t_gtx_clk,

    input  logic        console_reset_in,
    input  logic        TX_CHANNEL_UP_in,
    input  logic        tx_dst_rdy_n_in,
    input  logic        refresh_process_en,
    input  logic        clk_40mhz_1us_in,
    input  logic        Fault_inject_en,

    input  logic [8:0]  slice_sel,
    input  logic [11:0] slice_length_odd,
    input  logic [11:0] slice_length_even,

    input  logic        aurora_frame_fifo_prog_empty,
    input  logic        aurora_frame_fifo_empty,

    input  logic        idle_process_en,
    input  logic        idle_trig,
`ifdef TX_DATA_WIDTH_32
    input  logic [31:0] aurora_frame_fifo_dout,
    input  logic [31:0] idle_data_out,
    output logic [1:0]  tx_rem_out,
    output logic [31:0] tx_d_out,
`else
    input  logic [63:0] aurora_frame_fifo_dout,
    input  logic [63:0] idle_data_out,
    output logic [2:0]  tx_rem_out,
    output logic [63:0] tx_d_out,
`endif

    output logic        tx_sof_n_out,
    output logic        tx_eof_n_out,
    output logic        tx_src_rdy_n_out,
    output logic        fifo_rd_en,

    output logic        view_tx_done,
    output logic        idle_frame_ind,
    output logic        view_start_cnt_half,
    output logic        aurora_first_view,

    output logic [7:0]  header_cnt,
    output logic [7:0]  slice_cnt,
    output logic [9:0]  slice_data_cnt,
    output logic        header_en,
    output logic        header_cmd_1_en,
    output logic        header_cmd_2_en,
    output logic        footer_en,
    output logic        footer_1_en,
    output logic        slice_cmd_1_en,
    output logic        slice_cmd_2_en,

    output logic        crc_tx_2_en,
    output logic        crc_tx_1_en,
    output logic        clear_crc,
    output logic        crc_en,
    output logic        idle_slice_data_en,
    output logic        gtx_refresh_process_en,

    output logic        Diag_aurora_data_err_out,
    output logic        Diag_aurora_header_err_out,
    output logic        Diag_auroradata_en_rise_flag_out,
    output logic [3:0]  auro_frame_state_test
);

    // -------------------------------------------------------------------------
    // State, Constants, and Width-Dependent Limits
    // -------------------------------------------------------------------------
    typedef enum logic [3:0] {
        IDLE               = 4'h0,
        HEAD_SOF_PRE_STA   = 4'h1,
        HEAD_SOF_PRE_STA2  = 4'h2,
        HEAD_SOF_STA       = 4'h3,
        HEAD_DATA_STA      = 4'h4,
        HEAD_EOF_STA       = 4'h5,
        WAIT_SLICE_STA     = 4'h6,
        SLICE_SOF_PRE_STA  = 4'h7,
        SLICE_SOF_PRE_STA2 = 4'h8,
        SLICE_SOF_STA      = 4'h9,
        SLICE_DATA_STA     = 4'ha,
        SLICE_EOF_STA      = 4'hb,
        SLICE_DONE_STA     = 4'hc,
        REFRESH_WAIT       = 4'hd,
        REFRESH_DATA       = 4'he
    } auro_frame_state_t;

    logic [2:0]  sof_pre_cnt_lim;
    logic [1:0]  sof_cnt_lim;
    logic [1:0]  eof_cnt_lim;
    logic [7:0]  header_cnt_lim;
    logic [9:0]  slice_data_cnt_lim;

    // -------------------------------------------------------------------------
    // Local Signals
    // -------------------------------------------------------------------------
    (* mark_debug="true" *) auro_frame_state_t auro_frame_state;
    auro_frame_state_t auro_frame_state_next;

    logic [11:0] slice_length;
    logic [11:0] idle_slice_length;
    logic [11:0] slice_length_tx;

    logic tx_dst_rdy;
    logic rst_local;
    logic fifo_reset;

    logic rst_local_t_ddr_clk_delay;
    logic rst_local_t_ddr_clk_1d;
    logic rst_local_t_ddr_clk_2d;
    logic rst_local_t_ddr_clk_3d;
    logic rst_local_t_ddr_clk_4d;
    logic rst_local_t_ddr_clk_5d;
    logic rst_local_t_gtx_clk_d;

    logic console_reset_in_d;
    logic console_reset_in_dd;
    logic console_reset_in_ddd;
    logic tx_channel_up_d;
    logic tx_channel_up_dd;
    logic tx_channel_up_ddd;

    (* ASYNC_REG = "true" *) logic refresh_process_en_rcom_cdc_to_d;
    (* ASYNC_REG = "true" *) logic refresh_process_en_dd;
    (* ASYNC_REG = "true" *) logic refresh_process_en_ddd;

    logic pulse_1us_d;
    logic pulse_1us_dd;
    logic pulse_1us_ddd;
    logic pulse_1us_edge;
    logic refresh_trigger_pulse;

    logic [15:0] fault_50ms_cnt;
    logic        fault_50ms_cnt_rch;
    logic        fault_gen_r;
    logic        fault_gen_set;
    logic        fault_gen_clr;
    logic        fault_gen_pulse;
    logic        fault_gen_inject_ind;

    logic [2:0]  view_start_dly_cnt;
    logic        view_start_dly_cnt_rch;
    logic [9:0]  view_start_to_start_cnt;
    logic        view_start_to_start_cnt_rch;
    logic        trans_idle_frame_trig;
    logic        trans_normal_frame_trig;
    logic        trans_frame_trig;
    logic        console_reset_enable;

    logic [2:0] sof_pre_cnt;
    logic       sof_pre_cnt_rch;
    logic [1:0] sof_cnt;
    logic       sof_cnt_rch;
    logic [1:0] eof_cnt;
    logic       eof_cnt_rch;
    logic       header_cnt_rch;

    logic        slice_data_cnt_add_normal;
    logic        slice_data_cnt_add_idle;
    logic        slice_data_cnt_add_en;
    logic        slice_data_cnt_rch;
    logic [8:0]  slice_sel_r;
    logic        add_slice_cnt;
    logic        slice_cnt_lim;
    logic        slice_cnt_rch;
    logic [3:0]  ref_data_cnt;
    logic        ref_data_cnt_rch;
    logic [3:0]  slice_interview_cnt;
    logic        slice_interview_cnt_rch;

    logic tx_sof_out;
    logic tx_eof_out;
    logic tx_src_rdy_out;
    logic tx_sof_refresh;
    logic tx_eof_refresh;
    logic tx_src_rdy_refresh;

    logic fifo_rd_en_t;
    logic data_valid_rd_en;
    logic fifo_rd_en_dly;

    logic crc_en_t;
    logic clear_crc_t;
    logic idle_slice_data_en_t;

    logic aurora_frame_ok;
    logic data_sof;
    logic head_sof;
    logic set_Diag_aurora_data_err_out;
    logic set_Diag_aurora_header_err_out;
    logic aurora_first_view_temp;
    logic [15:0] aurora_idle_cnt;

    logic aurora_data_heade_ok;
    logic latch_frame_kind;
    logic slice_data_en;

`ifdef TX_DATA_WIDTH_32
    logic [31:0] tx_d_out_t;
`else
    logic [63:0] tx_d_out_t;
`endif

`ifdef TX_DATA_WIDTH_32
    assign sof_pre_cnt_lim    = 'd1;
    assign sof_cnt_lim        = 'd1;
    assign eof_cnt_lim        = 'd1;
    assign header_cnt_lim     = 'd61;
    assign slice_data_cnt_lim = (slice_length_tx[11:1] + 1'h1);
`else
    assign sof_pre_cnt_lim    = 'd0;
    assign sof_cnt_lim        = 'd0;
    assign eof_cnt_lim        = 'd0;
    assign header_cnt_lim     = 'd30;
    assign slice_data_cnt_lim = slice_length_tx[11:2];
`endif

    // -------------------------------------------------------------------------
    // CDC, Reset, and Channel Ready
    // -------------------------------------------------------------------------
    always_ff @(posedge ui_clk) begin
        rst_local_t_ddr_clk_1d    <= rst_local_t_ddr_clk;
        rst_local_t_ddr_clk_2d    <= rst_local_t_ddr_clk_1d;
        rst_local_t_ddr_clk_3d    <= rst_local_t_ddr_clk_2d;
        rst_local_t_ddr_clk_4d    <= rst_local_t_ddr_clk_3d;
        rst_local_t_ddr_clk_5d    <= rst_local_t_ddr_clk_4d;
        rst_local_t_ddr_clk_delay <= rst_local_t_ddr_clk_5d;
    end

    always_ff @(posedge gtx_user_clk_in) begin
        console_reset_in_d   <= console_reset_in;
        console_reset_in_dd  <= console_reset_in_d;
        console_reset_in_ddd <= console_reset_in_dd;
    end

    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            tx_channel_up_d   <= 'h0;
            tx_channel_up_dd  <= 'h0;
            tx_channel_up_ddd <= 'h0;
        end
        else begin
            tx_channel_up_d   <= TX_CHANNEL_UP_in;
            tx_channel_up_dd  <= tx_channel_up_d;
            tx_channel_up_ddd <= tx_channel_up_dd;
        end
    end

    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            rst_local_t_gtx_clk_d <= 'h1;
        end
        else begin
            rst_local_t_gtx_clk_d <= rst_local_t_gtx_clk;
        end
    end

    assign tx_dst_rdy = (~tx_dst_rdy_n_in) & tx_channel_up_ddd;
    assign rst_local  = ~rst_local_t_gtx_clk_d;
    assign fifo_reset = ddr_user_rst | rst_local_t_ddr_clk_delay;

    // -------------------------------------------------------------------------
    // Refresh Synchronization and 1us Timing
    // -------------------------------------------------------------------------
    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            refresh_process_en_rcom_cdc_to_d <= 'h0;
            refresh_process_en_dd            <= 'h0;
            refresh_process_en_ddd           <= 'h0;
        end
        else begin
            refresh_process_en_rcom_cdc_to_d <= refresh_process_en;
            refresh_process_en_dd            <= refresh_process_en_rcom_cdc_to_d;
            refresh_process_en_ddd           <= refresh_process_en_dd;
        end
    end

    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            pulse_1us_d   <= 'h0;
            pulse_1us_dd  <= 'h0;
            pulse_1us_ddd <= 'h0;
        end
        else begin
            pulse_1us_d   <= clk_40mhz_1us_in;
            pulse_1us_dd  <= pulse_1us_d;
            pulse_1us_ddd <= pulse_1us_dd;
        end
    end

    assign gtx_refresh_process_en = refresh_process_en_dd;
    assign pulse_1us_edge         = pulse_1us_dd & (~pulse_1us_ddd);
    assign refresh_trigger_pulse  = gtx_refresh_process_en & pulse_1us_edge;

    // -------------------------------------------------------------------------
    // Fault Injection
    // -------------------------------------------------------------------------
    assign fault_50ms_cnt_rch = (fault_50ms_cnt == 'hC800);  // 50us
    assign fault_gen_set      = fault_gen_r & (slice_data_cnt == 'h10);
    assign fault_gen_clr      = fault_gen_r & (slice_data_cnt == 'h20);
    assign fault_gen_inject_ind = fault_gen_pulse & (slice_data_cnt == 'h18);

    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            fault_50ms_cnt <= 'h0;
        end
        else if (~Fault_inject_en || fault_50ms_cnt_rch) begin
            fault_50ms_cnt <= 'h0;
        end
        else if (pulse_1us_edge) begin
            fault_50ms_cnt <= fault_50ms_cnt + 1'h1;
        end
    end

    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            fault_gen_r <= 'h0;
        end
        else if (fault_50ms_cnt_rch) begin
            fault_gen_r <= 'h1;
        end
        else if (fault_gen_clr) begin
            fault_gen_r <= 'h0;
        end
    end

    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            fault_gen_pulse <= 'h0;
        end
        else if (fault_gen_set) begin
            fault_gen_pulse <= 'h1;
        end
        else if (fault_gen_clr) begin
            fault_gen_pulse <= 'h0;
        end
    end

    // -------------------------------------------------------------------------
    // View and Frame Trigger Control
    // -------------------------------------------------------------------------
    assign slice_length      = slice_cnt[0] ? slice_length_even : slice_length_odd;
    assign idle_slice_length = 'h360;
    assign slice_length_tx   = idle_process_en ? idle_slice_length : slice_length;

    assign view_start_cnt_half       = (view_start_dly_cnt == 'h3) & (auro_frame_state == IDLE);
    assign view_start_dly_cnt_rch    = &view_start_dly_cnt;
    assign view_start_to_start_cnt_rch = (view_start_to_start_cnt == 'h50); // 80us

    assign console_reset_enable = (auro_frame_state == IDLE) |
                                  (auro_frame_state == REFRESH_DATA);
    assign trans_idle_frame_trig  = idle_process_en & idle_trig;
    assign trans_normal_frame_trig = (~idle_process_en) &
                                     (~aurora_frame_fifo_prog_empty) &
                                     view_start_to_start_cnt_rch &
                                     view_start_dly_cnt_rch;
    assign trans_frame_trig = trans_idle_frame_trig | trans_normal_frame_trig;
    assign view_tx_done     = (auro_frame_state == SLICE_DONE_STA) && (~rst_local);

    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            view_start_dly_cnt <= 'h0;
        end
        else if (gtx_refresh_process_en || view_tx_done /*|| rst_local*/) begin
            view_start_dly_cnt <= 'h0;
        end
        else if (~view_start_dly_cnt_rch) begin
            view_start_dly_cnt <= view_start_dly_cnt + 1'h1;
        end
    end

    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            view_start_to_start_cnt <= 'h0;
        end
        else if (gtx_refresh_process_en || (auro_frame_state == HEAD_SOF_PRE_STA)) begin
            view_start_to_start_cnt <= 'h0;
        end
        else if (~view_start_to_start_cnt_rch && pulse_1us_edge) begin
            view_start_to_start_cnt <= view_start_to_start_cnt + 1'h1;
        end
    end

    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            idle_frame_ind <= 'h0;
        end
        else if (trans_idle_frame_trig && (auro_frame_state == IDLE)) begin
            idle_frame_ind <= 'h1;
        end
        else if (trans_normal_frame_trig && (auro_frame_state == IDLE)) begin
            idle_frame_ind <= 'h0;
        end
    end

    // -------------------------------------------------------------------------
    // SOF, EOF, Header, Slice, and Refresh Counters
    // -------------------------------------------------------------------------
    assign sof_pre_cnt_rch = (sof_pre_cnt == sof_pre_cnt_lim) & tx_dst_rdy;
    assign sof_cnt_rch     = (sof_cnt == sof_cnt_lim);
    assign eof_cnt_rch     = (eof_cnt == eof_cnt_lim);
    assign header_cnt_rch  = (header_cnt == header_cnt_lim) & tx_dst_rdy;

    assign slice_data_cnt_add_normal = (~aurora_frame_fifo_empty) &
                                       tx_dst_rdy &
                                       (~idle_frame_ind);
    assign slice_data_cnt_add_idle = tx_dst_rdy & idle_frame_ind;
    assign slice_data_cnt_add_en   = slice_data_cnt_add_normal | slice_data_cnt_add_idle;
    assign slice_data_cnt_rch      = (slice_data_cnt == slice_data_cnt_lim) &
                                     (slice_data_cnt_add_normal | slice_data_cnt_add_idle);

    assign latch_frame_kind = (auro_frame_state == HEAD_DATA_STA) &
                              (header_cnt == 'h7) &
                              tx_dst_rdy;
    assign slice_sel_r   = idle_frame_ind ? 8'h20 : slice_sel;
    assign add_slice_cnt = (auro_frame_state == SLICE_EOF_STA) & eof_cnt_rch & tx_dst_rdy;
    assign slice_cnt_lim = (slice_cnt == (slice_sel_r - 1));
    assign slice_cnt_rch = slice_cnt_lim & add_slice_cnt;

    assign ref_data_cnt_rch        = (ref_data_cnt == 'h1) & tx_dst_rdy;
    assign slice_interview_cnt_rch = 'h1;

    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            sof_pre_cnt <= 'h0;
        end
        else if ((auro_frame_state != HEAD_SOF_PRE_STA) &&
                 (auro_frame_state != SLICE_SOF_PRE_STA)) begin
            sof_pre_cnt <= 'h0;
        end
        else if ((~sof_pre_cnt_rch) && tx_dst_rdy) begin
            sof_pre_cnt <= sof_pre_cnt + 1'h1;
        end
    end

    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            sof_cnt <= 'h0;
        end
        else if ((auro_frame_state != HEAD_SOF_STA) &&
                 (auro_frame_state != SLICE_SOF_STA)) begin
            sof_cnt <= 'h0;
        end
        else if ((~sof_cnt_rch) && tx_dst_rdy) begin
            sof_cnt <= sof_cnt + 1'h1;
        end
    end

    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            eof_cnt <= 'h0;
        end
        else if ((auro_frame_state != HEAD_EOF_STA) &&
                 (auro_frame_state != SLICE_EOF_STA)) begin
            eof_cnt <= 'h0;
        end
        else if ((~eof_cnt_rch) && tx_dst_rdy) begin
            eof_cnt <= eof_cnt + 1'h1;
        end
    end

    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            header_cnt <= 'h0;
        end
        else if (auro_frame_state != HEAD_DATA_STA) begin
            header_cnt <= 'h0;
        end
        else if ((~header_cnt_rch) && tx_dst_rdy) begin
            header_cnt <= header_cnt + 1'h1;
        end
    end

    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            slice_data_cnt <= 'h0;
        end
        else if (auro_frame_state != SLICE_DATA_STA) begin
            slice_data_cnt <= 'h0;
        end
        else if ((~slice_data_cnt_rch) && slice_data_cnt_add_en) begin
            slice_data_cnt <= slice_data_cnt + 'h1;
        end
    end

    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            slice_cnt <= 'h0;
        end
        else if (auro_frame_state == IDLE) begin
            slice_cnt <= 'h0;
        end
        else if ((~slice_cnt_lim) && add_slice_cnt) begin
            slice_cnt <= slice_cnt + 1'h1;
        end
    end

    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            ref_data_cnt <= 'h0;
        end
        else if (auro_frame_state != REFRESH_DATA) begin
            ref_data_cnt <= 'h0;
        end
        else if ((~ref_data_cnt_rch) & tx_dst_rdy) begin
            ref_data_cnt <= ref_data_cnt + 1'h1;
        end
    end

    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            slice_interview_cnt <= 'h0;
        end
        else if (auro_frame_state != WAIT_SLICE_STA) begin
            slice_interview_cnt <= 'h0;
        end
        else if (~slice_interview_cnt_rch) begin
            slice_interview_cnt <= slice_interview_cnt + 1'h1;
        end
    end

    // -------------------------------------------------------------------------
    // Frame FSM: State Transition
    // -------------------------------------------------------------------------
    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            auro_frame_state <= IDLE;
        end
        else begin
            auro_frame_state <= auro_frame_state_next;
        end
    end

    // -------------------------------------------------------------------------
    // Frame FSM: Next-State Decision
    // -------------------------------------------------------------------------
    always_comb begin
        auro_frame_state_next = auro_frame_state;

        case (auro_frame_state)
            IDLE: begin
                if (rst_local || (~tx_channel_up_ddd)) begin
                    auro_frame_state_next = IDLE;
                end
                else if (gtx_refresh_process_en) begin
                    auro_frame_state_next = REFRESH_WAIT;
                end
                else if (trans_frame_trig) begin
                    auro_frame_state_next = HEAD_SOF_PRE_STA;
                end
            end

            HEAD_SOF_PRE_STA: begin
                if (rst_local) begin
                    auro_frame_state_next = IDLE;
                end
                else if (sof_pre_cnt_rch) begin
                    auro_frame_state_next = HEAD_SOF_PRE_STA2;
                end
            end

            HEAD_SOF_PRE_STA2: begin
                if (rst_local) begin
                    auro_frame_state_next = IDLE;
                end
                else if (tx_dst_rdy) begin
                    auro_frame_state_next = HEAD_SOF_STA;
                end
            end

            HEAD_SOF_STA: begin
                if (rst_local) begin
                    auro_frame_state_next = HEAD_EOF_STA;
                end
                else if (sof_cnt_rch && tx_dst_rdy) begin
                    auro_frame_state_next = HEAD_DATA_STA;
                end
            end

            HEAD_DATA_STA: begin
                if (header_cnt_rch || rst_local) begin
                    auro_frame_state_next = HEAD_EOF_STA;
                end
            end

            HEAD_EOF_STA: begin
                if (rst_local /*&& (tx_dst_rdy)*/) begin
                    auro_frame_state_next = IDLE;
                end
                else if (eof_cnt_rch && tx_dst_rdy) begin
                    auro_frame_state_next = WAIT_SLICE_STA;
                end
            end

            WAIT_SLICE_STA: begin
                if (rst_local) begin
                    auro_frame_state_next = IDLE;
                end
                else if (((~aurora_frame_fifo_prog_empty) || idle_process_en) &&
                         slice_interview_cnt_rch) begin
                    auro_frame_state_next = SLICE_SOF_PRE_STA;
                end
            end

            SLICE_SOF_PRE_STA: begin
                if (rst_local) begin
                    auro_frame_state_next = IDLE;
                end
                else if (sof_pre_cnt_rch) begin
                    auro_frame_state_next = SLICE_SOF_PRE_STA2;
                end
            end

            SLICE_SOF_PRE_STA2: begin
                if (rst_local) begin
                    auro_frame_state_next = IDLE;
                end
                if (tx_dst_rdy) begin
                    auro_frame_state_next = SLICE_SOF_STA;
                end
            end

            SLICE_SOF_STA: begin
                if (rst_local) begin
                    auro_frame_state_next = SLICE_EOF_STA;
                end
                else if (sof_cnt_rch && tx_dst_rdy) begin
                    auro_frame_state_next = SLICE_DATA_STA;
                end
            end

            SLICE_DATA_STA: begin
                if (slice_data_cnt_rch || rst_local) begin
                    auro_frame_state_next = SLICE_EOF_STA;
                end
            end

            SLICE_EOF_STA: begin
                if (rst_local /*&& (tx_dst_rdy)*/) begin
                    auro_frame_state_next = IDLE;
                end
                else if (eof_cnt_rch && tx_dst_rdy) begin
                    if (slice_cnt_rch) begin
                        auro_frame_state_next = SLICE_DONE_STA;
                    end
                    else begin
                        auro_frame_state_next = WAIT_SLICE_STA;
                    end
                end
            end

            SLICE_DONE_STA: begin
                auro_frame_state_next = IDLE;
            end

            REFRESH_WAIT: begin
                if (~gtx_refresh_process_en) begin
                    auro_frame_state_next = IDLE;
                end
                else if (refresh_trigger_pulse) begin
                    auro_frame_state_next = REFRESH_DATA;
                end
            end

            REFRESH_DATA: begin
                if (ref_data_cnt_rch) begin
                    auro_frame_state_next = REFRESH_WAIT;
                end
            end

            default: begin
                auro_frame_state_next = IDLE;
            end
        endcase
    end

    // -------------------------------------------------------------------------
    // Frame FSM: State Output and Control Assignment
    // -------------------------------------------------------------------------
    assign tx_sof_out = (sof_cnt == 'h0) &
                        ((auro_frame_state == HEAD_SOF_STA) |
                         (auro_frame_state == SLICE_SOF_STA));
    assign tx_eof_out = eof_cnt_rch &
                        ((auro_frame_state == HEAD_EOF_STA) |
                         (auro_frame_state == SLICE_EOF_STA));
    assign aurora_frame_ok = (auro_frame_state == SLICE_DONE_STA) |
                             ((auro_frame_state == REFRESH_DATA) & ref_data_cnt_rch);

    // -------------------------------------------------------------------------
    // FIFO Read and TX Valid Control
    // -------------------------------------------------------------------------
    assign fifo_rd_en_t = tx_dst_rdy &
                          ((auro_frame_state == HEAD_SOF_PRE_STA) |
                           (auro_frame_state == HEAD_SOF_PRE_STA2) |
                           (auro_frame_state == HEAD_SOF_STA) |
                           (auro_frame_state == HEAD_DATA_STA) |
                           (auro_frame_state == SLICE_SOF_PRE_STA) |
                           (auro_frame_state == SLICE_SOF_PRE_STA2) |
                           (auro_frame_state == SLICE_SOF_STA) |
                           ((auro_frame_state == SLICE_EOF_STA) & (~eof_cnt_rch)) |
                           ((auro_frame_state == HEAD_EOF_STA) & (~eof_cnt_rch)) |
                           (auro_frame_state == SLICE_DATA_STA));
    assign fifo_rd_en = (~idle_frame_ind) & fifo_rd_en_t;

    assign data_valid_rd_en = tx_dst_rdy &
                              ((auro_frame_state == HEAD_SOF_PRE_STA2) |
                               (auro_frame_state == HEAD_SOF_STA) |
                               (auro_frame_state == HEAD_DATA_STA) |
                               (auro_frame_state == SLICE_SOF_PRE_STA2) |
                               (auro_frame_state == SLICE_SOF_STA) |
                               ((auro_frame_state == SLICE_EOF_STA) & (~eof_cnt_rch)) |
                               ((auro_frame_state == HEAD_EOF_STA) & (~eof_cnt_rch)) |
                               (auro_frame_state == SLICE_DATA_STA));

    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            fifo_rd_en_dly <= 'h0;
        end
        else if (tx_dst_rdy) begin
            fifo_rd_en_dly <= data_valid_rd_en;
        end
    end

    assign tx_src_rdy_out = fifo_rd_en_dly & tx_dst_rdy;

    // -------------------------------------------------------------------------
    // Header, Slice, Footer, and CRC Control
    // -------------------------------------------------------------------------
    assign idle_slice_data_en = idle_slice_data_en_t;
    assign idle_slice_data_en_t = tx_dst_rdy &
                                  ((auro_frame_state == SLICE_SOF_PRE_STA2) |
                                   (auro_frame_state == SLICE_SOF_STA) |
                                   (auro_frame_state == SLICE_DATA_STA));

    assign header_cmd_2_en = sof_cnt_rch      & tx_dst_rdy & (auro_frame_state == HEAD_SOF_STA);
    assign header_cmd_1_en = (sof_cnt == 'h0) & tx_dst_rdy & (auro_frame_state == HEAD_SOF_STA);
    assign header_en       = tx_dst_rdy & (auro_frame_state == HEAD_DATA_STA);

    assign slice_cmd_2_en = sof_cnt_rch      & tx_dst_rdy & (auro_frame_state == SLICE_SOF_STA);
    assign slice_cmd_1_en = (sof_cnt == 'h0) & tx_dst_rdy & (auro_frame_state == SLICE_SOF_STA);

`ifdef TX_DATA_WIDTH_32
    assign footer_en   = tx_dst_rdy & (auro_frame_state == SLICE_DATA_STA) &
                         (slice_data_cnt == slice_data_cnt_lim);
    assign footer_1_en = tx_dst_rdy & (auro_frame_state == SLICE_DATA_STA) &
                         (slice_data_cnt == (slice_data_cnt_lim - 1));
    assign crc_en_t    = tx_dst_rdy &
                         (((auro_frame_state == HEAD_DATA_STA) && header_cnt[0]) |
                          ((auro_frame_state == SLICE_DATA_STA) && slice_data_cnt[0]));
`else
    assign footer_en   = tx_dst_rdy & (auro_frame_state == SLICE_DATA_STA) &
                         (slice_data_cnt == slice_data_cnt_lim);
    assign footer_1_en = tx_dst_rdy & (auro_frame_state == SLICE_DATA_STA) &
                         (slice_data_cnt == (slice_data_cnt_lim - 1));
    assign crc_en_t    = tx_dst_rdy &
                         ((auro_frame_state == HEAD_DATA_STA) |
                          (auro_frame_state == SLICE_DATA_STA));
`endif

    assign crc_en      = crc_en_t & (~(crc_tx_1_en | crc_tx_2_en));
    assign clear_crc_t = (auro_frame_state == HEAD_SOF_STA) |
                         (auro_frame_state == SLICE_SOF_STA);
    assign clear_crc   = clear_crc_t;
    assign crc_tx_1_en = (eof_cnt == 'h0) &
                         ((auro_frame_state == HEAD_EOF_STA) |
                          (auro_frame_state == SLICE_EOF_STA));
    assign crc_tx_2_en = eof_cnt_rch &
                         ((auro_frame_state == HEAD_EOF_STA) |
                          (auro_frame_state == SLICE_EOF_STA));

    // -------------------------------------------------------------------------
    // Refresh Frame Control
    // -------------------------------------------------------------------------
    assign tx_sof_refresh     = (auro_frame_state == REFRESH_DATA) & tx_dst_rdy & (ref_data_cnt == 'h0);
    assign tx_eof_refresh     = (auro_frame_state == REFRESH_DATA) & tx_dst_rdy & ref_data_cnt_rch;
    assign tx_src_rdy_refresh = tx_sof_refresh | tx_eof_refresh;

    // -------------------------------------------------------------------------
    // TX Output Selection
    // -------------------------------------------------------------------------
    logic [11:0] PROJECT_CODE  = 'h043;
    logic [3:0]  PROTOCAL_CODE = 'h3;
    logic [3:0]  REFRESH_ID    = 'h2;

    assign tx_rem_out       = 'h0;
    assign tx_sof_n_out     = ~(tx_sof_out | tx_sof_refresh);
    assign tx_eof_n_out     = ~(tx_eof_out | tx_eof_refresh);
    assign tx_src_rdy_n_out = ~(tx_src_rdy_out | tx_src_rdy_refresh);

`ifdef TX_DATA_WIDTH_32
    assign tx_d_out = fault_gen_inject_ind ? {12'hFAE, tx_d_out_t[19:0]} : tx_d_out_t;
    assign tx_d_out_t = tx_sof_refresh ? 32'h00000100 :
                        tx_eof_refresh ? {PROJECT_CODE, PROTOCAL_CODE, REFRESH_ID, 12'h0} :
                        idle_frame_ind ? idle_data_out :
                        aurora_frame_fifo_dout;
`else
    assign tx_d_out = fault_gen_inject_ind ? {12'hFAE, tx_d_out_t[51:0]} : tx_d_out_t;
    assign tx_d_out_t = tx_sof_refresh ? {PROJECT_CODE, PROTOCAL_CODE, REFRESH_ID, 12'h0, 32'h00000100} :
                        tx_eof_refresh ? {PROJECT_CODE, PROTOCAL_CODE, REFRESH_ID, 12'h0, 32'h00000100} :
                        idle_frame_ind ? idle_data_out :
                        aurora_frame_fifo_dout;
`endif

    // -------------------------------------------------------------------------
    // Diagnostic and Debug Outputs
    // -------------------------------------------------------------------------
    assign data_sof = tx_dst_rdy & (auro_frame_state == SLICE_SOF_STA);
    assign head_sof = tx_dst_rdy & (auro_frame_state == HEAD_SOF_STA);

`ifdef TX_DATA_WIDTH_32
    assign set_Diag_aurora_data_err_out   = data_sof & sof_cnt_rch & (tx_d_out[31:12] != 'h4330);
    assign set_Diag_aurora_header_err_out = head_sof & sof_cnt_rch & (tx_d_out[31:12] != 'h4331);
`else
    assign set_Diag_aurora_data_err_out   = data_sof & sof_cnt_rch & (tx_d_out[63:44] != 'h4330);
    assign set_Diag_aurora_header_err_out = head_sof & sof_cnt_rch & (tx_d_out[63:44] != 'h4331);
`endif

    assign aurora_first_view_temp = (header_cnt == 'h0) &
                                    tx_d_out[20] &
                                    (auro_frame_state == HEAD_DATA_STA) &
                                    tx_src_rdy_out;

    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            Diag_aurora_data_err_out <= 'h0;
        end
        else if (set_Diag_aurora_data_err_out && (~rst_local)) begin
            Diag_aurora_data_err_out <= 'h1;
        end
        else begin
            Diag_aurora_data_err_out <= 'h0;
        end
    end

    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            Diag_aurora_header_err_out <= 'h0;
        end
        else if (set_Diag_aurora_header_err_out && (~rst_local)) begin
            Diag_aurora_header_err_out <= 'h1;
        end
        else begin
            Diag_aurora_header_err_out <= 'h0;
        end
    end

    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            aurora_first_view <= 'h0;
        end
        else begin
            aurora_first_view <= aurora_first_view_temp;
        end
    end

    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            aurora_idle_cnt <= 'h0;
        end
        else if (tx_eof_out) begin
            aurora_idle_cnt <= 'h0;
        end
        else if (pulse_1us_dd && (~pulse_1us_ddd)) begin
            aurora_idle_cnt <= aurora_idle_cnt + 1'h1;
        end
    end

    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            Diag_auroradata_en_rise_flag_out <= 'h0;
        end
        else if (aurora_idle_cnt == 'h2710) begin
            Diag_auroradata_en_rise_flag_out <= 'h1;
        end
        else begin
            Diag_auroradata_en_rise_flag_out <= 'h0;
        end
    end

    always_ff @(posedge gtx_user_clk_in) begin
        auro_frame_state_test <= auro_frame_state;
    end

endmodule // aurora_frame
