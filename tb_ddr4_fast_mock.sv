`timescale 1ns/1ps

module tb_ddr4_fast_mock;

   localparam int AXI_ADDR_WIDTH = 32;
   localparam int AXI_ID_WIDTH   = 1;

   logic clk;
   logic rst;

   logic                      ui_clk;
   logic                      ui_clk_sync_rst;
   logic                      init_calib_complete;
   logic                      dbg_clk;

   logic [AXI_ID_WIDTH-1:0]   axi_awid;
   logic [AXI_ADDR_WIDTH-1:0] axi_awaddr;
   logic [7:0]                axi_awlen;
   logic [2:0]                axi_awsize;
   logic [1:0]                axi_awburst;
   logic                      axi_awlock;
   logic [3:0]                axi_awcache;
   logic [2:0]                axi_awprot;
   logic [3:0]                axi_awqos;
   logic                      axi_awvalid;
   logic                      axi_awready;
   logic [127:0]              axi_wdata;
   logic [15:0]               axi_wstrb;
   logic                      axi_wlast;
   logic                      axi_wvalid;
   logic                      axi_wready;
   logic [AXI_ID_WIDTH-1:0]   axi_bid;
   logic [1:0]                axi_bresp;
   logic                      axi_bvalid;
   logic                      axi_bready;
   logic [AXI_ID_WIDTH-1:0]   axi_arid;
   logic [AXI_ADDR_WIDTH-1:0] axi_araddr;
   logic [7:0]                axi_arlen;
   logic [2:0]                axi_arsize;
   logic [1:0]                axi_arburst;
   logic                      axi_arlock;
   logic [3:0]                axi_arcache;
   logic [2:0]                axi_arprot;
   logic [3:0]                axi_arqos;
   logic                      axi_arvalid;
   logic                      axi_arready;
   logic [AXI_ID_WIDTH-1:0]   axi_rid;
   logic [127:0]              axi_rdata;
   logic [1:0]                axi_rresp;
   logic                      axi_rlast;
   logic                      axi_rvalid;
   logic                      axi_rready;

   ddr4_fast_mock #(
      .AXI_ADDR_WIDTH     (AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH       (AXI_ID_WIDTH),
      .MEM_WORDS          (1024),
      .CALIB_DELAY_CYCLES (4),
      .READ_LATENCY_CYCLES(1)
   ) dut (
      .clk_in             (clk),
      .RESET              (rst),
      .ui_clk             (ui_clk),
      .ui_clk_sync_rst    (ui_clk_sync_rst),
      .init_calib_complete(init_calib_complete),
      .dbg_clk            (dbg_clk),
      .axi_awid           (axi_awid),
      .axi_awaddr         (axi_awaddr),
      .axi_awlen          (axi_awlen),
      .axi_awsize         (axi_awsize),
      .axi_awburst        (axi_awburst),
      .axi_awlock         (axi_awlock),
      .axi_awcache        (axi_awcache),
      .axi_awprot         (axi_awprot),
      .axi_awqos          (axi_awqos),
      .axi_awvalid        (axi_awvalid),
      .axi_awready        (axi_awready),
      .axi_wdata          (axi_wdata),
      .axi_wstrb          (axi_wstrb),
      .axi_wlast          (axi_wlast),
      .axi_wvalid         (axi_wvalid),
      .axi_wready         (axi_wready),
      .axi_bid            (axi_bid),
      .axi_bresp          (axi_bresp),
      .axi_bvalid         (axi_bvalid),
      .axi_bready         (axi_bready),
      .axi_arid           (axi_arid),
      .axi_araddr         (axi_araddr),
      .axi_arlen          (axi_arlen),
      .axi_arsize         (axi_arsize),
      .axi_arburst        (axi_arburst),
      .axi_arlock         (axi_arlock),
      .axi_arcache        (axi_arcache),
      .axi_arprot         (axi_arprot),
      .axi_arqos          (axi_arqos),
      .axi_arvalid        (axi_arvalid),
      .axi_arready        (axi_arready),
      .axi_rid            (axi_rid),
      .axi_rdata          (axi_rdata),
      .axi_rresp          (axi_rresp),
      .axi_rlast          (axi_rlast),
      .axi_rvalid         (axi_rvalid),
      .axi_rready         (axi_rready)
   );

   initial clk = 1'b0;
   always #5 clk = ~clk;

   initial begin
      rst         = 1'b1;
      axi_awid    = '0;
      axi_awaddr  = '0;
      axi_awlen   = '0;
      axi_awsize  = 3'd4;
      axi_awburst = 2'b01;
      axi_awlock  = 1'b0;
      axi_awcache = '0;
      axi_awprot  = '0;
      axi_awqos   = '0;
      axi_awvalid = 1'b0;
      axi_wdata   = '0;
      axi_wstrb   = '1;
      axi_wlast   = 1'b0;
      axi_wvalid  = 1'b0;
      axi_bready  = 1'b0;
      axi_arid    = '0;
      axi_araddr  = '0;
      axi_arlen   = '0;
      axi_arsize  = 3'd4;
      axi_arburst = 2'b01;
      axi_arlock  = 1'b0;
      axi_arcache = '0;
      axi_arprot  = '0;
      axi_arqos   = '0;
      axi_arvalid = 1'b0;
      axi_rready  = 1'b0;

      repeat (3) @(posedge clk);
      rst = 1'b0;
      wait (init_calib_complete);
      repeat (2) @(posedge clk);

      write_beat(32'h0000_0040, 128'h0123_4567_89ab_cdef_fedc_ba98_7654_3210);
      read_check(32'h0000_0040, 128'h0123_4567_89ab_cdef_fedc_ba98_7654_3210);

      write_burst2(32'h0000_0080,
                   128'h1111_2222_3333_4444_5555_6666_7777_8888,
                   128'h9999_aaaa_bbbb_cccc_dddd_eeee_ffff_0000);
      read_check_burst2(32'h0000_0080,
                        128'h1111_2222_3333_4444_5555_6666_7777_8888,
                        128'h9999_aaaa_bbbb_cccc_dddd_eeee_ffff_0000);

      $display("DDR4 fast mock basic AXI test passed");
      $finish;
   end

   task automatic write_beat(input logic [31:0] addr, input logic [127:0] data);
      begin
         @(posedge clk);
         axi_awaddr  <= addr;
         axi_awlen   <= 8'd0;
         axi_awvalid <= 1'b1;
         wait (axi_awready);
         @(posedge clk);
         axi_awvalid <= 1'b0;

         axi_wdata  <= data;
         axi_wlast  <= 1'b1;
         axi_wvalid <= 1'b1;
         wait (axi_wready);
         @(posedge clk);
         axi_wvalid <= 1'b0;
         axi_wlast  <= 1'b0;

         axi_bready <= 1'b1;
         wait (axi_bvalid);
         @(posedge clk);
         axi_bready <= 1'b0;
      end
   endtask

   task automatic write_burst2(
      input logic [31:0] addr,
      input logic [127:0] data0,
      input logic [127:0] data1
   );
      begin
         @(posedge clk);
         axi_awaddr  <= addr;
         axi_awlen   <= 8'd1;
         axi_awvalid <= 1'b1;
         wait (axi_awready);
         @(posedge clk);
         axi_awvalid <= 1'b0;

         axi_wdata  <= data0;
         axi_wlast  <= 1'b0;
         axi_wvalid <= 1'b1;
         wait (axi_wready);
         @(posedge clk);

         axi_wdata <= data1;
         axi_wlast <= 1'b1;
         wait (axi_wready);
         @(posedge clk);
         axi_wvalid <= 1'b0;
         axi_wlast  <= 1'b0;

         axi_bready <= 1'b1;
         wait (axi_bvalid);
         @(posedge clk);
         axi_bready <= 1'b0;
      end
   endtask

   task automatic read_check(input logic [31:0] addr, input logic [127:0] expected);
      begin
         @(posedge clk);
         axi_araddr  <= addr;
         axi_arlen   <= 8'd0;
         axi_arvalid <= 1'b1;
         wait (axi_arready);
         @(posedge clk);
         axi_arvalid <= 1'b0;

         axi_rready <= 1'b1;
         wait (axi_rvalid);
         if (axi_rdata !== expected || ~axi_rlast) begin
            $fatal(1, "single read mismatch: data=%h expected=%h rlast=%b", axi_rdata, expected, axi_rlast);
         end
         @(posedge clk);
         axi_rready <= 1'b0;
      end
   endtask

   task automatic read_check_burst2(
      input logic [31:0] addr,
      input logic [127:0] expected0,
      input logic [127:0] expected1
   );
      begin
         @(posedge clk);
         axi_araddr  <= addr;
         axi_arlen   <= 8'd1;
         axi_arvalid <= 1'b1;
         wait (axi_arready);
         @(posedge clk);
         axi_arvalid <= 1'b0;

         axi_rready <= 1'b1;
         wait (axi_rvalid);
         if (axi_rdata !== expected0 || axi_rlast) begin
            $fatal(1, "burst read beat0 mismatch: data=%h expected=%h rlast=%b", axi_rdata, expected0, axi_rlast);
         end
         @(posedge clk);
         #1;
         if (axi_rdata !== expected1 || ~axi_rlast) begin
            $fatal(1, "burst read beat1 mismatch: data=%h expected=%h rlast=%b", axi_rdata, expected1, axi_rlast);
         end
         @(posedge clk);
         axi_rready <= 1'b0;
      end
   endtask

endmodule
