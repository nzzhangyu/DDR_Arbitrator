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
   axis_frame_sof, m_axis_tx_tlast, m_axis_tx_tvalid, m_axis_tx_tready, m_axis_tx_tdata, crc_rst,
   gtx_user_clk_in
   );

   input            axis_frame_sof ;    // internal start-of-frame marker
   input            m_axis_tx_tlast ;   // AXI4-Stream end of frame
   input            m_axis_tx_tvalid ;  // AXI4-Stream data valid
   input            m_axis_tx_tready ;  // AXI4-Stream sink ready
   input [63:0]     m_axis_tx_tdata ;

  
   input        crc_rst;
   
   
   input            gtx_user_clk_in ;
  
   output           crc_error;
   
   //reg [9:0]        data_cnt;
   wire axis_tx_fire;

   //assign           crc_rst_n = aurora_tx_reset_n & rst_local_t_gtx_clk & (~aurora_sw_rst);
   assign axis_tx_fire = m_axis_tx_tvalid & m_axis_tx_tready;
   
     
   reg [63:0] crc_data_in_reg;

   always @(posedge gtx_user_clk_in ) begin
      if(crc_rst) begin
         crc_data_in_reg  <= 'h0;
      end
      else if(axis_tx_fire) begin
         crc_data_in_reg  <= m_axis_tx_tdata;
      end
   end
   
   reg data_val;
   wire data_val_tmp;
   wire crc_en;
   
   assign data_val_tmp = axis_tx_fire & (~axis_frame_sof) & (~m_axis_tx_tlast);
   
   always @(posedge gtx_user_clk_in ) begin
        data_val   <= data_val_tmp;
   end
 
   assign crc_en     = data_val ;
   
   
   reg [63:0] crc_data_catch_reg;

   always @(posedge gtx_user_clk_in ) begin
      if(crc_rst) begin
        crc_data_catch_reg   <= 'h0;
      end
      else if(m_axis_tx_tlast && axis_tx_fire) begin
        crc_data_catch_reg   <= m_axis_tx_tdata;
      end
   end

   reg [2:0]   data_cnt;
   wire        data_cnt_lim;

   assign      data_cnt_lim = &data_cnt;
   
   
   always @(posedge gtx_user_clk_in ) begin
      if(crc_rst) begin
         data_cnt  <= 'h0;
      end
      else if(axis_frame_sof && axis_tx_fire) begin
         data_cnt   <= 'h1;
      end
      else if(m_axis_tx_tlast && axis_tx_fire) begin
         data_cnt   <= 'h0;
      end
      else if( (|data_cnt) && (~data_cnt_lim) && axis_tx_fire ) begin
    data_cnt   <= data_cnt + 1'h1;
      end
   end
   
   
   
   reg crc_chk_val;
   wire crc_chk_val_t;

   assign crc_chk_val_t = m_axis_tx_tlast & axis_tx_fire & data_cnt_lim;
   
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
   assign      crc_clear = axis_frame_sof & axis_tx_fire;

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
   wire        set_crc_error;

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
