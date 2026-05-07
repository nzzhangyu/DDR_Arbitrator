`timescale 1ns/1ps

module tb_ddr_wr_pingpong_ram;

   localparam int DATA_WIDTH     = 128;
   localparam int BANK_DEPTH     = 16;
   localparam int COMMIT_LEVEL   = 8;
   localparam int COMMIT_TIMEOUT = 20;

   logic                  wr_clk;
   logic                  rd_clk;
   logic                  rst;
   logic [DATA_WIDTH-1:0] din;
   logic                  wr_en;
   logic                  rd_en;
   logic                  flush;
   logic [DATA_WIDTH-1:0] dout;
   logic                  full;
   logic                  empty;
   logic                  valid;
   logic                  prog_empty;
   logic [13:0]           rd_data_count;
   logic                  wr_rst_busy;
   logic                  rd_rst_busy;

   ddr_wr_pingpong_ram #(
      .DATA_WIDTH          (DATA_WIDTH),
      .BANK_DEPTH          (BANK_DEPTH),
      .COMMIT_LEVEL        (COMMIT_LEVEL),
      .COMMIT_TIMEOUT      (COMMIT_TIMEOUT),
      .SKID_DEPTH          (4),
      .READ_LATENCY_CYCLES (2)
   ) dut (
      .dout         (dout),
      .full         (full),
      .empty        (empty),
      .valid        (valid),
      .prog_empty   (prog_empty),
      .rd_data_count(rd_data_count),
      .wr_rst_busy  (wr_rst_busy),
      .rd_rst_busy  (rd_rst_busy),
      .wr_clk       (wr_clk),
      .rd_clk       (rd_clk),
      .rst          (rst),
      .din          (din),
      .wr_en        (wr_en),
      .rd_en        (rd_en),
      .flush        (flush)
   );

   initial wr_clk = 1'b0;
   always #5 wr_clk = ~wr_clk;

   initial rd_clk = 1'b0;
   always #7 rd_clk = ~rd_clk;

   initial begin
      rst   = 1'b1;
      din   = '0;
      wr_en = 1'b0;
      rd_en = 1'b0;
      flush = 1'b0;

      repeat (6) @(posedge wr_clk);
      rst = 1'b0;

      write_range(0, COMMIT_LEVEL);
      read_range(0, COMMIT_LEVEL);

      write_range(100, 3);
      repeat (COMMIT_TIMEOUT + 8) @(posedge wr_clk);
      read_range(100, 3);

      $display("DDR write ping-pong RAM basic test passed");
      $finish;
   end

   task automatic write_range(input int base, input int count);
      int i;
      begin
         for (i = 0; i < count; i++) begin
            @(posedge wr_clk);
            if (full) begin
               $fatal(1, "unexpected full while writing base=%0d index=%0d", base, i);
            end
            din   <= make_word(base + i);
            wr_en <= 1'b1;
         end
         @(posedge wr_clk);
         wr_en <= 1'b0;
         din   <= '0;
      end
   endtask

   task automatic read_range(input int base, input int count);
      int i;
      begin
         for (i = 0; i < count; i++) begin
            wait (valid);
            #1;
            if (dout !== make_word(base + i)) begin
               $fatal(1, "read mismatch index=%0d data=%h expected=%h",
                      i, dout, make_word(base + i));
            end
            @(posedge rd_clk);
            rd_en <= 1'b1;
            @(posedge rd_clk);
            rd_en <= 1'b0;
         end
      end
   endtask

   function automatic logic [127:0] make_word(input int value);
      make_word = {32'hcafe_0000 | value[31:0],
                   32'h1234_0000 | value[31:0],
                   32'h5678_0000 | value[31:0],
                   32'h9abc_0000 | value[31:0]};
   endfunction

endmodule
