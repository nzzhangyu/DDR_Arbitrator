`timescale 1ns/1ps

// Native controller testbench monitor.
// This helper keeps the main controller testbench focused on stimulus and
// scoreboard flow. It owns the diagnostic counters, worst-case assertions, and
// final summary log for FIFO occupancy and native MIG backpressure behavior.
module ddr4_controller_tb_monitor (
   input  logic        ui_clk,
   input  logic        ui_clk_sync_rst,
   input  logic        clk,
   input  logic        reset,
   input  int          log_fd,

   input  bit          worst_check_enable,
   input  int          max_wr_fifo_level_limit,
   input  int          min_rd_fifo_level_limit,
   input  int          max_user_underflow_cycles_limit,
   input  int          max_app_rdy_stall_limit,
   input  int          max_app_wdf_stall_limit,
   input  int          max_read_data_gap_limit,

   input  logic        init_calib_complete,
   input  logic        app_rdy,
   input  logic        app_wdf_rdy,
   input  logic        app_rd_data_valid,
   input  logic        user_r_valid,
   input  logic        user_r_empty,
   input  logic        consumer_enable,
   input  logic        consumer_stall_active,
   input  logic        expected_data_remaining,
   input  logic        native_read_cmd_fire,
   input  logic        native_write_cmd_fire,
   input  logic        in_read_data_state,
   input  logic        urgent_read_data_event_fire,

   input  logic [13:0] wr_fifo_level,
   input  logic        wr_fifo_full,
   input  logic [13:0] rd_fifo_level,
   input  logic        rd_fifo_full,
   input  logic [3:0]  rw_state,
   input  logic [9:0]  read_burst_len,
   input  logic [9:0]  read_beat_cnt,
   input  logic        wr_level_high,
   input  logic        wr_level_urgent,
   input  logic        read_data_fire,

   input  int          sent_count,
   input  int          recv_count,
   input  int          mismatch_count,
   input  int          overflow_count,
   input  int          write_gap_cycle_count,
   input  int          consumer_stall_cycle_count,
   input  int          rd_req_stall_cycle_count,

   output int          native_read_cmd_count,
   output int          native_write_cmd_count,
   output int          read_budget_error_count,
   output int          urgent_interrupt_error_count,
   output int          urgent_read_data_event_count,
   output int          underflow_count,
   output int          monitor_error_count
);

   int   worst_case_error_count;
   int   user_underflow_error_count;
   int   app_rdy_stall_cycle_count;
   int   app_wdf_stall_cycle_count;
   int   read_data_gap_cycle_count;
   int   user_underflow_cycle_count;
   int   app_rdy_stall_run;
   int   app_wdf_stall_run;
   int   read_data_gap_run;
   int   user_underflow_run;
   int   max_app_rdy_stall_run;
   int   max_app_wdf_stall_run;
   int   max_read_data_gap_run;
   int   max_user_underflow_run;
   int   wr_fifo_min_level;
   int   wr_fifo_max_level;
   int   rd_fifo_min_level;
   int   rd_fifo_max_level;
   int   wr_fifo_full_event_count;
   int   rd_fifo_full_event_count;
   int   rd_fifo_empty_event_count;
   logic urgent_read_data_pending;
   logic wr_fifo_limit_reported;
   logic rd_fifo_limit_reported;
   logic app_rdy_limit_reported;
   logic app_wdf_limit_reported;
   logic read_data_gap_limit_reported;
   logic user_underflow_limit_reported;

   assign monitor_error_count = worst_case_error_count + user_underflow_error_count;

   task automatic write_summary(input string result);
      begin
         if (log_fd != 0) begin
            $fdisplay(log_fd, "SUMMARY: result=%s sent=%0d received=%0d mismatch=%0d overflow=%0d underflow=%0d worst_errors=%0d",
                      result, sent_count, recv_count, mismatch_count,
                      overflow_count, underflow_count, monitor_error_count);
            $fdisplay(log_fd, "SUMMARY: wr_fifo_min=%0d wr_fifo_max=%0d wr_fifo_full_events=%0d rd_fifo_min=%0d rd_fifo_max=%0d rd_fifo_full_events=%0d rd_fifo_empty_events=%0d",
                      wr_fifo_min_level, wr_fifo_max_level, wr_fifo_full_event_count,
                      rd_fifo_min_level, rd_fifo_max_level, rd_fifo_full_event_count,
                      rd_fifo_empty_event_count);
            $fdisplay(log_fd, "SUMMARY: max_app_rdy_stall=%0d max_app_wdf_stall=%0d max_read_data_gap=%0d max_user_underflow=%0d",
                      max_app_rdy_stall_run, max_app_wdf_stall_run,
                      max_read_data_gap_run, max_user_underflow_run);
            $fdisplay(log_fd, "SUMMARY: stall_cycles app_rdy=%0d app_wdf=%0d read_data_gap=%0d user_underflow=%0d write_gap=%0d consumer_stall=%0d rd_req_stall=%0d",
                      app_rdy_stall_cycle_count, app_wdf_stall_cycle_count,
                      read_data_gap_cycle_count, user_underflow_cycle_count,
                      write_gap_cycle_count, consumer_stall_cycle_count,
                      rd_req_stall_cycle_count);
            $fdisplay(log_fd, "SUMMARY: native_read_cmds=%0d native_write_cmds=%0d urgent_read_events=%0d read_budget_errors=%0d urgent_interrupt_errors=%0d",
                      native_read_cmd_count, native_write_cmd_count,
                      urgent_read_data_event_count, read_budget_error_count,
                      urgent_interrupt_error_count);
            $fflush(log_fd);
         end
      end
   endtask

   // FIFO levels are sampled from user_app_top internals and passed in by the
   // testbench. This keeps RTL ports unchanged while still recording the real
   // XPM FIFO occupancy envelope under stress.
   always @(posedge ui_clk) begin
      if (ui_clk_sync_rst) begin
         wr_fifo_min_level          <= 16383;
         wr_fifo_max_level          <= 0;
         rd_fifo_min_level          <= 16383;
         rd_fifo_max_level          <= 0;
         wr_fifo_full_event_count   <= 0;
         rd_fifo_full_event_count   <= 0;
         rd_fifo_empty_event_count  <= 0;
         worst_case_error_count     <= 0;
         app_rdy_stall_cycle_count  <= 0;
         app_wdf_stall_cycle_count  <= 0;
         read_data_gap_cycle_count  <= 0;
         app_rdy_stall_run          <= 0;
         app_wdf_stall_run          <= 0;
         read_data_gap_run          <= 0;
         max_app_rdy_stall_run      <= 0;
         max_app_wdf_stall_run      <= 0;
         max_read_data_gap_run      <= 0;
         wr_fifo_limit_reported     <= 1'b0;
         rd_fifo_limit_reported     <= 1'b0;
         app_rdy_limit_reported     <= 1'b0;
         app_wdf_limit_reported     <= 1'b0;
         read_data_gap_limit_reported <= 1'b0;
      end
      else begin
         if (wr_fifo_level < wr_fifo_min_level) wr_fifo_min_level <= wr_fifo_level;
         if (wr_fifo_level > wr_fifo_max_level) wr_fifo_max_level <= wr_fifo_level;
         if (rd_fifo_level < rd_fifo_min_level) rd_fifo_min_level <= rd_fifo_level;
         if (rd_fifo_level > rd_fifo_max_level) rd_fifo_max_level <= rd_fifo_level;
         if (wr_fifo_full) wr_fifo_full_event_count <= wr_fifo_full_event_count + 1;
         if (rd_fifo_full) rd_fifo_full_event_count <= rd_fifo_full_event_count + 1;
         if (user_r_empty) rd_fifo_empty_event_count <= rd_fifo_empty_event_count + 1;

         if (worst_check_enable && (!wr_fifo_limit_reported) &&
             (wr_fifo_level > max_wr_fifo_level_limit)) begin
            worst_case_error_count <= worst_case_error_count + 1;
            wr_fifo_limit_reported <= 1'b1;
            $fdisplay(log_fd, "ERROR/WORST: wr_fifo_level exceeded limit at %0t: level=%0d limit=%0d state=%0d",
                      $time, wr_fifo_level, max_wr_fifo_level_limit, rw_state);
            $error("Worst-case write FIFO level exceeded at %0t: level=%0d limit=%0d",
                   $time, wr_fifo_level, max_wr_fifo_level_limit);
         end

         if (worst_check_enable && (!rd_fifo_limit_reported) &&
             consumer_enable && (!consumer_stall_active) &&
             expected_data_remaining && (rd_fifo_level < min_rd_fifo_level_limit)) begin
            worst_case_error_count <= worst_case_error_count + 1;
            rd_fifo_limit_reported <= 1'b1;
            $fdisplay(log_fd, "ERROR/WORST: rd_fifo_level below limit at %0t: level=%0d limit=%0d state=%0d",
                      $time, rd_fifo_level, min_rd_fifo_level_limit, rw_state);
            $error("Worst-case read FIFO level below limit at %0t: level=%0d limit=%0d",
                   $time, rd_fifo_level, min_rd_fifo_level_limit);
         end

         update_stall_window(app_rdy, app_rdy_stall_run, max_app_rdy_stall_run,
                             app_rdy_stall_cycle_count, app_rdy_limit_reported,
                             max_app_rdy_stall_limit, "app_rdy");
         update_stall_window(app_wdf_rdy, app_wdf_stall_run, max_app_wdf_stall_run,
                             app_wdf_stall_cycle_count, app_wdf_limit_reported,
                             max_app_wdf_stall_limit, "app_wdf_rdy");

         // Read-data gaps are only meaningful while the native state machine is
         // waiting for a read return beat.
         if (in_read_data_state && (!app_rd_data_valid)) begin
            read_data_gap_cycle_count <= read_data_gap_cycle_count + 1;
            read_data_gap_run <= read_data_gap_run + 1;
            if ((read_data_gap_run + 1) > max_read_data_gap_run) begin
               max_read_data_gap_run <= read_data_gap_run + 1;
            end
            if (worst_check_enable && (!read_data_gap_limit_reported) &&
                (max_read_data_gap_limit >= 0) &&
                ((read_data_gap_run + 1) > max_read_data_gap_limit)) begin
               worst_case_error_count <= worst_case_error_count + 1;
               read_data_gap_limit_reported <= 1'b1;
               $fdisplay(log_fd, "ERROR/WORST: read data gap exceeded limit at %0t: run=%0d limit=%0d state=%0d",
                         $time, read_data_gap_run + 1, max_read_data_gap_limit, rw_state);
               $error("Worst-case read data gap exceeded at %0t: run=%0d limit=%0d",
                      $time, read_data_gap_run + 1, max_read_data_gap_limit);
            end
         end
         else begin
            read_data_gap_run <= 0;
         end
      end
   end

   task automatic update_stall_window(
      input  logic ready_signal,
      inout  int   run_count,
      inout  int   max_run_count,
      inout  int   cycle_count,
      inout  logic limit_reported,
      input  int   limit,
      input  string name
   );
      begin
         if (init_calib_complete && (!ready_signal)) begin
            cycle_count = cycle_count + 1;
            run_count = run_count + 1;
            if (run_count > max_run_count) max_run_count = run_count;
            if (worst_check_enable && (!limit_reported) && (limit >= 0) &&
                (run_count > limit)) begin
               worst_case_error_count = worst_case_error_count + 1;
               limit_reported = 1'b1;
               $fdisplay(log_fd, "ERROR/WORST: %s stall exceeded limit at %0t: run=%0d limit=%0d state=%0d",
                         name, $time, run_count, limit, rw_state);
               $error("Worst-case %s stall exceeded at %0t: run=%0d limit=%0d",
                      name, $time, run_count, limit);
            end
         end
         else begin
            run_count = 0;
         end
      end
   endtask

   // Business-underflow is checked in the user clock domain. Testbench-injected
   // consumer stalls are excluded; a gap is only an error candidate when the
   // consumer is allowed to read and pending expected data exists.
   always @(posedge clk) begin
      if (reset) begin
         underflow_count <= 0;
         user_underflow_error_count <= 0;
         user_underflow_cycle_count <= 0;
         user_underflow_run <= 0;
         max_user_underflow_run <= 0;
         user_underflow_limit_reported <= 1'b0;
      end
      else if (consumer_enable && (!consumer_stall_active) &&
               expected_data_remaining && (!user_r_valid)) begin
         underflow_count <= underflow_count + 1;
         user_underflow_cycle_count <= user_underflow_cycle_count + 1;
         user_underflow_run <= user_underflow_run + 1;
         if ((user_underflow_run + 1) > max_user_underflow_run) begin
            max_user_underflow_run <= user_underflow_run + 1;
         end
         if (worst_check_enable && (!user_underflow_limit_reported) &&
             ((user_underflow_run + 1) > max_user_underflow_cycles_limit)) begin
            user_underflow_error_count <= user_underflow_error_count + 1;
            user_underflow_limit_reported <= 1'b1;
            $fdisplay(log_fd, "ERROR/WORST: user read underflow exceeded limit at %0t: run=%0d limit=%0d sent=%0d received=%0d",
                      $time, user_underflow_run + 1,
                      max_user_underflow_cycles_limit, sent_count, recv_count);
            $error("Worst-case user read underflow exceeded at %0t: run=%0d limit=%0d",
                   $time, user_underflow_run + 1, max_user_underflow_cycles_limit);
         end
      end
      else begin
         user_underflow_run <= 0;
      end
   end

   // Native arbitration policy checks and command counters.
   always @(posedge ui_clk) begin
      if (ui_clk_sync_rst) begin
         native_read_cmd_count        <= 0;
         native_write_cmd_count       <= 0;
         read_budget_error_count      <= 0;
         urgent_interrupt_error_count <= 0;
         urgent_read_data_event_count <= 0;
         urgent_read_data_pending     <= 1'b0;
      end
      else begin
         if (native_read_cmd_fire) native_read_cmd_count <= native_read_cmd_count + 1;
         if (native_write_cmd_fire) native_write_cmd_count <= native_write_cmd_count + 1;

         if (read_burst_len > 10'd512) begin
            read_budget_error_count <= read_budget_error_count + 1;
            $fdisplay(log_fd, "ERROR: Native read budget exceeded 512 at %0t: read_burst_len=%0d state=%0d",
                      $time, read_burst_len, rw_state);
            $error("Native read budget exceeded 512 at %0t: read_burst_len=%0d state=%0d",
                   $time, read_burst_len, rw_state);
         end

         if (native_read_cmd_fire && (read_beat_cnt == 10'd0) &&
             wr_level_high && (read_burst_len > 10'd128)) begin
            read_budget_error_count <= read_budget_error_count + 1;
            $fdisplay(log_fd, "ERROR: Native read command exceeded high-write budget at %0t: read_burst_len=%0d state=%0d",
                      $time, read_burst_len, rw_state);
            $error("Native read command exceeded high-write budget at %0t: read_burst_len=%0d state=%0d",
                   $time, read_burst_len, rw_state);
         end

         if (native_read_cmd_fire && wr_level_urgent) begin
            urgent_interrupt_error_count <= urgent_interrupt_error_count + 1;
            $fdisplay(log_fd, "ERROR: Native read command accepted while write FIFO urgent at %0t: state=%0d",
                      $time, rw_state);
            $error("Native read command accepted while write FIFO urgent at %0t: state=%0d",
                   $time, rw_state);
         end

         if (urgent_read_data_event_fire && (!urgent_read_data_pending)) begin
            urgent_read_data_event_count <= urgent_read_data_event_count + 1;
            urgent_read_data_pending     <= 1'b1;
         end
         if ((urgent_read_data_pending ||
              (urgent_read_data_event_fire && (!urgent_read_data_pending))) &&
             read_data_fire) begin
            urgent_read_data_pending <= 1'b0;
         end
         else if ((!in_read_data_state) && urgent_read_data_pending) begin
            urgent_interrupt_error_count <= urgent_interrupt_error_count + 1;
            urgent_read_data_pending     <= 1'b0;
            $fdisplay(log_fd, "ERROR: Native read service left RW_READ_DATA before urgent read data returned at %0t: state=%0d",
                      $time, rw_state);
            $error("Native read service left RW_READ_DATA before urgent read data returned at %0t: state=%0d",
                   $time, rw_state);
         end
      end
   end

endmodule
