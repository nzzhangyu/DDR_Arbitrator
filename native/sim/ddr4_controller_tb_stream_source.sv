`timescale 1ns/1ps

// Stream source for driving ddr4_controller.data_from_ddr_* directly.
//
// This models the stream that normally comes from header_frame_gen:
//   reading header frame -> slice frame 0 -> ... -> slice frame N
//
// Only cycles with data_en=1 are written into ddr_wr_fifo. The idle cycles below
// model header_data_out_en deassertions between header-frame states.
module ddr4_controller_tb_stream_source #(
    parameter int CONV_PERIOD_US      = 232,
    parameter int CLK_PERIOD_PS       = 5000,
    parameter int FTP_NUM             = 30,
    parameter int CH_NUM              = 48,
    parameter int SLICE_NUM           = 128,
    parameter int SAMPLE_BITS         = 16,
    parameter int APP_DATA_BITS       = 128,
    parameter bit INCREMENT_MODE      = 1'b0,
    parameter bit MODEL_HEADER_GAPS   = 1'b1,
    parameter int SLICE_GAP_CYCLES    = 1,
    parameter int VIEW_GAP_CYCLES     = 4
) (
    input  logic         clk,
    input  logic         reset,
    input  logic         start,
    input  int           sim_view_count,
    output logic         data_en,
    output logic [127:0] data_word,
    output logic         send_done
);

    localparam int VIEW_PERIOD_CYCLES    = (CONV_PERIOD_US * 1000000) / CLK_PERIOD_PS;
    localparam int SAMPLES_PER_BEAT      = APP_DATA_BITS / SAMPLE_BITS;
    localparam int SLICE_PAYLOAD_SAMPLES = FTP_NUM * CH_NUM;
    localparam int SLICE_PAYLOAD_BEATS   = (SLICE_PAYLOAD_SAMPLES + SAMPLES_PER_BEAT - 1) /
                                           SAMPLES_PER_BEAT;
    localparam int SLICE_TRAILER_BEATS   = 1; // {slice_crc64, 64'hFACEEACECACEBACE}
    localparam int SLICE_DATA_BEATS      = SLICE_PAYLOAD_BEATS + SLICE_TRAILER_BEATS;

    localparam logic [63:0] SYNC_HEADER_DATA    = 64'h5a5a5a5aa5a5a5a5;
    localparam logic [63:0] H_FRAME_HEADER_DATA = 64'h0433100000002100;
    localparam logic [63:0] SLICE_FOOTER_DATA   = 64'hFACEEACECACEBACE;

    int unsigned cycle_count;
    int          source_sent_count;
    logic [7:0]  increment_byte;

    always @(posedge clk) begin
        if (reset) begin
            cycle_count <= '0;
        end
        else begin
            cycle_count <= cycle_count + 1;
        end
    end

    initial begin
        data_en           = 1'b0;
        data_word         = '0;
        send_done         = 1'b0;
        source_sent_count = 0;
        increment_byte    = '0;

        wait (!reset);
        wait (start);
        send_ddr_input_stream();
    end

    task automatic send_ddr_input_stream();
        int view_idx;
        begin
            // Initial START and H_SYNC_HEADER before the first valid view beat.
            repeat_idle_cycles(2);

            for (view_idx = 0; view_idx < sim_view_count; view_idx++) begin
                send_view_frame(view_idx);

                if (view_idx != (sim_view_count - 1)) begin
                    // Last valid beat of one view to first valid H_FRAME_HEADER
                    // beat of the next view: V_DONE, IDLE, START, H_SYNC_HEADER.
                    repeat_idle_cycles(VIEW_GAP_CYCLES);
                end
            end

            idle_write_cycle();
            send_done = 1'b1;
        end
    endtask

    task automatic send_view_frame(input int view_idx);
        int slice_idx;
        begin
            send_reading_header_frame(view_idx);

            for (slice_idx = 0; slice_idx < SLICE_NUM; slice_idx++) begin
                send_slice_frame(view_idx, slice_idx);
            end
        end
    endtask

    task automatic send_reading_header_frame(input int view_idx);
        int header_group_idx;
        begin
            push_write_beat({H_FRAME_HEADER_DATA, SYNC_HEADER_DATA});

            // In header_frame_gen, H_DATA writes only when header_cnt[0]==1.
            // The effective sequence is {group1, group0}, {group3, group2}, ...
            // through {group29, group28}. group30 is paired with the CRC beat.
            for (header_group_idx = 1; header_group_idx <= 29; header_group_idx += 2) begin
                maybe_idle_write_cycle();
                push_write_beat({
                    make_header_group64(view_idx, header_group_idx),
                    make_header_group64(view_idx, header_group_idx - 1)
                });
            end

            // H_DATA with header_cnt==30 is not a valid output cycle; H_CRC then
            // emits {crc, group30}. This matches the current RTL behavior.
            maybe_idle_write_cycle();
            push_write_beat({make_header_crc64(view_idx), make_header_group64(view_idx, 30)});
        end
    endtask

    task automatic send_slice_frame(input int view_idx, input int slice_idx);
        int data_beat_idx;
        begin
            // Last valid beat before this slice to its S_FRAME_HEADER beat.
            // For slice0 this is the H_CRC -> S_FRAME_HEADER gap.
            repeat_idle_cycles(SLICE_GAP_CYCLES);
            push_write_beat({make_slice_frame_header64(slice_idx), SYNC_HEADER_DATA});

            // First S_DATA read primes rx_fifo_rd_en_d; no write occurs that cycle.
            maybe_idle_write_cycle();
            for (data_beat_idx = 0; data_beat_idx < SLICE_DATA_BEATS; data_beat_idx++) begin
                push_write_beat(make_slice_data_word(view_idx, slice_idx, data_beat_idx));
            end
        end
    endtask

    task automatic push_write_beat(input logic [127:0] word);
        begin
            @(negedge clk);
            data_word = INCREMENT_MODE ? {16{increment_byte}} : word;
            data_en   = 1'b1;
            source_sent_count++;
            if (INCREMENT_MODE) begin
                increment_byte++;
            end
        end
    endtask

    task automatic maybe_idle_write_cycle();
        begin
            if (MODEL_HEADER_GAPS) begin
                idle_write_cycle();
            end
        end
    endtask

    task automatic repeat_idle_cycles(input int gap_cycles);
        int gap_idx;
        begin
            for (gap_idx = 0; gap_idx < gap_cycles; gap_idx++) begin
                idle_write_cycle();
            end
        end
    endtask

    task automatic idle_write_cycle();
        begin
            @(negedge clk);
            data_en   = 1'b0;
            data_word = '0;
        end
    endtask

    function automatic logic [63:0] make_slice_frame_header64(input int slice_idx);
        logic [11:0] all_slice_number;
        logic [9:0]  data_slice_length;
        begin
            all_slice_number = 12'(slice_idx);
            data_slice_length = 10'((SLICE_PAYLOAD_SAMPLES >> 2) + 3);
            make_slice_frame_header64 = {
                20'h04330,
                all_slice_number,
                14'h0,
                data_slice_length,
                8'h00
            };
        end
    endfunction

    function automatic logic [63:0] make_header_group64(
        input int view_idx,
        input int group_idx
    );
        logic [15:0] w0;
        logic [15:0] w1;
        logic [15:0] w2;
        logic [15:0] w3;
        begin
            w0 = make_header_word16(view_idx, group_idx * 4 + 0);
            w1 = make_header_word16(view_idx, group_idx * 4 + 1);
            w2 = make_header_word16(view_idx, group_idx * 4 + 2);
            w3 = make_header_word16(view_idx, group_idx * 4 + 3);
            make_header_group64 = {w3, w2, w1, w0};
        end
    endfunction

    function automatic logic [15:0] make_header_word16(
        input int view_idx,
        input int word_idx
    );
        begin
            case (word_idx)
                0:  make_header_word16 = 16'h4844; // "HD"
                1:  make_header_word16 = 16'(view_idx);
                2:  make_header_word16 = 16'(SLICE_NUM);
                3:  make_header_word16 = 16'(SLICE_PAYLOAD_SAMPLES);
                4:  make_header_word16 = 16'(FTP_NUM);
                5:  make_header_word16 = 16'(CH_NUM);
                6:  make_header_word16 = 16'(CONV_PERIOD_US);
                7:  make_header_word16 = 16'(SAMPLE_BITS);
                8:  make_header_word16 = 16'(APP_DATA_BITS);
                9:  make_header_word16 = 16'(SLICE_DATA_BEATS);
                10: make_header_word16 = 16'(VIEW_PERIOD_CYCLES & 16'hffff);
                11: make_header_word16 = 16'((VIEW_PERIOD_CYCLES >> 16) & 16'hffff);
                default:
                    make_header_word16 = 16'((view_idx * 16'h101) ^ word_idx);
            endcase
        end
    endfunction

    function automatic logic [63:0] make_header_crc64(input int view_idx);
        logic [63:0] crc;
        int group_idx;
        begin
            crc = 64'h0;
            for (group_idx = 0; group_idx <= 30; group_idx++) begin
                crc ^= make_header_group64(view_idx, group_idx);
                crc = {crc[62:0], crc[63]};
            end
            make_header_crc64 = crc;
        end
    endfunction

    function automatic logic [127:0] make_slice_data_word(
        input int view_idx,
        input int slice_idx,
        input int data_beat_idx
    );
        begin
            if (data_beat_idx == SLICE_PAYLOAD_BEATS) begin
                make_slice_data_word = {make_slice_crc64(view_idx, slice_idx), SLICE_FOOTER_DATA};
            end
            else begin
                make_slice_data_word = make_payload_word(view_idx, slice_idx, data_beat_idx);
            end
        end
    endfunction

    function automatic logic [63:0] make_slice_crc64(input int view_idx, input int slice_idx);
        logic [63:0] crc;
        logic [127:0] payload_word;
        int beat_idx;
        begin
            crc = 64'h0;
            for (beat_idx = 0; beat_idx < SLICE_PAYLOAD_BEATS; beat_idx++) begin
                payload_word = make_payload_word(view_idx, slice_idx, beat_idx);
                crc ^= payload_word[63:0];
                crc ^= payload_word[127:64];
                crc = {crc[60:0], crc[63:61]};
            end
            crc ^= SLICE_FOOTER_DATA;
            make_slice_crc64 = crc;
        end
    endfunction

    function automatic logic [15:0] make_sample16(
        input int view_idx,
        input int slice_idx,
        input int sample_idx
    );
        begin
            make_sample16 = 16'((view_idx * 16'h101) ^
                                (slice_idx * 16'h11) ^
                                sample_idx);
        end
    endfunction

    function automatic logic [127:0] make_payload_word(
        input int view_idx,
        input int slice_idx,
        input int payload_beat_idx
    );
        logic [127:0] word;
        int sample_lane;
        int sample_idx;
        begin
            word = '0;
            for (sample_lane = 0; sample_lane < SAMPLES_PER_BEAT; sample_lane++) begin
                sample_idx = payload_beat_idx * SAMPLES_PER_BEAT + sample_lane;
                if (sample_idx < SLICE_PAYLOAD_SAMPLES) begin
                    word[sample_lane*SAMPLE_BITS +: SAMPLE_BITS] =
                        make_sample16(view_idx, slice_idx, sample_idx);
                end
            end
            make_payload_word = word;
        end
    endfunction

endmodule
