//--------------------------------------------------------------------------------
// Company: Neusoft Medical Systems
// Engineer: 
// 
// Create Date:     15/1/2019 
// Design Name:    
// Module Name:    trans_frame_type_ctrl 
// Project Name:   H71
// Target Devices: 
// Tool versions: 
// Description:  
//------------------generate idle_process_en
//    set idle_process_en when sample_data_on and view_tx_done (the last idle frame transmit finished ) 
//   clear idle_process_en when last_view_ind (the last view transmit 
// Dependencies: generate aurora frame     
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: make
//
//--------------------------------------------------------------------------------

`timescale 1ns/1ps
module trans_frame_type_ctrl(/*AUTOARG*/
   // Outputs
   idle_process_en,
   // Inputs
   aurora_sw_rst, rst_local_t_gtx_clk, gtx_user_clk_in,
   sampling_data_on, view_start_cnt_half, view_tx_done,
   gtx_clk_last_view_trans_fsh
   );

   input                            aurora_sw_rst ;                // aurora_tx_reset (gtx_clk locked )
   input              rst_local_t_gtx_clk;
   
   input                            gtx_user_clk_in ;                // aurora_8b10b user clock 
   
   //input            make_data_on;
   input              sampling_data_on;
   
   input              view_start_cnt_half;
   input              view_tx_done;
   //input            last_view_ind;
   input              gtx_clk_last_view_trans_fsh;
   
   output             idle_process_en;
   
   /*
   reg                make_data_on_d;
   reg                make_data_on_dd;
   reg                make_data_on_ddd;
   
   always @(posedge gtx_user_clk_in  ) begin
      make_data_on_d   <= make_data_on;
      make_data_on_dd   <= make_data_on_d;
      make_data_on_ddd   <= make_data_on_dd;
   end
   */
  // /*
   reg              sampling_data_on_d;
   reg              sampling_data_on_dd ;
   reg              sampling_data_on_ddd  ;
   
   
   always @(posedge gtx_user_clk_in  ) begin
      sampling_data_on_d     <= sampling_data_on;
      sampling_data_on_dd    <= sampling_data_on_d;
   end
   // */
   
   reg   busy_process_en;
  
   
   always @(posedge gtx_user_clk_in  ) begin
      if(aurora_sw_rst) begin
    busy_process_en   <= 'h0;
      end
      else if (~rst_local_t_gtx_clk) begin
    busy_process_en   <= 'h0;
      end
      else if (busy_process_en && gtx_clk_last_view_trans_fsh ) begin  //period 1 
    busy_process_en   <= 'h0;
      end
      else if ( sampling_data_on_dd && view_start_cnt_half) begin //period 2 
    busy_process_en  <= 'h1;
      end
   end

   wire  idle_process_en;
   assign idle_process_en = ~busy_process_en;
   
   /*
   reg[1:0]      make_data_on_dile_frame_cnt;

   assign     make_data_on_dile_frame_cnt_lim = &make_data_on_dile_frame_cnt;
   
   always @(posedge gtx_user_clk_in  ) begin
      if(aurora_sw_rst) begin
    make_data_on_dile_frame_cnt   <= 'h0;
      end
      else if(make_data_on_dd && (~make_data_on_dd))begin
    make_data_on_dile_frame_cnt   <= 'h0;
      end
      else if (busy_process_en) begin
    make_data_on_dile_frame_cnt   <= 'h0;
      end
      else if ((~make_data_on_dile_frame_cnt_lim) &&  view_start_cnt_half) begin
    make_data_on_dile_frame_cnt   <= make_data_on_dile_frame_cnt + 'h1;
      end
   end
   
   assign make_data_short_err = make_data_on_dile_frame_cnt_lim;
   */

endmodule // trans_frame_type_ctrl
