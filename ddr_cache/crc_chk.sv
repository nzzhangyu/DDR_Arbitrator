//--------------------------------------------------------------------------------
// Company: Neusoft Medical Systems
// Engineer: 
// 
// Create Date:     15/1/2019 
// Design Name:    
// Module Name:    crc_chk 
// Project Name:   H71
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: check the CRC   
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: make
// 
//--------------------------------------------------------------------------------

`timescale 1ns/1ps
module crc_chk(/*AUTOARG*/
   // Outputs
   crc_error,
   // Inputs
   tx_sof_n_out, tx_eof_n_out, tx_src_rdy_n_out, tx_d_out, crc_rst,
   gtx_user_clk_in
   );

   input            tx_sof_n_out ;      // start of frame 
   input            tx_eof_n_out ;      // end of frame 
   input            tx_src_rdy_n_out ;  // 
   input [63:0]     tx_d_out ;

  
   input        crc_rst;
   
   
   input            gtx_user_clk_in ;
  
   output           crc_error;
   
   //reg [9:0]        data_cnt;

   //assign           crc_rst_n = aurora_tx_reset_n & rst_local_t_gtx_clk & (~aurora_sw_rst);
   
     
   reg [63:0] crc_data_in_reg;

   always @(posedge gtx_user_clk_in ) begin
      if(crc_rst) begin
         crc_data_in_reg  <= 'h0;
      end
      else if(~tx_src_rdy_n_out) begin
         crc_data_in_reg  <= tx_d_out;
      end
   end
   
   reg data_val;
   
   assign data_val_tmp = (~tx_src_rdy_n_out) & tx_sof_n_out & tx_eof_n_out ;
   
   always @(posedge gtx_user_clk_in ) begin
        data_val   <= data_val_tmp;
   end
 
   assign crc_en     = data_val ;
   
   
   reg [63:0] crc_data_catch_reg;

   always @(posedge gtx_user_clk_in ) begin
      if(crc_rst) begin
        crc_data_catch_reg   <= 'h0;
      end
      else if((~tx_eof_n_out)&& (~tx_src_rdy_n_out)) begin
        crc_data_catch_reg   <= tx_d_out;
      end
   end

   reg [2:0]   data_cnt;

   assign      data_cnt_lim = &data_cnt;
   
   
   always @(posedge gtx_user_clk_in ) begin
      if(crc_rst) begin
         data_cnt  <= 'h0;
      end
      else if((~tx_sof_n_out)&& (~tx_src_rdy_n_out)) begin
         data_cnt   <= 'h1;
      end
      else if((~tx_eof_n_out)&& (~tx_src_rdy_n_out)) begin
         data_cnt   <= 'h0;
      end
      else if( (|data_cnt) && (~data_cnt_lim) && (~tx_src_rdy_n_out) ) begin
    data_cnt   <= data_cnt + 1'h1;
      end
   end
   
   
   
   reg crc_chk_val;

   assign crc_chk_val_t = (~tx_eof_n_out)& (~tx_src_rdy_n_out) & data_cnt_lim;
   
   always @(posedge gtx_user_clk_in ) begin
      if(crc_rst) begin
        crc_chk_val   <= 'h0;
      end
      else begin
        crc_chk_val   <= crc_chk_val_t;
      end
   end

   wire [15:0]                     crc_0_out;
   wire [15:0]                     crc_1_out;
   wire [15:0]                     crc_2_out;
   wire [15:0]                     crc_3_out;
                                   
   wire [63:0]                     crc_out;
                                   
                                   
   wire [15:0]                     crc_0_in;
   wire [15:0]                     crc_1_in;
   wire [15:0]                     crc_2_in;
   wire [15:0]                     crc_3_in;

   wire                            RESET;
   wire                            clk;
   wire                            crc_clear;
  // wire                            crc_en;
   
   assign      RESET = crc_rst;
   assign      clk = gtx_user_clk_in;
   assign      crc_clear = (~tx_sof_n_out);

   assign      crc_out = {crc_3_out,crc_2_out,crc_1_out,crc_0_out};
   
   assign      crc_3_in =  crc_data_in_reg[63:48];
   assign      crc_2_in =  crc_data_in_reg[47:32];
   assign      crc_1_in =  crc_data_in_reg[31:16];
   assign      crc_0_in =  crc_data_in_reg[15:0];
   
   CRC_16_header_data        CRC_0_uut(
                                      // Outputs
                                      .CRC_CODE    (crc_0_out[15:0]),
                                      // Inputs
                                      .Clk         (clk),
                                      .Reset       (RESET),
                                      .CRC_Clear   (crc_clear),
                                      .CRC_En      (crc_en),
                                      .DataIn      (crc_0_in[15:0]));
   
   CRC_16_header_data        CRC_1_uut(
                                      // Outputs
                                      .CRC_CODE    (crc_1_out[15:0]),
                                      // Inputs
                                      .Clk         (clk),
                                      .Reset       (RESET),
                                      .CRC_Clear   (crc_clear),
                                      .CRC_En      (crc_en),
                                      .DataIn      (crc_1_in[15:0]));
   
   
   CRC_16_header_data        CRC_2_uut(
                                      // Outputs
                                      .CRC_CODE    (crc_2_out[15:0]),
                                      // Inputs
                                      .Clk         (clk),
                                      .Reset       (RESET),
                                      .CRC_Clear   (crc_clear),
                                      .CRC_En      (crc_en),
                                      .DataIn      (crc_2_in[15:0]));
   
   
   CRC_16_header_data        CRC_3_uut(
                                      // Outputs
                                      .CRC_CODE    (crc_3_out[15:0]),
                                      // Inputs
                                      .Clk         (clk),
                                      .Reset       (RESET),
                                      .CRC_Clear   (crc_clear),
                                      .CRC_En      (crc_en),
                                      .DataIn      (crc_3_in[15:0]));

   

    /*(* mark_debug="true" *)*/ reg         crc_error;

   assign      set_crc_error = crc_out != crc_data_catch_reg;
   
   
    always @(posedge gtx_user_clk_in ) begin
      if(crc_rst) begin
        crc_error   <= 'h0;
      end
      else if(crc_chk_val && set_crc_error) begin
        crc_error   <= 'h1;
      end
      else begin
        crc_error   <= 'h0;
      end
    end
   
   

       
endmodule // crc_chk
