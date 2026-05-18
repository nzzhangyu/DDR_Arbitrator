`timescale 1ns/1ps

// Fast native-app DDR mock with coarse backpressure.
module ddr4_fast_mock #(
    parameter int APP_ADDR_WIDTH      = 32,
    parameter int MEM_WORDS           = 16384,
    parameter int CALIB_DELAY_CYCLES  = 32,
    parameter int READ_LATENCY_CYCLES = 2,
    parameter int REFRESH_INTERVAL_CYCLES = 0,
    parameter int REFRESH_BLOCK_CYCLES    = 0,
    parameter int MAINT_INTERVAL_CYCLES   = 0,
    parameter int MAINT_BLOCK_CYCLES      = 0,
    parameter int READY_STALL_INTERVAL_CYCLES = 0,
    parameter int READY_STALL_CYCLES          = 0,
    parameter int READ_DATA_GAP_INTERVAL_CYCLES = 0,
    parameter int READ_DATA_GAP_CYCLES          = 0,
    parameter int TURNAROUND_CYCLES     = 0,
    parameter int RTW_TURNAROUND_CYCLES = TURNAROUND_CYCLES,
    parameter int WTR_TURNAROUND_CYCLES = TURNAROUND_CYCLES,
    parameter int CMD_QUEUE_DEPTH = 0,
    parameter int CMD_DRAIN_INTERVAL_CYCLES = 1
) (
    input  logic                      clk_in,
    input  logic                      RESET,

    // MIG user clock/status.
    output logic                      ui_clk,
    output logic                      ui_clk_sync_rst,
    output logic                      init_calib_complete,
    output logic                      dbg_clk,

    // App command channel.
    input  logic [APP_ADDR_WIDTH-1:0] app_addr,
    input  logic [2:0]                app_cmd,
    input  logic                      app_en,
    output logic                      app_rdy,

    // Write-data channel.
    input  logic [127:0]              app_wdf_data,
    input  logic [15:0]               app_wdf_mask,
    input  logic                      app_wdf_wren,
    input  logic                      app_wdf_end,
    output logic                      app_wdf_rdy,

    // Read-data channel.
    output logic [127:0]              app_rd_data,
    output logic                      app_rd_data_valid,
    output logic                      app_rd_data_end
    );

    // 128-bit word memory; app_addr[3:0] is byte offset.
    localparam int MEM_ADDR_BITS = $clog2(MEM_WORDS);
    localparam int MEM_WORD_MSB  = 4 + MEM_ADDR_BITS - 1;
    localparam logic [2:0] APP_CMD_WRITE = 3'b000;
    localparam logic [2:0] APP_CMD_READ  = 3'b001;

    // Behavioral storage.
    logic [127:0] mem [0:MEM_WORDS-1];
    logic [7:0]   calib_cnt;

    logic [APP_ADDR_WIDTH-1:0] write_addr_q;
    logic                      write_cmd_pending_q;

    // Read latency pipe.
    logic [APP_ADDR_WIDTH-1:0]    read_addr_pipe [0:READ_LATENCY_CYCLES];
    logic [READ_LATENCY_CYCLES:0] read_valid_pipe;

    logic [MEM_ADDR_BITS-1:0] write_mem_index;
    logic [MEM_ADDR_BITS-1:0] read_mem_index;
    logic                     cmd_stall_active;            // Command stall.
    logic                     data_stall_active;           // Read-data stall.
    logic                     read_pipe_stall;             // Read pipe hold.
    logic                     turn_write_block;            // Read-to-write block.
    logic                     turn_read_block;             // Write-to-read block.
    logic                     write_cmd_fire;              // Accepted write command.
    logic                     read_cmd_fire;               // Accepted read command.
    logic                     refresh_active;              // Refresh stall reason.
    logic                     maint_active;                // Maintenance stall reason.
    logic                     ready_stall_active;          // Ready stall reason.
    logic                     read_gap_active;             // Read gap reason.
    logic                     turnaround_active;           // Turnaround reason.
    logic                     cmd_queue_full_active;       // Command queue full.

    integer i;

    initial begin
        for (i = 0; i < MEM_WORDS; i++) begin
            mem[i] = '0;
        end
    end

    // Clock aliases.
    assign ui_clk = clk_in;
    assign dbg_clk = clk_in;
    assign ui_clk_sync_rst = RESET | (~init_calib_complete);

    // Coarse stall and turnaround model.
    ddr4_fast_mock_stall_model #(
        .REFRESH_INTERVAL_CYCLES       (REFRESH_INTERVAL_CYCLES),
        .REFRESH_BLOCK_CYCLES          (REFRESH_BLOCK_CYCLES),
        .MAINT_INTERVAL_CYCLES         (MAINT_INTERVAL_CYCLES),
        .MAINT_BLOCK_CYCLES            (MAINT_BLOCK_CYCLES),
        .READY_STALL_INTERVAL_CYCLES   (READY_STALL_INTERVAL_CYCLES),
        .READY_STALL_CYCLES            (READY_STALL_CYCLES),
        .READ_DATA_GAP_INTERVAL_CYCLES (READ_DATA_GAP_INTERVAL_CYCLES),
        .READ_DATA_GAP_CYCLES          (READ_DATA_GAP_CYCLES),
        .TURNAROUND_CYCLES             (TURNAROUND_CYCLES),
        .RTW_TURNAROUND_CYCLES         (RTW_TURNAROUND_CYCLES),
        .WTR_TURNAROUND_CYCLES         (WTR_TURNAROUND_CYCLES),
        .CMD_QUEUE_DEPTH               (CMD_QUEUE_DEPTH),
        .CMD_DRAIN_INTERVAL_CYCLES     (CMD_DRAIN_INTERVAL_CYCLES)
    ) stall_model_u (
        .clk                    (clk_in),
        .reset                  (RESET),
        .init_calib_complete    (init_calib_complete),
        .app_en                 (app_en),
        .app_cmd                (app_cmd),
        .app_rdy                (app_rdy),
        .read_pipe_output_valid (read_valid_pipe[READ_LATENCY_CYCLES]),
        .cmd_stall_active       (cmd_stall_active),
        .data_stall_active      (data_stall_active),
        .read_pipe_stall        (read_pipe_stall),
        .turn_write_block       (turn_write_block),
        .turn_read_block        (turn_read_block),
        .refresh_active         (refresh_active),
        .maint_active           (maint_active),
        .ready_stall_active     (ready_stall_active),
        .read_gap_active        (read_gap_active),
        .turnaround_active      (turnaround_active),
        .cmd_queue_full_active  (cmd_queue_full_active)
    );

    assign app_rdy = init_calib_complete &&
                        (~write_cmd_pending_q) &&
                        (~cmd_stall_active) &&
                        (~read_pipe_stall) &&
                        (~(turn_write_block && (app_cmd == APP_CMD_WRITE))) &&
                        (~(turn_read_block && (app_cmd == APP_CMD_READ)));
    assign app_wdf_rdy = init_calib_complete && (~cmd_stall_active);
    assign write_mem_index = write_addr_q[MEM_WORD_MSB:4];
    assign read_mem_index = read_addr_pipe[READ_LATENCY_CYCLES][MEM_WORD_MSB:4];
    assign app_rd_data = mem[read_mem_index];
    assign app_rd_data_valid = read_valid_pipe[READ_LATENCY_CYCLES] && (~data_stall_active);
    assign app_rd_data_end = app_rd_data_valid;
    assign write_cmd_fire = app_en && app_rdy && (app_cmd == APP_CMD_WRITE);
    assign read_cmd_fire  = app_en && app_rdy && (app_cmd == APP_CMD_READ);

   // Mock calibration delay.
   always_ff @(posedge clk_in) begin
      if (RESET) begin
         calib_cnt           <= '0;
         init_calib_complete <= 1'b0;
        end
        else if (~init_calib_complete) begin
            if ((CALIB_DELAY_CYCLES <= 1) ||
                (calib_cnt >= (CALIB_DELAY_CYCLES - 1))) begin
                init_calib_complete <= 1'b1;
            end
            else begin
                calib_cnt <= calib_cnt + 8'd1;
            end
        end
    end

    // Write command/data pairing.
    always_ff @(posedge clk_in) begin
        if (RESET) begin
            write_addr_q        <= '0;
            write_cmd_pending_q <= 1'b0;
        end
        else begin
            if (write_cmd_fire && app_wdf_wren && app_wdf_rdy && app_wdf_end) begin
                integer byte_idx;
                logic [127:0] next_word;
                logic [MEM_ADDR_BITS-1:0] direct_write_index;

                // Same-cycle write.
                direct_write_index = app_addr[MEM_WORD_MSB:4];
                next_word = mem[direct_write_index];
                for (byte_idx = 0; byte_idx < 16; byte_idx++) begin
                    if (~app_wdf_mask[byte_idx]) begin
                        next_word[byte_idx*8 +: 8] = app_wdf_data[byte_idx*8 +: 8];
                    end
                end
                mem[direct_write_index] <= next_word;
            end
            else if (write_cmd_fire) begin
                write_addr_q        <= app_addr;
                write_cmd_pending_q <= 1'b1;
            end

            if (write_cmd_pending_q && app_wdf_wren && app_wdf_rdy && app_wdf_end) begin
                integer byte_idx;
                logic [127:0] next_word;

                // Delayed write data.
                next_word = mem[write_mem_index];
                for (byte_idx = 0; byte_idx < 16; byte_idx++) begin
                    if (~app_wdf_mask[byte_idx]) begin
                        next_word[byte_idx*8 +: 8] = app_wdf_data[byte_idx*8 +: 8];
                    end
                end
                mem[write_mem_index] <= next_word;
                write_cmd_pending_q  <= 1'b0;
            end
        end
    end

    // Read latency pipe with output hold.
    always_ff @(posedge clk_in) begin
        if (RESET) begin
            read_valid_pipe <= '0;
            for (int stage = 0; stage <= READ_LATENCY_CYCLES; stage++) begin
                read_addr_pipe[stage] <= '0;
            end
        end
        else if (~read_pipe_stall) begin
            read_valid_pipe[0] <= read_cmd_fire;
            read_addr_pipe[0]  <= app_addr;

            for (int stage = 1; stage <= READ_LATENCY_CYCLES; stage++) begin
                read_valid_pipe[stage] <= read_valid_pipe[stage-1];
                read_addr_pipe[stage]  <= read_addr_pipe[stage-1];
            end
        end
    end

endmodule
