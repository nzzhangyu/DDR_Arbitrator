// Aurora TX frame generator.
// Generates header, slice, idle, and refresh frames from DDR cache FIFO data.
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
    input  logic        m_axis_tx_tready,
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
    output logic [3:0]  m_axis_tx_tkeep,
    output logic [31:0] m_axis_tx_tdata,
`else
    input  logic [63:0] aurora_frame_fifo_dout,
    input  logic [63:0] idle_data_out,
    output logic [7:0]  m_axis_tx_tkeep,
    output logic [63:0] m_axis_tx_tdata,
`endif

    output logic        m_axis_tx_tvalid,
    output logic        m_axis_tx_tlast,
    output logic        axis_frame_sof,
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
        IDLE               = 4'h0,      // wait frame trigger
        HEAD_SOF_PRE_STA   = 4'h1,      // pre-read header data
        HEAD_SOF_PRE_STA2  = 4'h2,      // align header SOF
        HEAD_SOF_STA       = 4'h3,      // send header SOF
        HEAD_DATA_STA      = 4'h4,      // send header payload
        HEAD_EOF_STA       = 4'h5,      // send header EOF
        WAIT_SLICE_STA     = 4'h6,      // wait slice ready
        SLICE_SOF_PRE_STA  = 4'h7,      // pre-read slice data
        SLICE_SOF_PRE_STA2 = 4'h8,      // align slice SOF
        SLICE_SOF_STA      = 4'h9,      // send slice SOF
        SLICE_DATA_STA     = 4'ha,      // send slice payload
        SLICE_EOF_STA      = 4'hb,      // send slice EOF
        SLICE_DONE_STA     = 4'hc,      // finish view
        REFRESH_WAIT       = 4'hd,      // wait refresh tick
        REFRESH_DATA       = 4'he       // send refresh frame
    } auro_frame_state_t;

    logic [2:0]  sof_pre_cnt_lim;       // SOF preamble beats
    logic [1:0]  sof_cnt_lim;           // SOF beats
    logic [1:0]  eof_cnt_lim;           // EOF beats
    logic [7:0]  header_cnt_lim;        // header payload beats
    logic [9:0]  slice_data_cnt_lim;    // slice payload beats

    // -------------------------------------------------------------------------
    // Local Signals
    // -------------------------------------------------------------------------
    (* mark_debug="true" *) auro_frame_state_t auro_frame_state; // current frame state
    auro_frame_state_t auro_frame_state_next;                    // next frame state

    logic [11:0] slice_length;       // active normal slice length
    logic [11:0] idle_slice_length;  // fixed idle slice length
    logic [11:0] slice_length_tx;    // selected TX slice length

    logic axis_tx_fire;              // AXI4-Stream handshake while channel is up
    logic rst_local;                 // local GTX reset active
    logic fifo_reset;                // DDR-side FIFO reset

    logic rst_local_ddr_dly;         // delayed DDR reset
    logic rst_local_ddr_d1;
    logic rst_local_ddr_d2;
    logic rst_local_ddr_d3;
    logic rst_local_ddr_d4;
    logic rst_local_ddr_d5;
    logic rst_local_gtx_d1;          // GTX reset sample

    logic console_reset_in_gtx_d1;
    logic console_reset_in_gtx_d2;
    logic console_reset_in_gtx_d3;

    logic tx_channel_up_gtx_d1;
    logic tx_channel_up_gtx_d2;
    logic tx_channel_up_gtx_d3;      // synced channel-up

    (* ASYNC_REG = "true" *) logic refresh_process_en_gtx_d1;
    (* ASYNC_REG = "true" *) logic refresh_process_en_gtx_d2;
    (* ASYNC_REG = "true" *) logic refresh_process_en_gtx_d3; // refresh CDC tail

    logic pulse_1us_gtx_d1;
    logic pulse_1us_gtx_d2;
    logic pulse_1us_gtx_d3;
    logic pulse_1us_edge;               // 1us rising edge
    logic refresh_trigger_pulse;        // refresh frame trigger

    logic [15:0] fault_50ms_cnt;        // fault interval counter
    logic        fault_50ms_cnt_rch;    // fault interval reached
    logic        fault_gen_r;           // fault armed
    logic        fault_gen_set;         // start fault window
    logic        fault_gen_clr;         // end fault window
    logic        fault_gen_pulse;       // fault window active
    logic        fault_gen_inject_ind;  // corrupt one beat

    logic [2:0]  tail_gap_cnt;              // frame tail to next frame head counter
    logic        tail_gap_done;             // tail-to-head gap reached
    logic [9:0]  head_gap_cnt;              // frame head to next frame head counter
    logic        head_gap_done;             // head-to-head gap reached
    logic        trans_idle_frame_trig;     // idle frame request
    logic        trans_normal_frame_trig;   // normal frame request
    logic        trans_frame_trig;          // any frame request
    logic        console_reset_enable;      // console reset window

    logic [2:0] sof_pre_cnt;         // SOF preamble counter
    logic       sof_pre_cnt_rch;     // SOF preamble done
    logic [1:0] sof_cnt;             // SOF counter
    logic       sof_cnt_rch;         // SOF done
    logic [1:0] eof_cnt;             // EOF counter
    logic       eof_cnt_rch;         // EOF done
    logic       header_cnt_rch;      // header done

    logic        slice_data_cnt_add_normal; // count FIFO data beat
    logic        slice_data_cnt_add_idle;   // count idle data beat
    logic        slice_data_cnt_add_en;     // count any slice beat
    logic        slice_data_cnt_rch;        // slice payload done
    logic [8:0]  slice_sel_r;              // selected slice count
    logic        add_slice_cnt;            // advance slice index
    logic        slice_cnt_lim;            // last slice selected
    logic        slice_cnt_rch;            // all slices done
    logic [3:0]  ref_data_cnt;             // refresh beat counter
    logic        ref_data_cnt_lim;         // refresh last beat selected
    logic        ref_data_cnt_rch;         // refresh frame done handshake
    logic [3:0]  slice_interview_cnt;      // inter-slice gap counter
    logic        slice_interview_cnt_rch;  // inter-slice gap done

    logic frame_sof;                  // normal frame start marker
    logic frame_eof;                  // normal frame end marker
    logic axis_frame_valid;           // normal AXI4-Stream valid
    logic refresh_frame_sof;          // refresh frame start marker
    logic refresh_frame_eof;          // refresh frame end marker
    logic refresh_axis_valid;         // refresh AXI4-Stream valid

    logic fifo_rd_en_t;                     // raw FIFO read enable
    logic data_valid_rd_en;                 // delayed-data valid seed
    logic fifo_rd_en_dly;                   // aligned TX valid

    logic crc_en_t;                         // raw CRC enable
    logic clear_crc_t;                      // raw CRC clear
    logic idle_slice_data_en_t;             // idle payload valid

    logic aurora_frame_ok;                  // frame completed
    logic data_sof;                         // slice SOF check point
    logic head_sof;                         // header SOF check point
    logic set_Diag_aurora_data_err_out;     // data tag mismatch
    logic set_Diag_aurora_header_err_out;   // header tag mismatch
    logic aurora_first_view_temp;           // first-view marker
    logic [15:0] aurora_idle_cnt;           // no-EOF watchdog
        
    logic aurora_data_heade_ok;             // legacy header/data flag
    logic latch_frame_kind;                 // frame-kind sample point
    logic slice_data_en;                    // legacy slice data flag

