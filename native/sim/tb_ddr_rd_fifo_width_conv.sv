`timescale 1ns/1ps

module tb_ddr_rd_fifo_width_conv;

    localparam int FIFO_WRITE_DEPTH = 8192;

    logic         wr_clk;
    logic         rd_clk;
    logic         rst;
    logic [127:0] raw_word;
    logic [127:0] fifo_din;
    logic [63:0]  fifo_dout;
    logic         wr_en;
    logic         rd_en;
    logic         data_valid;
    logic         empty;
    logic         full;
    logic         wr_rst_busy;
    logic         rd_rst_busy;
    logic [13:0]  wr_data_count;

    assign fifo_din = {raw_word[63:0], raw_word[127:64]};

    xpm_fifo_async #(
        .CASCADE_HEIGHT      (0),
        .CDC_SYNC_STAGES     (2),
        .DOUT_RESET_VALUE    ("0"),
        .ECC_MODE            ("no_ecc"),
        .FIFO_MEMORY_TYPE    ("auto"),
        .FIFO_READ_LATENCY   (0),
        .FIFO_WRITE_DEPTH    (FIFO_WRITE_DEPTH),
        .FULL_RESET_VALUE    (0),
        .PROG_EMPTY_THRESH   (256),
        .PROG_FULL_THRESH    (6144),
        .RD_DATA_COUNT_WIDTH (15),
        .READ_DATA_WIDTH     (64),
        .READ_MODE           ("fwft"),
        .RELATED_CLOCKS      (0),
        .SIM_ASSERT_CHK      (0),
        .USE_ADV_FEATURES    ("1F1F"),
        .WAKEUP_TIME         (0),
        .WRITE_DATA_WIDTH    (128),
        .WR_DATA_COUNT_WIDTH (14)
    ) dut (
        .data_valid    (data_valid),
        .dout          (fifo_dout),
        .empty         (empty),
        .full          (full),
        .wr_data_count (wr_data_count),
        .din           (fifo_din),
        .injectdbiterr (1'b0),
        .injectsbiterr (1'b0),
        .rd_clk        (rd_clk),
        .rd_en         (rd_en),
        .rst           (rst),
        .sleep         (1'b0),
        .wr_clk        (wr_clk),
        .wr_en         (wr_en),
        .wr_rst_busy   (wr_rst_busy),
        .rd_rst_busy   (rd_rst_busy)
    );

    initial begin
        wr_clk = 1'b0;
        forever #1.667 wr_clk = ~wr_clk;
    end

    initial begin
        rd_clk = 1'b0;
        forever #2.5 rd_clk = ~rd_clk;
    end

    initial begin
        rst      = 1'b1;
        raw_word = '0;
        wr_en    = 1'b0;
        rd_en    = 1'b0;

        #120ns;
        repeat (10) @(posedge wr_clk);
        rst = 1'b0;
        wait ((!wr_rst_busy) && (!rd_rst_busy));

        push_word(128'h1111_2222_3333_4444_5555_6666_7777_8888);
        push_word(128'h9999_aaaa_bbbb_cccc_dddd_eeee_ffff_0001);

        pop_check(64'h1111_2222_3333_4444);
        pop_check(64'h5555_6666_7777_8888);
        pop_check(64'h9999_aaaa_bbbb_cccc);
        pop_check(64'hdddd_eeee_ffff_0001);

        repeat (4) @(posedge rd_clk);
        if (!empty) begin
            $fatal(1, "Width-conversion FIFO did not empty after four 64-bit reads");
        end

        $display("DDR read FIFO 128-to-64 high-half-first test passed");
        $finish;
    end

    task automatic push_word(input logic [127:0] word);
        begin
            @(negedge wr_clk);
            raw_word = word;
            wr_en    = 1'b1;
            @(negedge wr_clk);
            wr_en    = 1'b0;
        end
    endtask

    task automatic pop_check(input logic [63:0] expected);
        begin
            wait (data_valid);
            @(negedge rd_clk);
            if (fifo_dout !== expected) begin
                $fatal(1, "64-bit output mismatch: data=%h expected=%h",
                       fifo_dout, expected);
            end
            rd_en = 1'b1;
            @(negedge rd_clk);
            rd_en = 1'b0;
        end
    endtask

endmodule
