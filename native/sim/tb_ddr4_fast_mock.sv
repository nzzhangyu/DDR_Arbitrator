`timescale 1ns/1ps

module tb_ddr4_fast_mock;

   localparam int APP_ADDR_WIDTH = 32;

   logic                      clk;
   logic                      reset;
   logic                      ui_clk;
   logic                      ui_clk_sync_rst;
   logic                      init_calib_complete;
   logic                      dbg_clk;
   logic [APP_ADDR_WIDTH-1:0] app_addr;
   logic [2:0]                app_cmd;
   logic                      app_en;
   logic                      app_rdy;
   logic [127:0]              app_wdf_data;
   logic [15:0]               app_wdf_mask;
   logic                      app_wdf_wren;
   logic                      app_wdf_end;
   logic                      app_wdf_rdy;
   logic [127:0]              app_rd_data;
   logic                      app_rd_data_valid;
   logic                      app_rd_data_end;

   ddr4_fast_mock #(
      .APP_ADDR_WIDTH     (APP_ADDR_WIDTH),
      .MEM_WORDS          (1024),
      .CALIB_DELAY_CYCLES (4),
      .READ_LATENCY_CYCLES(2)
   ) dut (
      .clk_in             (clk),
      .RESET              (reset),
      .ui_clk             (ui_clk),
      .ui_clk_sync_rst    (ui_clk_sync_rst),
      .init_calib_complete(init_calib_complete),
      .dbg_clk            (dbg_clk),
      .app_addr           (app_addr),
      .app_cmd            (app_cmd),
      .app_en             (app_en),
      .app_rdy            (app_rdy),
      .app_wdf_data       (app_wdf_data),
      .app_wdf_mask       (app_wdf_mask),
      .app_wdf_wren       (app_wdf_wren),
      .app_wdf_end        (app_wdf_end),
      .app_wdf_rdy        (app_wdf_rdy),
      .app_rd_data        (app_rd_data),
      .app_rd_data_valid  (app_rd_data_valid),
      .app_rd_data_end    (app_rd_data_end)
   );

   initial begin
      clk = 1'b0;
      forever #5 clk = ~clk;
   end

   initial begin
      reset = 1'b1;
      app_addr = '0;
      app_cmd = '0;
      app_en = 1'b0;
      app_wdf_data = '0;
      app_wdf_mask = '0;
      app_wdf_wren = 1'b0;
      app_wdf_end = 1'b0;

      repeat (5) @(posedge clk);
      reset <= 1'b0;
      wait (init_calib_complete);
      repeat (2) @(posedge clk);

      native_write(32'h0000_0010, 128'h1111_2222_3333_4444_5555_6666_7777_8888);
      native_write(32'h0000_0020, 128'h9999_aaaa_bbbb_cccc_dddd_eeee_ffff_0001);
      native_read_check(32'h0000_0010, 128'h1111_2222_3333_4444_5555_6666_7777_8888);
      native_read_check(32'h0000_0020, 128'h9999_aaaa_bbbb_cccc_dddd_eeee_ffff_0001);

      $display("DDR4 native fast mock basic test passed");
      $finish;
   end

   task automatic native_write(input logic [APP_ADDR_WIDTH-1:0] addr,
                               input logic [127:0] data);
      begin
         @(posedge clk);
         app_addr <= addr;
         app_cmd <= 3'b000;
         app_en <= 1'b1;
         wait (app_rdy);
         @(posedge clk);
         app_en <= 1'b0;

         app_wdf_data <= data;
         app_wdf_mask <= 16'h0000;
         app_wdf_wren <= 1'b1;
         app_wdf_end <= 1'b1;
         wait (app_wdf_rdy);
         @(posedge clk);
         app_wdf_wren <= 1'b0;
         app_wdf_end <= 1'b0;
      end
   endtask

   task automatic native_read_check(input logic [APP_ADDR_WIDTH-1:0] addr,
                                    input logic [127:0] expected);
      begin
         @(posedge clk);
         app_addr <= addr;
         app_cmd <= 3'b001;
         app_en <= 1'b1;
         wait (app_rdy);
         @(posedge clk);
         app_en <= 1'b0;

         wait (app_rd_data_valid);
         if (app_rd_data !== expected || ~app_rd_data_end) begin
            $fatal(1, "native read mismatch: data=%h expected=%h end=%b",
                   app_rd_data, expected, app_rd_data_end);
         end
         @(posedge clk);
      end
   endtask

endmodule
