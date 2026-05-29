`timescale 1ns/1ps

// Read pending queue and variable-latency return model.
module ddr4_fast_mock_read_pending_model #(
    parameter int APP_ADDR_WIDTH = 32,
    parameter int MEM_WORDS = 16384,
    parameter int READ_LATENCY_CYCLES = 2,
    parameter int READ_LATENCY_MIN_CYCLES = READ_LATENCY_CYCLES,
    parameter int READ_LATENCY_MAX_CYCLES = READ_LATENCY_CYCLES,
    parameter int READ_PENDING_DEPTH = 16
) (
    input  logic                      clk,
    input  logic                      reset,
    input  logic                      init_calib_complete,
    input  logic                      read_cmd_fire,
    input  logic [APP_ADDR_WIDTH-1:0] read_addr,
    input  logic                      data_stall_active,
    output logic [$clog2(MEM_WORDS)-1:0] read_mem_index,
    output logic                      read_return_ready,
    output logic                      read_return_fire,
    output logic                      read_pending_full_active
);

    localparam int MEM_ADDR_BITS = $clog2(MEM_WORDS);
    localparam int MEM_WORD_MSB  = 3 + MEM_ADDR_BITS - 1;
    localparam int READ_PENDING_PTR_BITS =
        (READ_PENDING_DEPTH <= 1) ? 1 : $clog2(READ_PENDING_DEPTH);

    logic [APP_ADDR_WIDTH-1:0] read_pending_addr_q [0:READ_PENDING_DEPTH-1];
    int                        read_pending_latency_q [0:READ_PENDING_DEPTH-1];
    logic [READ_PENDING_PTR_BITS-1:0] read_pending_head_q;
    logic [READ_PENDING_PTR_BITS-1:0] read_pending_tail_q;
    int                        read_pending_count_q;
    int                        read_latency_min_cfg;       // Latency floor.
    int                        read_latency_max_cfg;       // Latency ceiling.
    int                        read_pending_depth_cfg;     // Effective depth.
    int                        read_latency_next_q;        // Next latency.
    bit                        plusarg_seen;               // Plusarg sink.

    initial begin
        read_latency_min_cfg   = READ_LATENCY_MIN_CYCLES;
        read_latency_max_cfg   = READ_LATENCY_MAX_CYCLES;
        read_pending_depth_cfg = READ_PENDING_DEPTH;

        plusarg_seen = $value$plusargs("mock_read_latency_min=%d",
                                       read_latency_min_cfg);
        plusarg_seen = $value$plusargs("mock_read_latency_max=%d",
                                       read_latency_max_cfg);
        plusarg_seen = $value$plusargs("mock_read_pending_depth=%d",
                                       read_pending_depth_cfg);

        if ((READ_PENDING_DEPTH <= 0) ||
            (read_pending_depth_cfg <= 0) ||
            (read_pending_depth_cfg > READ_PENDING_DEPTH) ||
            (read_latency_min_cfg < 0) ||
            (read_latency_max_cfg < read_latency_min_cfg)) begin
            $fatal(1, "Invalid DDR fast mock read latency/pending config: min=%0d max=%0d depth=%0d compiled_depth=%0d",
                   read_latency_min_cfg, read_latency_max_cfg,
                   read_pending_depth_cfg, READ_PENDING_DEPTH);
        end
    end

    assign read_mem_index =
        read_pending_addr_q[read_pending_head_q][MEM_WORD_MSB:3];
    assign read_return_ready = (read_pending_count_q != 0) &&
                               (read_pending_latency_q[read_pending_head_q] <= 1);
    assign read_return_fire = read_return_ready && (~data_stall_active);
    assign read_pending_full_active =
        init_calib_complete && (read_pending_count_q >= read_pending_depth_cfg);

    function automatic logic [READ_PENDING_PTR_BITS-1:0] next_read_pending_index(
        input logic [READ_PENDING_PTR_BITS-1:0] index
    );
        begin
            if (index >= (read_pending_depth_cfg - 1)) begin
                next_read_pending_index = '0;
            end
            else begin
                next_read_pending_index = index + 1'b1;
            end
        end
    endfunction

    function automatic int next_read_latency(input int current_latency);
        begin
            if (current_latency >= read_latency_max_cfg) begin
                next_read_latency = read_latency_min_cfg;
            end
            else begin
                next_read_latency = current_latency + 1;
            end
        end
    endfunction

    // Read commands enter a pending queue; each entry returns after its latency.
    always_ff @(posedge clk) begin
        if (reset) begin
            read_pending_head_q  <= '0;
            read_pending_tail_q  <= '0;
            read_pending_count_q <= 0;
            read_latency_next_q  <= read_latency_min_cfg;
            for (int slot = 0; slot < READ_PENDING_DEPTH; slot++) begin
                read_pending_addr_q[slot]    <= '0;
                read_pending_latency_q[slot] <= 0;
            end
        end
        else begin
            if (~data_stall_active) begin
                for (int slot = 0; slot < READ_PENDING_DEPTH; slot++) begin
                    if (read_pending_latency_q[slot] > 0) begin
                        read_pending_latency_q[slot] <=
                            read_pending_latency_q[slot] - 1;
                    end
                end
            end

            if (read_cmd_fire) begin
                read_pending_addr_q[read_pending_tail_q]    <= read_addr;
                read_pending_latency_q[read_pending_tail_q] <= read_latency_next_q;
                read_pending_tail_q <= next_read_pending_index(read_pending_tail_q);
                read_latency_next_q <= next_read_latency(read_latency_next_q);
            end

            if (read_return_fire) begin
                read_pending_head_q <= next_read_pending_index(read_pending_head_q);
            end

            unique case ({read_cmd_fire, read_return_fire})
                2'b10: read_pending_count_q <= read_pending_count_q + 1;
                2'b01: read_pending_count_q <= read_pending_count_q - 1;
                default: read_pending_count_q <= read_pending_count_q;
            endcase
        end
    end

endmodule