`ifdef TX_DATA_WIDTH_32
    logic [31:0] axis_tdata_pre_fault; // selected AXI4-Stream data before fault injection
`else
    logic [63:0] axis_tdata_pre_fault; // selected AXI4-Stream data before fault injection
`endif

`ifdef TX_DATA_WIDTH_32
    // 32-bit beat limits
    assign sof_pre_cnt_lim    = 'd1;
    assign sof_cnt_lim        = 'd1;
    assign eof_cnt_lim        = 'd1;
    assign header_cnt_lim     = 'd61;
    assign slice_data_cnt_lim = (slice_length_tx[11:1] + 1'h1);
`else
    // 64-bit beat limits
    assign sof_pre_cnt_lim    = 'd0;
    assign sof_cnt_lim        = 'd0;
    assign eof_cnt_lim        = 'd0;
    assign header_cnt_lim     = 'd30;
    assign slice_data_cnt_lim = slice_length_tx[11:2];
`endif

    // -------------------------------------------------------------------------
    // CDC, Reset, and Channel Ready
    // -------------------------------------------------------------------------
    // stretch DDR reset into FIFO domain
    always_ff @(posedge ui_clk) begin
        rst_local_ddr_d1  <= rst_local_t_ddr_clk;
        rst_local_ddr_d2  <= rst_local_ddr_d1;
        rst_local_ddr_d3  <= rst_local_ddr_d2;
        rst_local_ddr_d4  <= rst_local_ddr_d3;
        rst_local_ddr_d5  <= rst_local_ddr_d4;
        rst_local_ddr_dly <= rst_local_ddr_d5;
    end

    // sample console reset
    always_ff @(posedge gtx_user_clk_in) begin
        console_reset_in_gtx_d1 <= console_reset_in;
        console_reset_in_gtx_d2 <= console_reset_in_gtx_d1;
        console_reset_in_gtx_d3 <= console_reset_in_gtx_d2;
    end

    // synchronize Aurora channel-up
    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            tx_channel_up_gtx_d1 <= 'h0;
            tx_channel_up_gtx_d2 <= 'h0;
            tx_channel_up_gtx_d3 <= 'h0;
        end
        else begin
            tx_channel_up_gtx_d1 <= TX_CHANNEL_UP_in;
            tx_channel_up_gtx_d2 <= tx_channel_up_gtx_d1;
            tx_channel_up_gtx_d3 <= tx_channel_up_gtx_d2;
        end
    end

    // sample local GTX reset
    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            rst_local_gtx_d1 <= 'h1;
        end
        else begin
            rst_local_gtx_d1 <= rst_local_t_gtx_clk;
        end
    end

    // derive AXI4-Stream handshake and resets
    assign axis_tx_fire = m_axis_tx_tready & tx_channel_up_gtx_d3;
    assign rst_local  = ~rst_local_gtx_d1;
    assign fifo_reset = ddr_user_rst | rst_local_ddr_dly;

    // -------------------------------------------------------------------------
    // Refresh Synchronization and 1us Timing
    // -------------------------------------------------------------------------
    // move refresh enable into GTX domain
    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            refresh_process_en_gtx_d1 <= 'h0;
            refresh_process_en_gtx_d2 <= 'h0;
            refresh_process_en_gtx_d3 <= 'h0;
        end
        else begin
            refresh_process_en_gtx_d1 <= refresh_process_en;
            refresh_process_en_gtx_d2 <= refresh_process_en_gtx_d1;
            refresh_process_en_gtx_d3 <= refresh_process_en_gtx_d2;
        end
    end

    // detect 1us pulse edge
    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            pulse_1us_gtx_d1 <= 'h0;
            pulse_1us_gtx_d2 <= 'h0;
            pulse_1us_gtx_d3 <= 'h0;
        end
        else begin
            pulse_1us_gtx_d1 <= clk_40mhz_1us_in;
            pulse_1us_gtx_d2 <= pulse_1us_gtx_d1;
            pulse_1us_gtx_d3 <= pulse_1us_gtx_d2;
        end
    end

    assign pulse_1us_edge = pulse_1us_gtx_d2 & (~pulse_1us_gtx_d3);

    // form refresh trigger
    assign gtx_refresh_process_en = refresh_process_en_gtx_d2;
    assign refresh_trigger_pulse  = gtx_refresh_process_en & pulse_1us_edge;

    // -------------------------------------------------------------------------
    // Fault Injection
    // -------------------------------------------------------------------------
    // choose fault insertion point
    assign fault_50ms_cnt_rch   = (fault_50ms_cnt == 'hC800);  // 50us
    assign fault_gen_set        = fault_gen_r & (slice_data_cnt == 'h10);
    assign fault_gen_clr        = fault_gen_r & (slice_data_cnt == 'h20);
    assign fault_gen_inject_ind = fault_gen_pulse & (slice_data_cnt == 'h18);

    // count fault interval
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

    // arm fault after interval
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

    // hold fault window
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
    // select active slice length
    assign slice_length      = slice_cnt[0] ? slice_length_even : slice_length_odd;
    assign idle_slice_length = 'h360;
    assign slice_length_tx   = idle_process_en ? idle_slice_length : slice_length;

    // gate view start cadence
    assign view_start_cnt_half = (tail_gap_cnt == 'h3) & (auro_frame_state == IDLE);
    assign tail_gap_done       = &tail_gap_cnt;
    assign head_gap_done       = (head_gap_cnt == 'h50); // 80us

    // build frame request
    assign console_reset_enable = (auro_frame_state == IDLE) |
                                  (auro_frame_state == REFRESH_DATA);
    assign trans_idle_frame_trig  = idle_process_en & idle_trig;
    assign trans_normal_frame_trig = (~idle_process_en) &
                                     (~aurora_frame_fifo_prog_empty) &
                                     head_gap_done &
                                     tail_gap_done;
    assign trans_frame_trig = trans_idle_frame_trig | trans_normal_frame_trig;
    assign view_tx_done     = (auro_frame_state == SLICE_DONE_STA) && (~rst_local);

    // delay after view completion
    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            tail_gap_cnt <= 'h0;
        end
        else if (gtx_refresh_process_en || view_tx_done /*|| rst_local*/) begin
            tail_gap_cnt <= 'h0;
        end
        else if (~tail_gap_done) begin
            tail_gap_cnt <= tail_gap_cnt + 1'h1;
        end
    end

    // enforce view-to-view spacing
    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            head_gap_cnt <= 'h0;
        end
        else if (gtx_refresh_process_en || (auro_frame_state == HEAD_SOF_PRE_STA)) begin
            head_gap_cnt <= 'h0;
        end
        else if (~head_gap_done && pulse_1us_edge) begin
            head_gap_cnt <= head_gap_cnt + 1'h1;
        end
    end

    // latch idle or normal frame kind
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
    // detect counter terminal beats
    assign sof_pre_cnt_rch = (sof_pre_cnt == sof_pre_cnt_lim) & axis_tx_fire;
    assign sof_cnt_rch     = (sof_cnt == sof_cnt_lim);
    assign eof_cnt_rch     = (eof_cnt == eof_cnt_lim);
    assign header_cnt_rch  = (header_cnt == header_cnt_lim) & axis_tx_fire;

    // count slice payload beats
    assign slice_data_cnt_add_normal = (~aurora_frame_fifo_empty) &
                                       axis_tx_fire &
                                       (~idle_frame_ind);
    assign slice_data_cnt_add_idle = axis_tx_fire & idle_frame_ind;
    assign slice_data_cnt_add_en   = slice_data_cnt_add_normal | slice_data_cnt_add_idle;
    assign slice_data_cnt_rch      = (slice_data_cnt == slice_data_cnt_lim) &
                                     (slice_data_cnt_add_normal | slice_data_cnt_add_idle);

    // select slice count
    assign latch_frame_kind = (auro_frame_state == HEAD_DATA_STA) &
                              (header_cnt == 'h7) &
                              axis_tx_fire;
    assign slice_sel_r   = idle_frame_ind ? 8'h20 : slice_sel;
    assign add_slice_cnt = (auro_frame_state == SLICE_EOF_STA) & eof_cnt_rch & axis_tx_fire;
    assign slice_cnt_lim = (slice_cnt == (slice_sel_r - 1));
    assign slice_cnt_rch = slice_cnt_lim & add_slice_cnt;

    // detect refresh and inter-slice completion
    assign ref_data_cnt_lim        = (ref_data_cnt == 'h1);
    assign ref_data_cnt_rch        = ref_data_cnt_lim & axis_tx_fire;
    assign slice_interview_cnt_rch = 'h1;

    // count SOF preamble
    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            sof_pre_cnt <= 'h0;
        end
        else if ((auro_frame_state != HEAD_SOF_PRE_STA) &&
                 (auro_frame_state != SLICE_SOF_PRE_STA)) begin
            sof_pre_cnt <= 'h0;
        end
        else if ((~sof_pre_cnt_rch) && axis_tx_fire) begin
            sof_pre_cnt <= sof_pre_cnt + 1'h1;
        end
    end

    // count SOF beats
    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            sof_cnt <= 'h0;
        end
        else if ((auro_frame_state != HEAD_SOF_STA) &&
                 (auro_frame_state != SLICE_SOF_STA)) begin
            sof_cnt <= 'h0;
        end
        else if ((~sof_cnt_rch) && axis_tx_fire) begin
            sof_cnt <= sof_cnt + 1'h1;
        end
    end

    // count EOF beats
    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            eof_cnt <= 'h0;
        end
        else if ((auro_frame_state != HEAD_EOF_STA) &&
                 (auro_frame_state != SLICE_EOF_STA)) begin
            eof_cnt <= 'h0;
        end
        else if ((~eof_cnt_rch) && axis_tx_fire) begin
            eof_cnt <= eof_cnt + 1'h1;
        end
    end

    // count header payload
    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            header_cnt <= 'h0;
        end
        else if (auro_frame_state != HEAD_DATA_STA) begin
            header_cnt <= 'h0;
        end
        else if ((~header_cnt_rch) && axis_tx_fire) begin
            header_cnt <= header_cnt + 1'h1;
        end
    end

    // count slice payload
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

    // count transmitted slices
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

    // count refresh beats
    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            ref_data_cnt <= 'h0;
        end
        else if (auro_frame_state != REFRESH_DATA) begin
            ref_data_cnt <= 'h0;
        end
        else if ((~ref_data_cnt_rch) & axis_tx_fire) begin
            ref_data_cnt <= ref_data_cnt + 1'h1;
        end
    end

    // count inter-slice gap
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
    // register FSM state
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
                if (rst_local || (~tx_channel_up_gtx_d3)) begin
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
                else if (axis_tx_fire) begin
                    auro_frame_state_next = HEAD_SOF_STA;
                end
            end

            HEAD_SOF_STA: begin
                if (rst_local) begin
                    auro_frame_state_next = HEAD_EOF_STA;
                end
                else if (sof_cnt_rch && axis_tx_fire) begin
                    auro_frame_state_next = HEAD_DATA_STA;
                end
            end

            HEAD_DATA_STA: begin
                if (header_cnt_rch || rst_local) begin
                    auro_frame_state_next = HEAD_EOF_STA;
                end
            end

            HEAD_EOF_STA: begin
                if (rst_local /*&& (axis_tx_fire)*/) begin
                    auro_frame_state_next = IDLE;
                end
                else if (eof_cnt_rch && axis_tx_fire) begin
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
                if (axis_tx_fire) begin
                    auro_frame_state_next = SLICE_SOF_STA;
                end
            end

            SLICE_SOF_STA: begin
                if (rst_local) begin
                    auro_frame_state_next = SLICE_EOF_STA;
                end
                else if (sof_cnt_rch && axis_tx_fire) begin
                    auro_frame_state_next = SLICE_DATA_STA;
                end
            end

            SLICE_DATA_STA: begin
                if (slice_data_cnt_rch || rst_local) begin
                    auro_frame_state_next = SLICE_EOF_STA;
                end
            end

            SLICE_EOF_STA: begin
                if (rst_local /*&& (axis_tx_fire)*/) begin
                    auro_frame_state_next = IDLE;
                end
                else if (eof_cnt_rch && axis_tx_fire) begin
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
    // generate normal frame strobes
    assign frame_sof = (sof_cnt == 'h0) &
                        ((auro_frame_state == HEAD_SOF_STA) |
                         (auro_frame_state == SLICE_SOF_STA));
    assign frame_eof = eof_cnt_rch &
                        ((auro_frame_state == HEAD_EOF_STA) |
                         (auro_frame_state == SLICE_EOF_STA));
    assign aurora_frame_ok = (auro_frame_state == SLICE_DONE_STA) |
                             ((auro_frame_state == REFRESH_DATA) & ref_data_cnt_rch);

    // -------------------------------------------------------------------------
    // FIFO Read and TX Valid Control
    // -------------------------------------------------------------------------
    // read during frame data path states
    assign fifo_rd_en_t = axis_tx_fire &
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
    // suppress FIFO reads for idle frames
    assign fifo_rd_en = (~idle_frame_ind) & fifo_rd_en_t;

    // align valid with FIFO output latency
    assign data_valid_rd_en = axis_tx_fire &
                              ((auro_frame_state == HEAD_SOF_PRE_STA2) |
                               (auro_frame_state == HEAD_SOF_STA) |
                               (auro_frame_state == HEAD_DATA_STA) |
                               (auro_frame_state == SLICE_SOF_PRE_STA2) |
                               (auro_frame_state == SLICE_SOF_STA) |
                               ((auro_frame_state == SLICE_EOF_STA) & (~eof_cnt_rch)) |
                               ((auro_frame_state == HEAD_EOF_STA) & (~eof_cnt_rch)) |
                               (auro_frame_state == SLICE_DATA_STA));

    // delay data-valid seed
    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            fifo_rd_en_dly <= 'h0;
        end
        else if (axis_tx_fire) begin
            fifo_rd_en_dly <= data_valid_rd_en;
        end
    end

    // expose valid after FIFO latency; counters advance only on axis_tx_fire
    assign axis_frame_valid = fifo_rd_en_dly & tx_channel_up_gtx_d3;

    // -------------------------------------------------------------------------
    // Header, Slice, Footer, and CRC Control
    // -------------------------------------------------------------------------
    // mark idle slice data window
    assign idle_slice_data_en = idle_slice_data_en_t;
    assign idle_slice_data_en_t = axis_tx_fire &
                                  ((auro_frame_state == SLICE_SOF_PRE_STA2) |
                                   (auro_frame_state == SLICE_SOF_STA) |
                                   (auro_frame_state == SLICE_DATA_STA));

    // mark header command and payload beats
    assign header_cmd_2_en = sof_cnt_rch      & axis_tx_fire & (auro_frame_state == HEAD_SOF_STA);
    assign header_cmd_1_en = (sof_cnt == 'h0) & axis_tx_fire & (auro_frame_state == HEAD_SOF_STA);
    assign header_en       = axis_tx_fire & (auro_frame_state == HEAD_DATA_STA);

    // mark slice command beats
    assign slice_cmd_2_en = sof_cnt_rch      & axis_tx_fire & (auro_frame_state == SLICE_SOF_STA);
    assign slice_cmd_1_en = (sof_cnt == 'h0) & axis_tx_fire & (auro_frame_state == SLICE_SOF_STA);

`ifdef TX_DATA_WIDTH_32
    // 32-bit footer and CRC cadence
    assign footer_en   = axis_tx_fire & (auro_frame_state == SLICE_DATA_STA) &
                         (slice_data_cnt == slice_data_cnt_lim);
    assign footer_1_en = axis_tx_fire & (auro_frame_state == SLICE_DATA_STA) &
                         (slice_data_cnt == (slice_data_cnt_lim - 1));
    assign crc_en_t    = axis_tx_fire &
                         (((auro_frame_state == HEAD_DATA_STA) && header_cnt[0]) |
                          ((auro_frame_state == SLICE_DATA_STA) && slice_data_cnt[0]));
`else
    // 64-bit footer and CRC cadence
    assign footer_en   = axis_tx_fire & (auro_frame_state == SLICE_DATA_STA) &
                         (slice_data_cnt == slice_data_cnt_lim);
    assign footer_1_en = axis_tx_fire & (auro_frame_state == SLICE_DATA_STA) &
                         (slice_data_cnt == (slice_data_cnt_lim - 1));
    assign crc_en_t    = axis_tx_fire &
                         ((auro_frame_state == HEAD_DATA_STA) |
                          (auro_frame_state == SLICE_DATA_STA));
`endif

    // emit CRC control strobes
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
    // generate refresh frame strobes
    assign refresh_frame_sof     = (auro_frame_state == REFRESH_DATA) & (ref_data_cnt == 'h0);
    assign refresh_frame_eof     = (auro_frame_state == REFRESH_DATA) & ref_data_cnt_lim;
    assign refresh_axis_valid = (auro_frame_state == REFRESH_DATA) & tx_channel_up_gtx_d3;

    // -------------------------------------------------------------------------
    // TX Output Selection
    // -------------------------------------------------------------------------
    logic [11:0] PROJECT_CODE  = 'h043; // refresh project tag
    logic [3:0]  PROTOCAL_CODE = 'h3;   // refresh protocol tag
    logic [3:0]  REFRESH_ID    = 'h2;   // refresh frame tag

    // Drive AXI4-Stream output controls. SOF stays internal and marks the
    // first TVALID/TREADY beat after reset or after a previous TLAST.
    assign m_axis_tx_tkeep  = '1;
    assign axis_frame_sof   = frame_sof | refresh_frame_sof;
    assign m_axis_tx_tlast  = frame_eof | refresh_frame_eof;
    assign m_axis_tx_tvalid = axis_frame_valid | refresh_axis_valid;

`ifdef TX_DATA_WIDTH_32
    // select 32-bit TX payload
    assign m_axis_tx_tdata = fault_gen_inject_ind ? {12'hFAE, axis_tdata_pre_fault[19:0]} : axis_tdata_pre_fault;
    assign axis_tdata_pre_fault = refresh_frame_sof ? 32'h00000100 :
                        refresh_frame_eof ? {PROJECT_CODE, PROTOCAL_CODE, REFRESH_ID, 12'h0} :
                        idle_frame_ind ? idle_data_out :
                        aurora_frame_fifo_dout;
`else
    // select 64-bit TX payload
    assign m_axis_tx_tdata = fault_gen_inject_ind ? {12'hFAE, axis_tdata_pre_fault[51:0]} : axis_tdata_pre_fault;
    assign axis_tdata_pre_fault = refresh_frame_sof ? {PROJECT_CODE, PROTOCAL_CODE, REFRESH_ID, 12'h0, 32'h00000100} :
                        refresh_frame_eof ? {PROJECT_CODE, PROTOCAL_CODE, REFRESH_ID, 12'h0, 32'h00000100} :
                        idle_frame_ind ? idle_data_out :
                        aurora_frame_fifo_dout;
`endif

    // -------------------------------------------------------------------------
    // Diagnostic and Debug Outputs
    // -------------------------------------------------------------------------
    // sample SOF check points
    assign data_sof = axis_tx_fire & (auro_frame_state == SLICE_SOF_STA);
    assign head_sof = axis_tx_fire & (auro_frame_state == HEAD_SOF_STA);

`ifdef TX_DATA_WIDTH_32
    // check 32-bit frame tags
    assign set_Diag_aurora_data_err_out   = data_sof & sof_cnt_rch & (m_axis_tx_tdata[31:12] != 'h4330);
    assign set_Diag_aurora_header_err_out = head_sof & sof_cnt_rch & (m_axis_tx_tdata[31:12] != 'h4331);
`else
    // check 64-bit frame tags
    assign set_Diag_aurora_data_err_out   = data_sof & sof_cnt_rch & (m_axis_tx_tdata[63:44] != 'h4330);
    assign set_Diag_aurora_header_err_out = head_sof & sof_cnt_rch & (m_axis_tx_tdata[63:44] != 'h4331);
`endif

    // detect first view marker
    assign aurora_first_view_temp = (header_cnt == 'h0) &
                                    m_axis_tx_tdata[20] &
                                    (auro_frame_state == HEAD_DATA_STA) &
                                    axis_frame_valid;

    // pulse data tag error
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

    // pulse header tag error
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

    // register first view marker
    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            aurora_first_view <= 'h0;
        end
        else begin
            aurora_first_view <= aurora_first_view_temp;
        end
    end

    // count idle time without EOF
    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            aurora_idle_cnt <= 'h0;
        end
        else if (frame_eof) begin
            aurora_idle_cnt <= 'h0;
        end
        else if (pulse_1us_gtx_d2 && (~pulse_1us_gtx_d3)) begin
            aurora_idle_cnt <= aurora_idle_cnt + 1'h1;
        end
    end

    // pulse no-data watchdog
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

    // expose FSM for debug
    always_ff @(posedge gtx_user_clk_in) begin
        auro_frame_state_test <= auro_frame_state;
    end

endmodule // aurora_frame
