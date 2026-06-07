//--------------------------------------------------------------------------------
// Company: Neusoft Medical Systems
// Engineer: 
// 
// Create Date:     15/1/2019 
// Design Name:    
// Module Name:    aurora_tx_frame 
// Project Name:   H71
// Target Devices: 
// Tool versions: 
// Description:  
//
// Dependencies: generate aurora frame     
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: make
//
//--------------------------------------------------------------------------------
`include "h80_define.sv"
`timescale 1ns/1ps
module aurora_tx_frame(
`ifdef TX_DATA_WIDTH_32
             tx_rem_out, tx_d_out,aurora_frame_fifo_dout,idle_data_out,
`else
             tx_rem_out, tx_d_out,aurora_frame_fifo_dout,idle_data_out,
`endif
             
             /*AUTOARG*/
   // Outputs
   Diag_aurora_data_err_out, Diag_aurora_header_err_out,
   Diag_auroradata_en_rise_flag_out, tx_sof_n_out, tx_eof_n_out,
   tx_src_rdy_n_out, fifo_rd_en, view_tx_done, idle_frame_ind,
   header_cnt, slice_cnt, slice_data_cnt, header_en, header_cmd_1_en,
   header_cmd_2_en, footer_en, footer_1_en, slice_cmd_1_en,
   slice_cmd_2_en, crc_tx_2_en, crc_tx_1_en, clear_crc, crc_en,
   idle_slice_data_en, view_start_cnt_half, aurora_first_view,
   gtx_refresh_process_en, auro_frame_state_test,
   // Inputs
   ui_clk, ddr_user_rst, console_reset_in, aurora_sw_rst,
   TX_CHANNEL_UP_in, rst_local_t_ddr_clk, rst_local_t_gtx_clk,
   refresh_process_en, gtx_user_clk_in, clk_40mhz_1us_in,
   Fault_inject_en, slice_sel, tx_dst_rdy_n_in,
   aurora_frame_fifo_prog_empty, aurora_frame_fifo_empty,
   idle_process_en, idle_trig, slice_length_odd, slice_length_even
   );
   
   
    
   //parameter                        SLICE_DATA_NUM = 704;            //--add by zhangdq   
   //parameter              CT_SLICE_NUM = 32;
      
   input                            ui_clk ;                  // system clock 100M
   input                            ddr_user_rst;                     // ddr_controller sys_rst_buf;
   //input                            RESET ;                          // system clock reset and local reset ; 1 active 
   
   input                            console_reset_in ;               // console_reset from rcom_ctrl 
   input                            aurora_sw_rst ;                // aurora_tx_reset (gtx_clk locked )
   input                            TX_CHANNEL_UP_in;
                                   
   input                            rst_local_t_ddr_clk;             //1 active
   input                            rst_local_t_gtx_clk;             //0 active
                                   
   input                            refresh_process_en ;             // refresh frame process enable (from view_retrans_ctrl)
   
   input                            gtx_user_clk_in ;                // aurora_8b10b user clock 
   
   input                            clk_40mhz_1us_in;                // 40Mhz clock 
   input                            Fault_inject_en;
   
   input  [8:0]                     slice_sel;                       // slice_sel setting 
                                   
   output                           Diag_aurora_data_err_out;        
   output                           Diag_aurora_header_err_out; 
   output                           Diag_auroradata_en_rise_flag_out;

   // aurora_8b10b interface
`ifdef TX_DATA_WIDTH_32
   output [1:0]                     tx_rem_out ;                     
   output [31:0]                    tx_d_out;
   input  [31:0]                    aurora_frame_fifo_dout;
   input  [31:0]                    idle_data_out;
`else
   output [2:0]                     tx_rem_out ;                     
   output [63:0]                    tx_d_out;
   input  [63:0]                    aurora_frame_fifo_dout;
   input  [63:0]                    idle_data_out;
   
`endif
   
   
   input                            tx_dst_rdy_n_in ;  
   output                           tx_sof_n_out ;
   output                           tx_eof_n_out ;
   output                           tx_src_rdy_n_out ;
   
 
   //output              aurora_sw_rst;  // to crc_check.v 

   //fifo interface

   input              aurora_frame_fifo_prog_empty;
   input              aurora_frame_fifo_empty;
   
   output             fifo_rd_en;
   //output              fifo_wr_en;

   //idle frame gen interface 

   input              idle_process_en;
   input              idle_trig;
   
   output             view_tx_done;  // to rd_cache_ctrl.v
   output             idle_frame_ind;// to rd_cache_ctrl.v
   
   output [7:0]       header_cnt;
   output [7:0]       slice_cnt;     // to idle frame gen 
   output [9:0]       slice_data_cnt;
   
   output             header_en;
   //output              slice_data_en;
   
   output             header_cmd_1_en;
   output             header_cmd_2_en;
   output             footer_en;
   output             footer_1_en;
   output             slice_cmd_1_en;
   output             slice_cmd_2_en;
   output             crc_tx_2_en;
   output             crc_tx_1_en;
   
   output             clear_crc;
   output             crc_en;

   output             idle_slice_data_en;
   
   
   //output              last_view_ind;

   output             view_start_cnt_half;
   output             aurora_first_view;
   
   input  [11:0]      slice_length_odd;
   input  [11:0]      slice_length_even;

   output             gtx_refresh_process_en;

   output [3:0]       auro_frame_state_test;
   
   
   
   parameter                        IDLE = 'h0;
   parameter                        HEAD_SOF_PRE_STA = 'h1;
   parameter                        HEAD_SOF_PRE_STA2 = 'h2;
   parameter                        HEAD_SOF_STA = 'h3;
   parameter                        HEAD_DATA_STA = 'h4;
   parameter                        HEAD_EOF_STA = 'h5;
   parameter                        WAIT_SLICE_STA = 'h6;
   parameter                        SLICE_SOF_PRE_STA = 'h7;
   parameter                        SLICE_SOF_PRE_STA2 = 'h8;
   parameter                        SLICE_SOF_STA = 'h9;
   parameter                        SLICE_DATA_STA = 'ha;
   parameter                        SLICE_EOF_STA = 'hb;
   parameter                        SLICE_DONE_STA = 'hc;
   parameter                        REFRESH_WAIT = 'hd;
   parameter                        REFRESH_DATA = 'he;
   
   (* mark_debug="true" *) reg [3:0]             auro_frame_state;
   reg [3:0]       auro_frame_state_next;

   wire            tx_sof_n_out ;
   wire            tx_eof_n_out ;
   wire            tx_src_rdy_n_out ;

   reg [9:0]             slice_data_cnt ;
  

   wire            view_tx_done;

   
   wire [11:0]              idle_slice_length;
   wire [11:0]              slice_length_tx;

   wire [2:0]            sof_pre_cnt_lim;
   wire [1:0]            sof_cnt_lim;
   wire [1:0]            eof_cnt_lim;
   wire [7:0]            header_cnt_lim;
   wire [9:0]            slice_data_cnt_lim;
   reg [7:0]             slice_cnt;
  
`ifdef TX_DATA_WIDTH_32  
   wire [1:0]            tx_rem_out;
   assign             sof_pre_cnt_lim    = 'd1;
   assign             sof_cnt_lim        = 'd1;
   assign             eof_cnt_lim        = 'd1;
   assign             header_cnt_lim     = 'd61;
   assign             slice_data_cnt_lim = (slice_length_tx[11:1]+1'h1);
`else  
   wire [2:0]            tx_rem_out;
   assign             sof_pre_cnt_lim    = 'd0;
   assign             sof_cnt_lim        = 'd0;
   assign             eof_cnt_lim        = 'd0;
   assign             header_cnt_lim     = 'd30;
   assign             slice_data_cnt_lim =  slice_length_tx[11:2];
   
`endif
 
   wire [11:0]              slice_length;

   assign             slice_length  = slice_cnt[0] ? slice_length_even : slice_length_odd;
  
   
   assign             idle_slice_length = 'h360;

   assign             slice_length_tx = idle_process_en ? idle_slice_length : slice_length;
 
   //to sync signal 
   
   reg                rst_local_t_ddr_clk_delay;
   reg                rst_local_t_ddr_clk_1d;
   reg                rst_local_t_ddr_clk_2d;
   reg                rst_local_t_ddr_clk_3d;
   reg                rst_local_t_ddr_clk_4d;
   reg                rst_local_t_ddr_clk_5d;
   
   always @(posedge ui_clk) begin
      rst_local_t_ddr_clk_1d      <= rst_local_t_ddr_clk;
      rst_local_t_ddr_clk_2d      <= rst_local_t_ddr_clk_1d;
      rst_local_t_ddr_clk_3d      <= rst_local_t_ddr_clk_2d;
      rst_local_t_ddr_clk_4d      <= rst_local_t_ddr_clk_3d;
      rst_local_t_ddr_clk_5d      <= rst_local_t_ddr_clk_4d;
      rst_local_t_ddr_clk_delay   <= rst_local_t_ddr_clk_5d;
   end
   
   
   reg                             console_reset_in_d;
   reg                             console_reset_in_dd;
   reg                             console_reset_in_ddd;
   
   always @(posedge gtx_user_clk_in) begin
      begin
         console_reset_in_d    <= console_reset_in;
         console_reset_in_dd   <= console_reset_in_d;
         console_reset_in_ddd  <= console_reset_in_dd;
      end
   end
   
   reg tx_channel_up_d;
   reg tx_channel_up_dd;
   reg tx_channel_up_ddd;

   
   always @(posedge gtx_user_clk_in  ) begin
      if(aurora_sw_rst) begin
         tx_channel_up_d     <= 'h0;
         tx_channel_up_dd    <= 'h0;
         tx_channel_up_ddd   <= 'h0;
      end
      else  begin
         tx_channel_up_d     <= TX_CHANNEL_UP_in;
         tx_channel_up_dd    <= tx_channel_up_d;
         tx_channel_up_ddd   <= tx_channel_up_dd;
      end
   end

      
   
    assign  tx_dst_rdy        =  (~tx_dst_rdy_n_in) & tx_channel_up_ddd;
   

   //------------refresh sync--------------
   
    (* ASYNC_REG = "true" *) reg refresh_process_en_rcom_cdc_to_d;
    (* ASYNC_REG = "true" *) reg refresh_process_en_dd;
    (* ASYNC_REG = "true" *) reg refresh_process_en_ddd;

   
   always @(posedge gtx_user_clk_in) begin
      if(aurora_sw_rst) begin
         refresh_process_en_rcom_cdc_to_d <= 'h0;
         refresh_process_en_dd            <= 'h0;
         refresh_process_en_ddd           <= 'h0;
      end
      else  begin
         refresh_process_en_rcom_cdc_to_d <= refresh_process_en;
         refresh_process_en_dd            <= refresh_process_en_rcom_cdc_to_d;
         refresh_process_en_ddd           <= refresh_process_en_dd;
      end
   end
     
   assign gtx_refresh_process_en         = refresh_process_en_dd;

   //----------------generate 1us trig of refresh -------------------
   reg     pulse_1us_d;
   reg     pulse_1us_dd;
   reg     pulse_1us_ddd;
  
   assign pulse_1us_edge = pulse_1us_dd & (~pulse_1us_ddd);
   
   assign refresh_trigger_pulse = gtx_refresh_process_en & pulse_1us_edge;
   
   //-------------- fault inject ------------------------------------
   reg [15:0] fault_50ms_cnt;

   assign     fault_50ms_cnt_rch = fault_50ms_cnt == 'hC800;  //50us
   //assign     fault_50ms_cnt_rch = fault_50ms_cnt == 'h3d0; //simulate 
   
   always @(posedge gtx_user_clk_in) begin
      if(aurora_sw_rst) begin
         fault_50ms_cnt   <= 'h0;
      end
      else if(~Fault_inject_en || fault_50ms_cnt_rch) begin
         fault_50ms_cnt   <= 'h0;
      end
      else if (pulse_1us_edge) begin
         fault_50ms_cnt   <= fault_50ms_cnt + 1'h1;
      end
   end

   reg fault_gen_r;

   assign fault_gen_set =  fault_gen_r  & (slice_data_cnt == 'h10);
   assign fault_gen_clr =  fault_gen_r  & (slice_data_cnt == 'h20);
   
   
   always @(posedge gtx_user_clk_in) begin
      if(aurora_sw_rst) begin
         fault_gen_r    <= 'h0;
      end
      else if (fault_50ms_cnt_rch) begin
         fault_gen_r    <= 'h1;
      end
      else if (fault_gen_clr) begin
         fault_gen_r    <= 'h0;
      end
   end

   reg fault_gen_pulse;
   
     
   always @(posedge gtx_user_clk_in) begin
      if(aurora_sw_rst) begin
         fault_gen_pulse    <= 'h0;
      end
      else if (fault_gen_set) begin
         fault_gen_pulse    <= 'h1;
      end
      else if (fault_gen_clr) begin
         fault_gen_pulse    <= 'h0;
      end
   end
   
   assign fault_gen_inject_ind = fault_gen_pulse & (slice_data_cnt == 'h18);
   
   //----------------------------------------------------------

   assign tx_rem_out = 'h0;
   
    //-----------------------intervieal between two frame ( first end to next start )-----------------------
   reg [2:0]                        view_start_dly_cnt; // 8 cycle
   wire                             view_start_dly_cnt_rch;

   assign             view_start_cnt_half      = (view_start_dly_cnt == 'h3) & (auro_frame_state == IDLE );
   
   

   assign     view_start_dly_cnt_rch = &view_start_dly_cnt;
   
   always @(posedge gtx_user_clk_in) begin
      if(aurora_sw_rst) begin
        view_start_dly_cnt   <= 'h0;
      end
      else if (gtx_refresh_process_en || view_tx_done /*|| rst_local*/) begin
        view_start_dly_cnt   <= 'h0;
      end
      else if(~view_start_dly_cnt_rch ) begin
         view_start_dly_cnt   <= view_start_dly_cnt + 1'h1;
      end
   end
   
    //-----------------------intervieal between two frame ( first start to next start )-----------------------
   reg [9:0]                        view_start_to_start_cnt; // about 15.3 us
   wire                             view_start_to_start_cnt_rch;

   
   assign             view_start_to_start_cnt_rch  = view_start_to_start_cnt == 'h50; //80us
   
   
   always @(posedge gtx_user_clk_in) begin
      if(aurora_sw_rst) begin
         view_start_to_start_cnt  <= 'h0;
      end
      else if (gtx_refresh_process_en || (auro_frame_state == HEAD_SOF_PRE_STA)) begin
         view_start_to_start_cnt  <= 'h0;
      end
      else if(~view_start_to_start_cnt_rch && pulse_1us_edge) begin
          view_start_to_start_cnt  <= view_start_to_start_cnt + 1'h1;
      end
   end
   
   
     
   /////////////////////FIFO reset ////////////////////////////////

  

   wire fifo_reset;
   
   assign fifo_reset  = ddr_user_rst | (rst_local_t_ddr_clk_delay) ;  

  
    
  
   
   //////////////////state //////////////////////////////
   //init_en 
   reg     rst_local_t_gtx_clk_d;

   always @(posedge gtx_user_clk_in) begin
      if(aurora_sw_rst) begin
        rst_local_t_gtx_clk_d   <= 'h1;
      end
      else begin
        rst_local_t_gtx_clk_d   <= rst_local_t_gtx_clk;
      end
   end
   
   assign rst_local = (~rst_local_t_gtx_clk_d );

   
   always @(posedge gtx_user_clk_in) begin
      if(aurora_sw_rst) begin
        auro_frame_state   <= IDLE;
      end
      else begin
        auro_frame_state   <= auro_frame_state_next;
      end
   end
   ///////////////////////////////////////////////////
   
   
   ////////////pre counter to remove a5a5... /////////////////
   reg [2:0]                        sof_pre_cnt;
   wire                             sof_pre_cnt_rch;

   assign    sof_pre_cnt_rch = (sof_pre_cnt == sof_pre_cnt_lim) & (tx_dst_rdy); 
   
   always @(posedge gtx_user_clk_in) begin
      if(aurora_sw_rst) begin
         sof_pre_cnt   <= 'h0;
      end
      else if((auro_frame_state != HEAD_SOF_PRE_STA) &&
              (auro_frame_state != SLICE_SOF_PRE_STA))  begin
         sof_pre_cnt   <= 'h0;
      end
       
      else if((~sof_pre_cnt_rch) && (tx_dst_rdy))  begin
         sof_pre_cnt   <= sof_pre_cnt + 1'h1;
      end
   end
   ////////////sof counter to    /////////////////
   reg [1:0]                        sof_cnt;
   wire                             sof_cnt_rch;

   assign    sof_cnt_rch = (sof_cnt == sof_cnt_lim) ; 
   
   always @(posedge gtx_user_clk_in) begin
      if(aurora_sw_rst) begin
         sof_cnt   <= 'h0;
      end
      else if((auro_frame_state != HEAD_SOF_STA) &&
              (auro_frame_state != SLICE_SOF_STA))  begin
         sof_cnt   <= 'h0;
      end
       
      else if((~sof_cnt_rch) && (tx_dst_rdy))  begin
         sof_cnt   <= sof_cnt + 1'h1;
      end
   end
     
   ////////////eof counter to    /////////////////
   reg [1:0]                        eof_cnt;
   wire                             eof_cnt_rch;

   assign    eof_cnt_rch = (eof_cnt == eof_cnt_lim); 
   
   always @(posedge gtx_user_clk_in) begin
      if(aurora_sw_rst) begin
         eof_cnt   <= 'h0;
      end
      else if((auro_frame_state != HEAD_EOF_STA) &&
              (auro_frame_state != SLICE_EOF_STA))  begin
         eof_cnt   <= 'h0;
      end
       
      else if((~eof_cnt_rch) && (tx_dst_rdy))  begin
         eof_cnt   <= eof_cnt + 1'h1;
      end
   end
     
   ///////header counter ///////////////

   reg [7:0]                        header_cnt;
   wire                             header_cnt_rch;

   assign    header_cnt_rch = (header_cnt == header_cnt_lim)  & (tx_dst_rdy);
   
   
   always @(posedge gtx_user_clk_in) begin
      if(aurora_sw_rst) begin
         header_cnt  <= 'h0;
      end
      else if (auro_frame_state != HEAD_DATA_STA) begin
         header_cnt  <= 'h0;
      end
      else if((~header_cnt_rch) && (tx_dst_rdy))  begin
         header_cnt   <= header_cnt + 1'h1;
      end
   end
   
   //////////////////////////slice_data_cnt ///////////////

   wire                             slice_data_cnt_rch;
   reg                idle_frame_ind;

   assign slice_data_cnt_add_normal = (~aurora_frame_fifo_empty) &
                   (tx_dst_rdy) & 
                  (~idle_frame_ind);
   assign slice_data_cnt_add_idle  = tx_dst_rdy & idle_frame_ind;

   assign slice_data_cnt_add_en = slice_data_cnt_add_normal | slice_data_cnt_add_idle;
   
   assign slice_data_cnt_rch       = (slice_data_cnt == slice_data_cnt_lim) & 
                 (slice_data_cnt_add_normal | slice_data_cnt_add_idle);

   
   always @(posedge gtx_user_clk_in) begin
      if(aurora_sw_rst) begin
         slice_data_cnt  <= 'h0;
      end
      else if(auro_frame_state != SLICE_DATA_STA) begin
         slice_data_cnt  <= 'h0;
      end
      else if ( (~slice_data_cnt_rch) && slice_data_cnt_add_en) begin
         slice_data_cnt   <= slice_data_cnt + 'h1;
      end
   end
 ////////////////////////////////////////////////
   reg                aurora_data_heade_ok ;
   wire [8:0]        slice_sel_r;
   wire               latch_frame_kind;
  
  
   
   assign  latch_frame_kind = (auro_frame_state == HEAD_DATA_STA) &(header_cnt == 'h7) & (tx_dst_rdy);
    
   assign  slice_sel_r = idle_frame_ind ?  8'h20 : slice_sel;
      
   
   wire                             slice_cnt_rch;
   wire                             add_slice_cnt;
   wire                             slice_cnt_lim;
   
   assign    add_slice_cnt = ( auro_frame_state == SLICE_EOF_STA )& eof_cnt_rch & (tx_dst_rdy);
   
   //assign    slice_cnt_lim = (slice_cnt == (slice_sel -1));
   assign    slice_cnt_lim = (slice_cnt == (slice_sel_r -1));
   assign    slice_cnt_rch = slice_cnt_lim & add_slice_cnt;
   
   always @(posedge gtx_user_clk_in) begin
       if(aurora_sw_rst) begin
         slice_cnt         <= 'h0;
       end
       else  if( auro_frame_state == IDLE) begin
         slice_cnt   <= 'h0;
       end
       else if ((~slice_cnt_lim) && add_slice_cnt) begin
         slice_cnt   <= slice_cnt + 1'h1;
       end
   end
    
   //////////////////////////ref_data_cnt_rch///////////////

   reg [3:0]                       ref_data_cnt;
   wire                            ref_data_cnt_rch;

   assign    ref_data_cnt_rch = (ref_data_cnt == 'h1) & (tx_dst_rdy);
   
   always @(posedge gtx_user_clk_in) begin
       if(aurora_sw_rst) begin
         ref_data_cnt   <= 'h0;
       end
       else if(auro_frame_state != REFRESH_DATA) begin
         ref_data_cnt   <= 'h0;
       end
       else if ((~ref_data_cnt_rch) & (tx_dst_rdy) ) begin
         ref_data_cnt   <= ref_data_cnt + 1'h1;
       end
   end
      
   ////////////////////slice interview delay
   reg[3:0]                         slice_interview_cnt;

   wire                             slice_interview_cnt_rch;

   //assign   slice_interview_cnt_rch = slice_interview_cnt == 'h7;
   assign   slice_interview_cnt_rch ='h1;
   
   always @(posedge gtx_user_clk_in) begin
       if(aurora_sw_rst) begin
         slice_interview_cnt   <= 'h0;
       end
       else if(auro_frame_state != WAIT_SLICE_STA) begin
         slice_interview_cnt   <= 'h0;
       end
       else if (~slice_interview_cnt_rch ) begin
          slice_interview_cnt    <= slice_interview_cnt + 1'h1;
       end
   end

   
   assign console_reset_enable = (auro_frame_state == IDLE) |
             (auro_frame_state    == REFRESH_DATA) ;

   assign trans_idle_frame_trig  =(  idle_process_en  & idle_trig);
   assign trans_normal_frame_trig =((~idle_process_en) & 
                (~aurora_frame_fifo_prog_empty) &
                view_start_to_start_cnt_rch &
                view_start_dly_cnt_rch);
   
   
   assign trans_frame_trig = trans_idle_frame_trig | trans_normal_frame_trig;

   assign view_tx_done = (auro_frame_state == SLICE_DONE_STA) && (~rst_local);

   
  
   always @(posedge gtx_user_clk_in ) begin
      if(aurora_sw_rst) begin
         idle_frame_ind  <= 'h0;
      end
      else if(trans_idle_frame_trig && (auro_frame_state == IDLE )) begin
         idle_frame_ind  <= 'h1;
      end
      else if(trans_normal_frame_trig && (auro_frame_state == IDLE )) begin
         idle_frame_ind  <= 'h0;
      end
   end
   
      
   /////////state STM/////////////
   
   always @(/*AS*/auro_frame_state or aurora_frame_fifo_prog_empty
       or eof_cnt_rch or gtx_refresh_process_en or header_cnt_rch
       or idle_process_en or ref_data_cnt_rch
       or refresh_trigger_pulse or rst_local or slice_cnt_rch
       or slice_data_cnt_rch or slice_interview_cnt_rch
       or sof_cnt_rch or sof_pre_cnt_rch or trans_frame_trig
       or tx_channel_up_ddd or tx_dst_rdy) begin
      auro_frame_state_next                  = auro_frame_state;
      case (auro_frame_state)
         IDLE : begin
            if(rst_local || (~tx_channel_up_ddd)) begin
               auro_frame_state_next    = IDLE;
            end
            else if(gtx_refresh_process_en) begin
               auro_frame_state_next    = REFRESH_WAIT;
            end
            else if(trans_frame_trig ) begin
               auro_frame_state_next    = HEAD_SOF_PRE_STA;
            end
         end
         HEAD_SOF_PRE_STA : begin   //read 32'h5a5a_5a5a and 32'ha5a5_a5a5 from fifo 
            if(rst_local ) begin 
               auro_frame_state_next    = IDLE;
            end
            else if(sof_pre_cnt_rch ) begin 
               auro_frame_state_next    = HEAD_SOF_PRE_STA2;
            end
         end
         HEAD_SOF_PRE_STA2 :  begin //read 32'h431000 and 32'h2100 from fifo 
            if(rst_local) begin
               auro_frame_state_next    = IDLE;
            end         
            else if(tx_dst_rdy) begin 
               auro_frame_state_next    = HEAD_SOF_STA;
            end
         end
         HEAD_SOF_STA : begin   //
            if(rst_local) begin
               auro_frame_state_next    = HEAD_EOF_STA;
            end
            else if(sof_cnt_rch && tx_dst_rdy) begin 
               auro_frame_state_next    = HEAD_DATA_STA;
            end
         end
         HEAD_DATA_STA : begin   //read 30 time 
            if(header_cnt_rch || rst_local) begin
               auro_frame_state_next    = HEAD_EOF_STA;
            end
         end
         HEAD_EOF_STA : begin  //read 
            if(rst_local /*&& (tx_dst_rdy)*/) begin
               auro_frame_state_next    = IDLE;
            end
            else if(eof_cnt_rch && tx_dst_rdy) begin 
               auro_frame_state_next    = WAIT_SLICE_STA;
            end
         end
         WAIT_SLICE_STA : begin
            if( rst_local) begin
               auro_frame_state_next    = IDLE;
            end
            else if( ((~aurora_frame_fifo_prog_empty)|| idle_process_en)  &&
            slice_interview_cnt_rch) begin  
               auro_frame_state_next    = SLICE_SOF_PRE_STA;
            end
         end
         SLICE_SOF_PRE_STA : begin   //read 32'h5a5a_5a5a from fifo 
            if( rst_local) begin 
               auro_frame_state_next    = IDLE;
            end
            else if(sof_pre_cnt_rch) begin 
               auro_frame_state_next    = SLICE_SOF_PRE_STA2;
            end
         end
         SLICE_SOF_PRE_STA2 : begin  //read 32'h5a5a_5a5a from fifo 
            if( rst_local) begin 
               auro_frame_state_next    = IDLE;
            end
         if(tx_dst_rdy ) begin 
               auro_frame_state_next    = SLICE_SOF_STA;
            end
         end
         SLICE_SOF_STA : begin
            if(rst_local) begin
               auro_frame_state_next    = SLICE_EOF_STA;
            end
            else if(sof_cnt_rch && tx_dst_rdy ) begin 
               auro_frame_state_next    = SLICE_DATA_STA;
            end
         end
         SLICE_DATA_STA : begin
            if(slice_data_cnt_rch || rst_local) begin
               auro_frame_state_next    = SLICE_EOF_STA;
            end
         end
         SLICE_EOF_STA : begin
            if (rst_local /*&& (tx_dst_rdy)*/) begin
               auro_frame_state_next    = IDLE;
            end
            else if(eof_cnt_rch && tx_dst_rdy) begin 
               if(slice_cnt_rch)  begin
                  auro_frame_state_next  = SLICE_DONE_STA;
               end
               else begin
                  auro_frame_state_next  = WAIT_SLICE_STA;
               end
            end
         end
         SLICE_DONE_STA : begin
            auro_frame_state_next       = IDLE;
         end
         REFRESH_WAIT : begin
            if(~gtx_refresh_process_en) begin 
               auro_frame_state_next    = IDLE;
            end
            else if (refresh_trigger_pulse) begin
               auro_frame_state_next    = REFRESH_DATA;
            end
         end
         REFRESH_DATA : begin
            if (ref_data_cnt_rch)  begin
               auro_frame_state_next    = REFRESH_WAIT;
            end
         end
               
         default : begin
            auro_frame_state_next       = IDLE;
         end
      endcase // case (auro_frame_state)
   end // always @ (...
   
//`ifdef TX_DATA_WIDTH_32
   assign tx_sof_out              =  (sof_cnt == 'h0) & ( (auro_frame_state == HEAD_SOF_STA) | (auro_frame_state == SLICE_SOF_STA));
   
   
   assign tx_eof_out                   =   eof_cnt_rch     & ((auro_frame_state == HEAD_EOF_STA) | (auro_frame_state    == SLICE_EOF_STA));

//`else
 //  assign tx_sof_out            = /*(tx_dst_rdy) &*/ ( (auro_frame_state == HEAD_SOF_STA) | (auro_frame_state == SLICE_SOF_STA));
   
   
 //  assign tx_eof_out                   = /*(tx_dst_rdy) &*/ ((auro_frame_state == HEAD_EOF_STA) | (auro_frame_state    == SLICE_EOF_STA));
//`endif

   //for simulation
   assign aurora_frame_ok = (auro_frame_state  == SLICE_DONE_STA) | 
                            ((auro_frame_state == REFRESH_DATA) & ref_data_cnt_rch ) ;
   
   ///////////////////////fifo read generate /////////////////////////////////////////
   
   wire   fifo_rd_en;
   wire   data_valid_rd_en;
   
   
   assign   fifo_rd_en_t         = (tx_dst_rdy) &
                                   ( (auro_frame_state  == HEAD_SOF_PRE_STA) |  //read out 32'h5a5a5a5a  32'h5a5a5a5a
                                     (auro_frame_state  == HEAD_SOF_PRE_STA2) |                  //read out 32'h2100
                                     (auro_frame_state  == HEAD_SOF_STA)     |                //read out 32'h433100
                                     (auro_frame_state  == HEAD_DATA_STA)    |
                                     (auro_frame_state  == SLICE_SOF_PRE_STA)|
                                     (auro_frame_state  == SLICE_SOF_PRE_STA2)|
                                     (auro_frame_state  == SLICE_SOF_STA)    |
                                     ((auro_frame_state == SLICE_EOF_STA) & (~eof_cnt_rch))  |
                                     ((auro_frame_state == HEAD_EOF_STA ) & (~eof_cnt_rch))  |
                                     (auro_frame_state  == SLICE_DATA_STA));
   
   assign fifo_rd_en = (~idle_frame_ind) & fifo_rd_en_t;
      
   assign   data_valid_rd_en     = (tx_dst_rdy) &
                                   ( (auro_frame_state    == HEAD_SOF_PRE_STA2) |
                                     (auro_frame_state    == HEAD_SOF_STA)      |
                                     (auro_frame_state    == HEAD_DATA_STA)     |
                                     (auro_frame_state    == SLICE_SOF_PRE_STA2)|
                                     (auro_frame_state    == SLICE_SOF_STA)     |
                                     ((auro_frame_state   == SLICE_EOF_STA) & (~eof_cnt_rch))  |
                                     ((auro_frame_state   == HEAD_EOF_STA ) & (~eof_cnt_rch))  |
                                     (auro_frame_state    == SLICE_DATA_STA));
   
   
   reg                             fifo_rd_en_dly;

   always @(posedge gtx_user_clk_in) begin
      if(aurora_sw_rst) begin
        fifo_rd_en_dly   <= 'h0;
      end
      else if((tx_dst_rdy)) begin
        fifo_rd_en_dly   <=  data_valid_rd_en;
      end
   end

   assign tx_src_rdy_out = fifo_rd_en_dly & (tx_dst_rdy);

   ///////////////////////idle data generate /////////////////////////////
       
   assign idle_slice_data_en     = (tx_dst_rdy) &
               ( (auro_frame_state    == SLICE_SOF_PRE_STA2)|
                 (auro_frame_state    == SLICE_SOF_STA)    |
                 (auro_frame_state    == SLICE_DATA_STA));
   
   ///////////////////////////idle frame signal ///////////////////////////
       
   wire               header_en;
   wire               header_cmd_1_en;
   wire               header_cmd_2_en;
   wire               footer_en;
   //wire             footer_2_en;
   wire               slice_cmd_1_en;
   wire               slice_cmd_2_en;
   wire               slice_data_en;

   wire            crc_tx_2_en;
   wire            crc_tx_1_en;

   wire            crc_en;
   //(* mark_debug="true" *)wire              crc_en_lsb;
   
   
   
   assign             header_cmd_2_en = sof_cnt_rch      & (tx_dst_rdy) & (auro_frame_state == HEAD_SOF_STA);
   assign             header_cmd_1_en = (sof_cnt == 'h0) & (tx_dst_rdy) & (auro_frame_state == HEAD_SOF_STA);
   
   assign             header_en     = (tx_dst_rdy) & (auro_frame_state == HEAD_DATA_STA);
   
    
   assign             slice_cmd_2_en  = sof_cnt_rch      & (tx_dst_rdy) & (auro_frame_state == SLICE_SOF_STA);
   assign             slice_cmd_1_en  = (sof_cnt == 'h0) & (tx_dst_rdy) & (auro_frame_state == SLICE_SOF_STA);
  
   
  
  
   //assign          header_cnt_not_zero     = (|header_cnt);
   //assign       slice_data_cnt_not_zero = (|slice_data_cnt);
`ifdef TX_DATA_WIDTH_32
   assign footer_en      = (tx_dst_rdy) & (auro_frame_state == SLICE_DATA_STA) & (slice_data_cnt == slice_data_cnt_lim);
   assign footer_1_en    = (tx_dst_rdy) & (auro_frame_state == SLICE_DATA_STA) & (slice_data_cnt == (slice_data_cnt_lim-1));
  
   assign crc_en_t    = (tx_dst_rdy) & 
           (((auro_frame_state == HEAD_DATA_STA) && header_cnt[0] ) |
                ((auro_frame_state    == SLICE_DATA_STA) && slice_data_cnt[0] ));
`else
   assign footer_en     = (tx_dst_rdy) & (auro_frame_state == SLICE_DATA_STA) & (slice_data_cnt == slice_data_cnt_lim);
   assign footer_1_en   = (tx_dst_rdy) & (auro_frame_state == SLICE_DATA_STA) & (slice_data_cnt == (slice_data_cnt_lim-1));
    
   assign crc_en_t    = (tx_dst_rdy) & 
           (((auro_frame_state == HEAD_DATA_STA) ) |
                ((auro_frame_state    == SLICE_DATA_STA)));
`endif
  
   assign crc_en = crc_en_t & (~(crc_tx_1_en |crc_tx_2_en) ) ;
   
  
   assign clear_crc_t  = (auro_frame_state    == HEAD_SOF_STA) |
          (auro_frame_state    == SLICE_SOF_STA) ;

   /*
   reg     clear_crc;

   always @(posedge gtx_user_clk_in) begin
      if(aurora_sw_rst) begin
    clear_crc   <= 'h0;
      end
      else begin
    clear_crc   <= clear_crc_t;
      end
   end
   */

   wire  clear_crc;

   assign clear_crc = clear_crc_t;
   
   
   assign crc_tx_1_en      = (eof_cnt == 'h0) & ((auro_frame_state == HEAD_EOF_STA) | (auro_frame_state == SLICE_EOF_STA)) ;
   assign crc_tx_2_en      = eof_cnt_rch      & ((auro_frame_state == HEAD_EOF_STA) | (auro_frame_state == SLICE_EOF_STA)) ;
   
      
   /////////////////////////////////////////////////////
   assign tx_sof_refresh = (auro_frame_state == REFRESH_DATA) & (tx_dst_rdy) & (ref_data_cnt == 'h0);
   assign tx_eof_refresh = (auro_frame_state == REFRESH_DATA) & (tx_dst_rdy) & (ref_data_cnt_rch);
   
   assign tx_src_rdy_refresh = tx_sof_refresh | tx_eof_refresh;
   
   
   assign tx_sof_n_out = ~(tx_sof_out | tx_sof_refresh);
   assign tx_eof_n_out = ~(tx_eof_out | tx_eof_refresh);
   assign tx_src_rdy_n_out = ~(tx_src_rdy_out | tx_src_rdy_refresh);

   wire [11:0] PROJECT_CODE   = 'h043;
   wire [3:0]  PROTOCAL_CODE  = 'h3;
   wire [3:0]  REFRESH_ID  = 'h2;

 /*
   assign tx_d_out_t =  tx_sof_refresh ?  32'h00000100 :  //32'h00000200  //zhangdq
                      tx_eof_refresh ? {PROJECT_CODE,PROTOCAL_CODE,REFRESH_ID,12'h0} :
                      idle_frame_ind ? idle_data_out : 
             aurora_frame_fifo_dout;
    */
`ifdef  TX_DATA_WIDTH_32
   wire [31:0] tx_d_out_t;
   wire [31:0] tx_d_out;
   
   
   assign      tx_d_out =  fault_gen_inject_ind ? {12'hFAE,tx_d_out_t[19:0]} : tx_d_out_t;
  
   assign      tx_d_out_t    =  tx_sof_refresh ? {32'h00000100}  :  //32'h00000200  //zhangdq
                 tx_eof_refresh ?  {PROJECT_CODE,PROTOCAL_CODE,REFRESH_ID,12'h0}:
                 idle_frame_ind ? idle_data_out : 
                 aurora_frame_fifo_dout;         
`else
   wire [63:0] tx_d_out_t;
   wire [63:0] tx_d_out;
   
   
   assign tx_d_out   = fault_gen_inject_ind ? {12'hFAE,tx_d_out_t[51:0]} : tx_d_out_t;
  
   assign tx_d_out_t = tx_sof_refresh ? {PROJECT_CODE,PROTOCAL_CODE,REFRESH_ID,12'h0,32'h00000100}  :  //32'h00000200  //zhangdq
                       tx_eof_refresh ? {PROJECT_CODE,PROTOCAL_CODE,REFRESH_ID,12'h0,32'h00000100} :
                       idle_frame_ind ? idle_data_out : 
                       aurora_frame_fifo_dout;
`endif
   //wire   fifo_wr_en    = wr_en & (~fifo_reset);
  
  
   //------------------------------Diag --------------------------------------------
   
   reg                             Diag_aurora_data_err_out;
   
   assign data_sof =  (tx_dst_rdy) & (auro_frame_state == SLICE_SOF_STA) ; 

`ifdef TX_DATA_WIDTH_32
   assign  set_Diag_aurora_data_err_out = data_sof  & sof_cnt_rch & (tx_d_out[31:12] != 'h4330);
`else
   assign  set_Diag_aurora_data_err_out = data_sof  & sof_cnt_rch & (tx_d_out[63:44] != 'h4330);
`endif
   always @(posedge gtx_user_clk_in) begin
      if(aurora_sw_rst) begin
         Diag_aurora_data_err_out   <= 'h0;
      end
      else if(set_Diag_aurora_data_err_out && (~rst_local))begin
         Diag_aurora_data_err_out   <= 'h1;
      end
      else begin
         Diag_aurora_data_err_out   <= 'h0;
      end
   end
   
  
   
    reg  Diag_aurora_header_err_out;
    reg  aurora_first_view;
          
    assign head_sof = (tx_dst_rdy) & (auro_frame_state == HEAD_SOF_STA)  ;

`ifdef TX_DATA_WIDTH_32
    assign set_Diag_aurora_header_err_out = head_sof & sof_cnt_rch & (tx_d_out[31:12] != 'h4331);
    assign aurora_first_view_temp = (header_cnt == 'h0) &
               tx_d_out[20] & //
               (auro_frame_state == HEAD_DATA_STA) & 
                  tx_src_rdy_out;          
`else
    assign set_Diag_aurora_header_err_out = head_sof & sof_cnt_rch & (tx_d_out[63:44] != 'h4331);
    assign aurora_first_view_temp = (header_cnt == 'h0) &
               tx_d_out[20] & //
               (auro_frame_state == HEAD_DATA_STA) & 
            tx_src_rdy_out;
`endif   

  
   
   always @(posedge gtx_user_clk_in) begin
      if(aurora_sw_rst) begin
        Diag_aurora_header_err_out   <= 'h0;
      end
      else if (set_Diag_aurora_header_err_out && (~rst_local)) begin
        Diag_aurora_header_err_out   <= 'h1;
      end
      else begin
         Diag_aurora_header_err_out   <= 'h0;
      end
   end

   
   
  
    always @(posedge gtx_user_clk_in) begin
      if(aurora_sw_rst) begin
    aurora_first_view   <= 'h0;
      end
      else begin
    aurora_first_view   <= aurora_first_view_temp;
      end
    end

   
  
   always @(posedge gtx_user_clk_in) begin
      if(aurora_sw_rst) begin
        pulse_1us_d           <= 'h0;
        pulse_1us_dd    <= 'h0;
        pulse_1us_ddd   <= 'h0;
      end
      else begin
        pulse_1us_d     <=  clk_40mhz_1us_in;
        pulse_1us_dd    <= pulse_1us_d;
        pulse_1us_ddd   <= pulse_1us_dd;
      end
   end

   reg [15:0]                       aurora_idle_cnt;
   
   always @(posedge gtx_user_clk_in) begin
      if(aurora_sw_rst) begin
        aurora_idle_cnt   <= 'h0;
      end
      else if(tx_eof_out) begin
        aurora_idle_cnt   <= 'h0;
      end
      else if(pulse_1us_dd && (~pulse_1us_ddd)) begin
        aurora_idle_cnt   <= aurora_idle_cnt + 1'h1;
      end
   end

   reg                             Diag_auroradata_en_rise_flag_out;
   
   always @(posedge gtx_user_clk_in) begin
      if(aurora_sw_rst) begin
        Diag_auroradata_en_rise_flag_out   <= 'h0;
      end
      else if(aurora_idle_cnt == 'h2710)begin
        Diag_auroradata_en_rise_flag_out   <= 'h1;
      end
      else begin
        Diag_auroradata_en_rise_flag_out   <= 'h0;
      end
   end
   
   
   reg [3:0] auro_frame_state_test;
    
   always @(posedge gtx_user_clk_in) begin
      auro_frame_state_test   <= auro_frame_state;
   end
   
   
endmodule // aurora_frame
