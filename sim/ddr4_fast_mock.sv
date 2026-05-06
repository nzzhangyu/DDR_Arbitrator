`timescale 1ns/1ps

// Lightweight DDR4 AXI mock for fast simulation.
// The model keeps a small 128-bit word memory and a simple calibration delay.
module ddr4_fast_mock #(
   parameter int AXI_ADDR_WIDTH      = 32,
   parameter int AXI_ID_WIDTH        = 1,
   parameter int MEM_WORDS           = 16384,
   parameter int CALIB_DELAY_CYCLES  = 32,
   parameter int READ_LATENCY_CYCLES = 2
) (
   input  logic                      clk_in,
   input  logic                      RESET,

   output logic                      ui_clk,
   output logic                      ui_clk_sync_rst,
   output logic                      init_calib_complete,
   output logic                      dbg_clk,

   input  logic [AXI_ID_WIDTH-1:0]    axi_awid,
   input  logic [AXI_ADDR_WIDTH-1:0]  axi_awaddr,
   input  logic [7:0]                 axi_awlen,
   input  logic [2:0]                 axi_awsize,
   input  logic [1:0]                 axi_awburst,
   input  logic                      axi_awlock,
   input  logic [3:0]                 axi_awcache,
   input  logic [2:0]                 axi_awprot,
   input  logic [3:0]                 axi_awqos,
   input  logic                      axi_awvalid,
   output logic                      axi_awready,

   input  logic [127:0]               axi_wdata,
   input  logic [15:0]                axi_wstrb,
   input  logic                      axi_wlast,
   input  logic                      axi_wvalid,
   output logic                      axi_wready,

   output logic [AXI_ID_WIDTH-1:0]    axi_bid,
   output logic [1:0]                 axi_bresp,
   output logic                      axi_bvalid,
   input  logic                      axi_bready,

   input  logic [AXI_ID_WIDTH-1:0]    axi_arid,
   input  logic [AXI_ADDR_WIDTH-1:0]  axi_araddr,
   input  logic [7:0]                 axi_arlen,
   input  logic [2:0]                 axi_arsize,
   input  logic [1:0]                 axi_arburst,
   input  logic                      axi_arlock,
   input  logic [3:0]                 axi_arcache,
   input  logic [2:0]                 axi_arprot,
   input  logic [3:0]                 axi_arqos,
   input  logic                      axi_arvalid,
   output logic                      axi_arready,

   output logic [AXI_ID_WIDTH-1:0]    axi_rid,
   output logic [127:0]               axi_rdata,
   output logic [1:0]                 axi_rresp,
   output logic                      axi_rlast,
   output logic                      axi_rvalid,
   input  logic                      axi_rready
);

   localparam int MEM_ADDR_BITS   = $clog2(MEM_WORDS);
   localparam int MEM_WORD_MSB    = 4 + MEM_ADDR_BITS - 1;
   localparam logic [AXI_ADDR_WIDTH-1:0] AXI_WORD_BYTES = AXI_ADDR_WIDTH'(16);
   localparam logic [1:0] OKAY    = 2'b00;
   localparam logic [1:0] MEM_BRESP = OKAY;
   localparam logic [1:0] MEM_RRESP = OKAY;

   logic [127:0] mem [0:MEM_WORDS-1];
   logic [7:0]   calib_cnt;

   logic [AXI_ADDR_WIDTH-1:0] write_addr_q;
   logic [8:0]                write_beats_left_q;
   logic [AXI_ID_WIDTH-1:0]   write_id_q;
   logic                      write_active_q;
   logic                      write_resp_pending_q;

   logic [AXI_ADDR_WIDTH-1:0] read_addr_q;
   logic [8:0]                read_beats_left_q;
   logic [AXI_ID_WIDTH-1:0]   read_id_q;
   logic [7:0]                read_latency_q;
   logic                      read_active_q;
   logic                      read_data_valid_q;

   logic [MEM_ADDR_BITS-1:0]  write_mem_index;
   logic [MEM_ADDR_BITS-1:0]  read_mem_index;

   integer i;

   initial begin
      for (i = 0; i < MEM_WORDS; i++) begin
         mem[i] = '0;
      end
   end

   assign ui_clk = clk_in;
   assign dbg_clk = clk_in;
   assign ui_clk_sync_rst = RESET | (~init_calib_complete);

   always_ff @(posedge clk_in) begin
      if (RESET) begin
         calib_cnt            <= '0;
         init_calib_complete  <= 1'b0;
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

   assign axi_awready = init_calib_complete &&
                        (~write_active_q) &&
                        (~write_resp_pending_q);
   assign axi_wready  = init_calib_complete && write_active_q;
   assign axi_bvalid  = write_resp_pending_q;
   assign axi_bid     = write_id_q;
   assign axi_bresp   = MEM_BRESP;

   assign axi_arready = init_calib_complete &&
                        (~read_active_q) &&
                        (~read_data_valid_q);
   assign axi_rid     = read_id_q;
   assign axi_rresp   = MEM_RRESP;
   assign axi_rvalid  = read_data_valid_q;
   assign axi_rlast   = read_data_valid_q && (read_beats_left_q == 9'd1);

   assign write_mem_index = write_addr_q[MEM_WORD_MSB:4];
   assign read_mem_index  = read_addr_q[MEM_WORD_MSB:4];
   assign axi_rdata       = mem[read_mem_index];

   always_ff @(posedge clk_in) begin
      if (RESET) begin
         write_addr_q           <= '0;
         write_beats_left_q     <= '0;
         write_id_q             <= '0;
         write_active_q         <= 1'b0;
         write_resp_pending_q   <= 1'b0;
      end
      else begin
         if (axi_awvalid && axi_awready) begin
            write_addr_q         <= axi_awaddr;
            write_beats_left_q   <= {1'b0, axi_awlen} + 9'd1;
            write_id_q           <= axi_awid;
            write_active_q       <= 1'b1;
         end

         if (write_active_q && axi_wvalid && axi_wready) begin
            integer byte_idx;
            logic [127:0] next_word;

            next_word = mem[write_mem_index];
            for (byte_idx = 0; byte_idx < 16; byte_idx++) begin
               if (axi_wstrb[byte_idx]) begin
                  next_word[byte_idx*8 +: 8] = axi_wdata[byte_idx*8 +: 8];
               end
            end
            mem[write_mem_index] <= next_word;
            write_addr_q         <= write_addr_q + AXI_WORD_BYTES;

            if (write_beats_left_q == 9'd1) begin
               write_beats_left_q   <= '0;
               write_active_q       <= 1'b0;
               write_resp_pending_q <= 1'b1;
            end
            else begin
               write_beats_left_q <= write_beats_left_q - 9'd1;
            end
         end

         if (axi_bvalid && axi_bready) begin
            write_resp_pending_q <= 1'b0;
         end
      end
   end

   always_ff @(posedge clk_in) begin
      if (RESET) begin
         read_addr_q         <= '0;
         read_beats_left_q   <= '0;
         read_id_q           <= '0;
         read_latency_q      <= '0;
         read_active_q       <= 1'b0;
         read_data_valid_q   <= 1'b0;
      end
      else begin
         if (axi_arvalid && axi_arready) begin
            read_addr_q       <= axi_araddr;
            read_beats_left_q <= {1'b0, axi_arlen} + 9'd1;
            read_id_q         <= axi_arid;
            read_latency_q    <= READ_LATENCY_CYCLES[7:0];
            read_active_q     <= 1'b1;
            read_data_valid_q <= 1'b0;
         end
         else if (read_active_q && ~read_data_valid_q) begin
            if (read_latency_q == 8'd0) begin
               read_data_valid_q <= 1'b1;
            end
            else begin
               read_latency_q <= read_latency_q - 8'd1;
            end
         end
         else if (read_data_valid_q && axi_rready) begin
            if (read_beats_left_q == 9'd1) begin
               read_beats_left_q <= '0;
               read_active_q     <= 1'b0;
               read_data_valid_q <= 1'b0;
            end
            else begin
               read_addr_q       <= read_addr_q + AXI_WORD_BYTES;
               read_beats_left_q <= read_beats_left_q - 9'd1;
               read_data_valid_q <= 1'b1;
            end
         end
      end
   end

endmodule
