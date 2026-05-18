`timescale 1ns/1ps

// Continuous business stream source for the native DDR controller testbench.
//
// Responsibility boundary:
// - This module knows the application frame format: view -> slice -> header/payload.
// - It drives the DUT user input with no artificial gap while a view is active.
// - It does not know anything about the scoreboard or DDR result checking.
//
// The top-level testbench observes data_en/data_word to build the expected
// scoreboard, so the expected stream is always the exact stream presented to the
// DUT input pins.
module ddr4_controller_tb_stream_source #(
    parameter int CONV_PERIOD_US     = 232,
    parameter int CLK_PERIOD_PS      = 5000,
    parameter int FTP_NUM            = 30,
    parameter int CH_NUM             = 48,
    parameter int SLICE_NUM          = 128,
    parameter int SAMPLE_BITS        = 16,
    parameter int APP_DATA_BITS      = 128
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        start,
    input  int          sim_view_count,
    output logic        data_en,
    output logic [127:0] data_word,
    output logic        send_done
);

    // Derived application framing. One payload beat carries eight 16-bit samples
    // when APP_DATA_BITS is 128 and SAMPLE_BITS is 16.
    localparam int VIEW_PERIOD_CYCLES   = (CONV_PERIOD_US * 1000000) / CLK_PERIOD_PS;
    localparam int SAMPLES_PER_BEAT     = APP_DATA_BITS / SAMPLE_BITS;
    localparam int SLICE_HEADER_BEATS   = 2;
    localparam int SLICE_PAYLOAD_SAMPLES = FTP_NUM * CH_NUM;
    localparam int SLICE_PAYLOAD_BEATS  = (SLICE_PAYLOAD_SAMPLES + SAMPLES_PER_BEAT - 1) /
                                          SAMPLES_PER_BEAT;
    localparam int SLICE_TOTAL_BEATS    = SLICE_HEADER_BEATS + SLICE_PAYLOAD_BEATS;

    int unsigned cycle_count;
    int          source_sent_count;

    always @(posedge clk) begin
        if (reset) begin
            cycle_count <= '0;
        end
        else begin
            cycle_count <= cycle_count + 1;
        end
    end

    initial begin
        // The source stays idle through reset and until the top-level test starts
        // it after make_data/reset settling. Once started, it sends all requested
        // views and then raises send_done.
        data_en           = 1'b0;
        data_word         = '0;
        send_done         = 1'b0;
        source_sent_count = 0;

        wait (!reset);
        wait (start);
        send_slice_stream();
    end

    task automatic send_slice_stream();
        int view_idx;
        int slice_idx;
        int view_start_cycle;
        begin
            // Each view sends all slices back-to-back, then waits until the
            // configured view period has elapsed. This models a continuous burst
            // within a view and a fixed acquisition cadence between views.
            for (view_idx = 0; view_idx < sim_view_count; view_idx++) begin
                view_start_cycle = cycle_count;
                for (slice_idx = 0; slice_idx < SLICE_NUM; slice_idx++) begin
                    send_slice_frame(view_idx, slice_idx);
                end
                idle_write_cycle();
                while ((cycle_count - view_start_cycle) < VIEW_PERIOD_CYCLES) begin
                    @(posedge clk);
                end
            end
            idle_write_cycle();
            send_done = 1'b1;
        end
    endtask

    task automatic send_slice_frame(input int view_idx, input int slice_idx);
        int payload_beat_idx;
        begin
            // Slice layout:
            //   beat 0: header0, structural identifiers and payload length
            //   beat 1: header1, timing and stream-position metadata
            //   beat 2..N: deterministic sample payload
            push_write_beat(make_slice_header0(view_idx, slice_idx));
            push_write_beat(make_slice_header1(view_idx, slice_idx));

            for (payload_beat_idx = 0;
                 payload_beat_idx < SLICE_PAYLOAD_BEATS;
                 payload_beat_idx++) begin
                push_write_beat(make_payload_word(view_idx, slice_idx, payload_beat_idx));
            end
        end
    endtask

    task automatic push_write_beat(input logic [127:0] word);
        begin
            // Drive on negedge so the DUT samples stable data on the following
            // posedge. There is no ready/valid backpressure on this user input;
            // FIFO overflow is intentionally reported by the DUT/testbench.
            @(negedge clk);
            data_word = word;
            data_en   = 1'b1;
            source_sent_count++;
        end
    endtask

    task automatic idle_write_cycle();
        begin
            // Inserted only between views and after the full stream is complete.
            // It is not a randomized pressure/stall mechanism.
            @(negedge clk);
            data_en   = 1'b0;
            data_word = '0;
        end
    endtask

    function automatic logic [127:0] make_slice_header0(
        input int view_idx,
        input int slice_idx
    );
        // Header0 encodes values that are expected to be constant or structural
        // within a view. The magic word makes swapped/misaligned headers obvious.
        make_slice_header0 = {
            32'hdd44_0001,
            16'(view_idx),
            16'(slice_idx),
            16'(SLICE_NUM),
            16'(SLICE_PAYLOAD_BEATS),
            16'(FTP_NUM),
            16'(CH_NUM)
        };
    endfunction

    function automatic logic [127:0] make_slice_header1(
        input int view_idx,
        input int slice_idx
    );
        // Header1 carries timing and stream-position metadata. source_sent_count
        // is the absolute beat index before this header is emitted.
        make_slice_header1 = {
            32'hdd44_0002,
            16'(view_idx),
            16'(slice_idx),
            16'(CONV_PERIOD_US),
            16'(VIEW_PERIOD_CYCLES),
            32'(source_sent_count),
            16'(SAMPLES_PER_BEAT),
            16'(SAMPLE_BITS)
        };
    endfunction

    function automatic logic [15:0] make_sample16(
        input int view_idx,
        input int slice_idx,
        input int sample_idx
    );
        // Deterministic but non-constant pattern. Mixing view/slice/sample fields
        // makes address/order mistakes show up as data mismatches quickly.
        make_sample16 = 16'((view_idx * 16'h101) ^
                            (slice_idx * 16'h11) ^
                            sample_idx);
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
                // Pack sample lane 0 into the least-significant 16 bits, matching
                // the DUT's 128-bit beat orientation used by the existing tests.
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
