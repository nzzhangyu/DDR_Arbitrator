`timescale 1ns/1ps

module tb_native_perf_monitor;
    localparam int WINDOW_CYCLES = 16;

    logic clk = 1'b0;
    logic rst = 1'b1;
    logic ddr_wr_req, ddr_rd_req_qual;
    logic write_data_fire, read_cmd_fire, read_data_fire;
    logic block_for_replay;
    logic in_idle, in_arb, in_write_req, in_read_cmd, in_read_data;
    logic grant_write, grant_read;
    logic wr_fifo_valid;
    logic [8:0] write_burst_len;
    logic read_cmd_send_en;
    logic app_rdy, app_wdf_rdy, app_rd_data_valid;
    logic rd_fifo_has_grant_space;
    logic wr_level_urgent, rd_level_urgent, req_stop;
    logic wr_fifo_full, rd_fifo_full;
    logic [14:0] wr_fifo_data_count;
    logic [15:0] rd_fifo_data_count;
    logic write_burst_done, read_burst_done, read_cmd_stop_event;
    logic [9:0] rd_outstanding;

    always #1 clk = ~clk;

    native_perf_monitor #(
        .COUNTER_WIDTH      (48),
        .PERF_WINDOW_CYCLES (WINDOW_CYCLES)
    ) dut (.*,
        .ui_clk (clk)
    );

    task automatic drive_cycle(input int n);
        begin
            ddr_wr_req = (n < 8);
            ddr_rd_req_qual = (n >= 4 && n < 12);
            write_data_fire = (n == 0 || n == 1);
            read_cmd_fire = (n == 2 || n == 3);
            read_data_fire = (n == 4 || n == 5);
            block_for_replay = (n == 14);
            in_idle = ((n % 5) == 0);
            in_arb = ((n % 5) == 1);
            in_write_req = ((n % 5) == 2);
            in_read_cmd = ((n % 5) == 3);
            in_read_data = ((n % 5) == 4);
            grant_write = (n == 1);
            grant_read = (n == 6);
            wr_fifo_valid = 1'b1;
            write_burst_len = 9'd4;
            read_cmd_send_en = (n == 3);
            app_rdy = (n != 3);
            app_wdf_rdy = (n != 7);
            app_rd_data_valid = (n == 4 || n == 5 || n == 13);
            rd_fifo_has_grant_space = (n != 9);
            wr_level_urgent = (n >= 6 && n <= 8);
            rd_level_urgent = (n >= 10 && n <= 11);
            req_stop = (n == 8);
            wr_fifo_full = (n == 12);
            rd_fifo_full = (n == 13);
            wr_fifo_data_count = n;
            rd_fifo_data_count = n * 2;
            write_burst_done = (n == 1);
            read_burst_done = (n == 5);
            read_cmd_stop_event = (n == 8);
            rd_outstanding = (n == 12) ? 10'd7 : ((n == 15) ? 10'd3 : n[9:0]);
        end
    endtask

    initial begin
        ddr_wr_req = 0; ddr_rd_req_qual = 0;
        write_data_fire = 0; read_cmd_fire = 0; read_data_fire = 0;
        block_for_replay = 0; in_idle = 0; in_arb = 0; in_write_req = 0;
        in_read_cmd = 0; in_read_data = 0; grant_write = 0; grant_read = 0;
        wr_fifo_valid = 0; write_burst_len = 0; read_cmd_send_en = 0;
        app_rdy = 0; app_wdf_rdy = 0; app_rd_data_valid = 0;
        rd_fifo_has_grant_space = 0; wr_level_urgent = 0; rd_level_urgent = 0;
        req_stop = 0; wr_fifo_full = 0; rd_fifo_full = 0;
        wr_fifo_data_count = 0; rd_fifo_data_count = 0;
        write_burst_done = 0; read_burst_done = 0; read_cmd_stop_event = 0;
        rd_outstanding = 0;

        repeat (2) @(posedge clk);
        @(negedge clk) rst = 1'b0;
        for (int n = 0; n < WINDOW_CYCLES; n++) begin
            drive_cycle(n);
            @(posedge clk);
            @(negedge clk);
        end
        #1;

        assert (dut.perf_snapshot_valid && dut.perf_snapshot_seq == 1)
            else $fatal(1, "snapshot control failed");
        assert (dut.perf_window_cycles == WINDOW_CYCLES)
            else $fatal(1, "window count failed");
        assert (dut.perf_wr_fire_count == 2 && dut.perf_rd_cmd_fire_count == 2 &&
                dut.perf_rd_data_fire_count == 2 && dut.perf_cmd_fire_count == 4 &&
                dut.perf_payload_count == 4)
            else $fatal(1, "throughput counters failed");
        assert (dut.perf_idle_cycles + dut.perf_arb_cycles +
                dut.perf_write_state_cycles + dut.perf_read_cmd_state_cycles +
                dut.perf_read_data_state_cycles == WINDOW_CYCLES)
            else $fatal(1, "state residency invariant failed");
        assert (dut.perf_wr_urgent_cycles == 3 && dut.perf_wr_urgent_events == 1 &&
                dut.perf_rd_urgent_cycles == 2 && dut.perf_rd_urgent_events == 1)
            else $fatal(1, "urgent counters failed");
        assert (dut.perf_wr_fifo_min == 0 && dut.perf_wr_fifo_max == 15 &&
                dut.perf_rd_fifo_min == 0 && dut.perf_rd_fifo_max == 30)
            else $fatal(1, "FIFO extrema failed");
        assert (dut.perf_rd_outstanding_max == 14 && dut.perf_rd_outstanding_end == 3)
            else $fatal(1, "outstanding tracking failed");
        assert (dut.perf_rd_cmd_stop_count == 1 && dut.perf_wr_burst_done_count == 1 &&
                dut.perf_rd_burst_done_count == 1)
            else $fatal(1, "burst quality counters failed");
        assert (!dut.perf_counter_overflow)
            else $fatal(1, "unexpected counter overflow");

        $display("native_perf_monitor directed test passed");
        $finish;
    end
endmodule
