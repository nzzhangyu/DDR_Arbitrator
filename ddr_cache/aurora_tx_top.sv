//--------------------------------------------------------------------------------
// Company: Neusoft Medical Systems
// Engineer: zhang_dq
// 
// Create Date:     29/06/2021 
// Design Name:    
// Module Name:     aurora_tx_top
// Project Name:   H72
// Target Devices: 
// Tool versions: 
// Description:  
//
// Dependencies: generate aurora frame     
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//--------------------------------------------------------------------------------
`include "h80_define.sv"
`timescale 1ns/1ps
module aurora_tx_top(
`ifdef TX_DATA_WIDTH_32
             tx_rem_out, tx_d_out,
`else
             tx_rem_out, tx_d_out,
`endif

           /*AUTOARG*/
   // Outputs
   aurora_asy_fifo_almost_full, Diag_aurora_data_err_out,
   Diag_aurora_header_err_out, Diag_auroradata_en_rise_flag_out,
   tx_sof_n_out, tx_eof_n_out, tx_src_rdy_n_out,
   aurora_tx_fifo_overflow, aurora_tx_fifo_underflow, idle_process_en,
   view_tx_done, aurora_first_view, crc_error, auro_frame_state_test,
   make_data_p_rst_gtx, aurora_frame_fifo_empty,
   aurora_frame_fifo_prog_empty,
   // Inputs
   user_r_data, user_r_valid, ui_clk, ddr_user_rst, console_reset_in,
   aurora_tx_reset, TX_CHANNEL_UP_in, rst_local_t_ddr_clk,
   rst_local_t_gtx_clk, refresh_process_en, gtx_user_clk_in,
   clk_40mhz_1us_in, Fault_inject_en, slice_sel, tx_dst_rdy_n_in,
   DMS_Type, L_FTP_temp, R_FTP_temp, make_data_on, sampling_data_on,
   conv, gtx_clk_last_view_trans_fsh, rp_back_en_rst,
   slice_length_odd, slice_length_even
   );

   
    
   input [127:0]         user_r_data;                      //ddr mig read data 
   input              user_r_valid;                     //ddr mig read data valid 
   
   input                            ui_clk ;                  // system clock 100M
   input                            ddr_user_rst ;            // ddr_controller sys_rst_buf;
   
   input                            console_reset_in ;               // console_reset from rcom_ctrl 
   input                            aurora_tx_reset ;                // aurora_tx_reset (gtx_clk locked )
   input                            TX_CHANNEL_UP_in;
                                   
   input                            rst_local_t_ddr_clk;             //1 active
   input                            rst_local_t_gtx_clk;             //0 active
                                   
   input                            refresh_process_en ;             // refresh frame process enable (from view_retrans_ctrl)
   
   input                            gtx_user_clk_in ;                // aurora_8b10b user clock 
   input                            clk_40mhz_1us_in;                // 40Mhz clock
   input              Fault_inject_en;
   
   input [8:0]                      slice_sel;                       // slice_sel setting 
  
   output                           aurora_asy_fifo_almost_full;// FIFO almost full with threshold  512 
   output                           Diag_aurora_data_err_out;        
   output                           Diag_aurora_header_err_out; 
   output                           Diag_auroradata_en_rise_flag_out;
   
   // aurora_8b10b interface
`ifdef TX_DATA_WIDTH_32
   output [1:0]                     tx_rem_out ;                     
   output [31:0]                    tx_d_out;
`else
   output [2:0]                     tx_rem_out ;                     
   output [63:0]                    tx_d_out;
   
`endif

   input                            tx_dst_rdy_n_in ; 
   output                           tx_sof_n_out ;
   output                           tx_eof_n_out ;
   output                           tx_src_rdy_n_out ;
   
   output                           aurora_tx_fifo_overflow;          //pulse 
   output                           aurora_tx_fifo_underflow;         //pulse 

   //output              aurora_sw_rst;  // to crc_check.v 

   //idle frame gen interface
   input [7:0]              DMS_Type;
   input [15:0]          L_FTP_temp;
   input [15:0]          R_FTP_temp;
   
   input              make_data_on;

   input              sampling_data_on;
   input              conv;
   
   output             idle_process_en;
   output             view_tx_done;
   output             aurora_first_view;

  
   input              gtx_clk_last_view_trans_fsh;

   input              rp_back_en_rst;    //to aurora_tx_frame.v

   input [11:0]          slice_length_odd;
   input [11:0]          slice_length_even;

   output             crc_error;
   
   output [3:0]          auro_frame_state_test;
   output             make_data_p_rst_gtx;
   
   output             aurora_frame_fifo_empty;
   output             aurora_frame_fifo_prog_empty;
   
   

`ifdef TX_DATA_WIDTH_32
   wire [31:0]              tx_d_out;
   wire [31:0]              idle_data_out;   
   wire [31:0]              aurora_frame_fifo_dout;
`else 
   wire [63:0]              tx_d_out;
   wire [63:0]              idle_data_out;   
   wire [63:0]              aurora_frame_fifo_dout;
`endif

   
   wire            aurora_asy_fifo_almost_full_in;// To idle_frame_gen of idle_frame_gen.v
   wire            aurora_frame_fifo_empty;// To aurora_tx_frame of aurora_tx_frame.v
   wire            aurora_frame_fifo_prog_empty;// To aurora_tx_frame of aurora_tx_frame.v

   wire [11:0]              slice_length_min;

   assign             slice_length_min  = (slice_length_odd < slice_length_even) ? slice_length_odd : slice_length_even;

   
   /*AUTOREGINPUT*/
   
   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire        clear_crc;     // From aurora_tx_frame of aurora_tx_frame.v
   wire        crc_en;        // From aurora_tx_frame of aurora_tx_frame.v
   wire        crc_tx_1_en;      // From aurora_tx_frame of aurora_tx_frame.v
   wire        crc_tx_2_en;      // From aurora_tx_frame of aurora_tx_frame.v
   wire        footer_1_en;      // From aurora_tx_frame of aurora_tx_frame.v
   wire        footer_en;     // From aurora_tx_frame of aurora_tx_frame.v
   wire        gtx_refresh_process_en; // From aurora_tx_frame of aurora_tx_frame.v
   wire        header_cmd_1_en;  // From aurora_tx_frame of aurora_tx_frame.v
   wire        header_cmd_2_en;  // From aurora_tx_frame of aurora_tx_frame.v
   wire [7:0]     header_cnt;    // From aurora_tx_frame of aurora_tx_frame.v
   wire        header_en;     // From aurora_tx_frame of aurora_tx_frame.v
   wire        idle_frame_ind;      // From aurora_tx_frame of aurora_tx_frame.v
   wire        idle_header_ctl_word_en_out;// From idle_frame_gen of idle_frame_gen_32.v, ...
   wire        idle_process_active_debug_out;// From idle_frame_gen of idle_frame_gen_32.v, ...
   wire        idle_process_active_out;// From idle_frame_gen of idle_frame_gen_32.v, ...
   wire        idle_slice_data_en;  // From aurora_tx_frame of aurora_tx_frame.v
   wire        idle_slice_trans_start; // From idle_frame_gen of idle_frame_gen_32.v, ...
   wire        idle_trig;     // From idle_frame_gen of idle_frame_gen_32.v, ...
   wire        slice_cmd_1_en;      // From aurora_tx_frame of aurora_tx_frame.v
   wire        slice_cmd_2_en;      // From aurora_tx_frame of aurora_tx_frame.v
   wire [7:0]     slice_cnt;     // From aurora_tx_frame of aurora_tx_frame.v
   wire [9:0]     slice_data_cnt;      // From aurora_tx_frame of aurora_tx_frame.v
   wire        view_start_cnt_half; // From aurora_tx_frame of aurora_tx_frame.v
   // End of automatics

  
   wire            full;
   wire                             valid;
   wire                             prog_full;
   
   wire [127:0]                     din;
   wire                             wr_en;
   wire                             fifo_rd_en;
   
   assign   aurora_asy_fifo_almost_full = prog_full;
   wire     aurora_sw_rst;
   
   assign   aurora_sw_rst = (aurora_tx_reset) ;
  
   assign   fifo_wr_en = user_r_valid;

   (* ASYNC_REG    = "true" *) reg      make_data_on_d;
   (* ASYNC_REG    = "true" *) reg      make_data_on_dd;
   (* ASYNC_REG    = "true" *) reg      make_data_on_ddd;
   
   always @(posedge gtx_user_clk_in) begin
      make_data_on_d      <= make_data_on;
      make_data_on_dd     <= make_data_on_d;
      make_data_on_ddd   <= make_data_on_dd;
   end
   
   assign make_data_p_edge_gtx = make_data_on_dd && (~make_data_on_ddd);
   
   reg [5:0] make_data_dly_cnt;
   wire       make_data_p_rst;
   wire      make_data_dly_cnt_rch;
   

   assign    make_data_p_rst     = ~make_data_dly_cnt_rch;
   assign    make_data_p_rst_gtx = make_data_p_rst;
   

   assign    make_data_dly_cnt_rch = make_data_dly_cnt[5];
   
   
   always @(posedge gtx_user_clk_in) begin
      if(aurora_tx_reset) begin
         make_data_dly_cnt  <= 'h0;
      end
      else if (make_data_p_edge_gtx)  begin
    make_data_dly_cnt  <= 'h0;
      end
      else if (~make_data_dly_cnt_rch) begin
    make_data_dly_cnt  <= make_data_dly_cnt + 'h1;
      end
   end
          

   wire     rst_local;
   reg       rp_back_en_rst_d;
   reg       rp_back_en_rst_dd;
   
   always @(posedge gtx_user_clk_in) begin
      rp_back_en_rst_d    <= rp_back_en_rst;
      rp_back_en_rst_dd   <= rp_back_en_rst_d;
   end

   //reset aurora_tx_frame  0 active 
   assign   rst_local_t_gtx_clk_n = (rst_local_t_gtx_clk) & (~rp_back_en_rst_dd) & (~make_data_p_rst);

   //reset crc_gen and fifo  1 active 
   assign   rst_local =  ~rst_local_t_gtx_clk_n;

    //reset trans_frame_type_ctrl  0 active 
   assign   rst_idle_process_n     =  rst_local_t_gtx_clk & (~make_data_p_rst);

   //reset idle frame gen  1 active 
   assign   rst_idle_frame_gen_n   =  ~rst_local_t_gtx_clk;
      
   //assign    din                             = {user_r_data[95:64],user_r_data[127:96],
   //                   user_r_data[31:0],user_r_data[63:32]};
 `ifdef  TX_DATA_WIDTH_32  
   assign   din                             = {user_r_data[31:0],user_r_data[63:32],user_r_data[95:64],user_r_data[127:96]};
 `else
   assign   din                             = {user_r_data[63:0],user_r_data[127:64]};
 `endif
   
   wire  crc_rst ;

   assign   crc_rst  = rst_local |  aurora_tx_reset;

   wire     wr_rst_busy;
   wire     rd_rst_busy;

   
`ifdef  TX_DATA_WIDTH_32
   wire [12:0]    prog_empty_thresh;
   
   assign   prog_empty_thresh = {2'h0,slice_length_min[11:1]}; // SLICE_DATA_NUM/2 

   aurora_frame_fifo_32 aurora_frame_fifo(///*AUTOINST*/
                                        // Outputs
                                        .dout                  (aurora_frame_fifo_dout[31:0]),
                                        .full                  (full),
                                        .empty                 (aurora_frame_fifo_empty),
                                        .valid                 (valid),
                                        .prog_full             (prog_full),
                                        .prog_empty            (aurora_frame_fifo_prog_empty),
                                        .wr_rst_busy           (wr_rst_busy ),
                                        .rd_rst_busy           (rd_rst_busy ),
                                        // Inputs
                                        .rst                   (rst_local),
                                        .wr_clk                (ui_clk),
                                        .rd_clk                (gtx_user_clk_in),
                                        //.din                   (user_r_data),
                                        .din                   (din),
                                        .wr_en                 (fifo_wr_en),
                                        .rd_en                 (fifo_rd_en),
                                        .prog_empty_thresh     (prog_empty_thresh[12:0]));

`else
   wire [12:0]    prog_empty_thresh;
   
   assign             prog_empty_thresh = {3'h0,slice_length_min[11:2]}; // SLICE_DATA_NUM/4 

   aurora_frame_fifo   aurora_frame_fifo(///*AUTOINST*/
                                        // Outputs
                                        .dout                  (aurora_frame_fifo_dout[63:0]),
                                        .full                  (full),
                                        .empty                 (aurora_frame_fifo_empty),
                                        .valid                 (valid),
                                        .prog_full             (prog_full),
                                        .prog_empty            (aurora_frame_fifo_prog_empty),
                                        .wr_rst_busy           (wr_rst_busy ),
                                        .rd_rst_busy           (rd_rst_busy ),
                                        // Inputs
                                        .rst                   (rst_local),
                                        .wr_clk                (ui_clk),
                                        .rd_clk                (gtx_user_clk_in),
                                        //.din                   (user_r_data),
                                        .din                   (din),
                                        .wr_en                 (fifo_wr_en),
                                        .rd_en                 (fifo_rd_en),
                                        .prog_empty_thresh     (prog_empty_thresh[12:0]));

`endif
   
   trans_frame_type_ctrl  
                  trans_frame_type_ctrl(
               .rst_local_t_gtx_clk(rst_idle_process_n),
               /*AUTOINST*/
               // Outputs
               .idle_process_en(idle_process_en),
               // Inputs
               .aurora_sw_rst (aurora_sw_rst),
               .gtx_user_clk_in(gtx_user_clk_in),
               .sampling_data_on(sampling_data_on),
               .view_start_cnt_half(view_start_cnt_half),
               .view_tx_done  (view_tx_done),
               .gtx_clk_last_view_trans_fsh(gtx_clk_last_view_trans_fsh));
   

   aurora_tx_frame     aurora_tx_frame ( 
               .rst_local_t_gtx_clk(rst_local_t_gtx_clk_n),
`ifdef  TX_DATA_WIDTH_32
               .tx_rem_out (tx_rem_out[1:0]),
               .tx_d_out   (tx_d_out[31:0]),
                   .aurora_frame_fifo_dout(aurora_frame_fifo_dout[31:0]),
                   .idle_data_out   (idle_data_out[31:0]),
`else
                   .tx_rem_out   (tx_rem_out[2:0]),
                   .tx_d_out  (tx_d_out[63:0]),
                   .aurora_frame_fifo_dout(aurora_frame_fifo_dout[63:0]),
                   .idle_data_out   (idle_data_out[63:0]),
`endif
               
               /*AUTOINST*/
               // Outputs
               .Diag_aurora_data_err_out(Diag_aurora_data_err_out),
               .Diag_aurora_header_err_out(Diag_aurora_header_err_out),
               .Diag_auroradata_en_rise_flag_out(Diag_auroradata_en_rise_flag_out),
               .tx_sof_n_out  (tx_sof_n_out),
               .tx_eof_n_out  (tx_eof_n_out),
               .tx_src_rdy_n_out(tx_src_rdy_n_out),
               .fifo_rd_en (fifo_rd_en),
               .view_tx_done  (view_tx_done),
               .idle_frame_ind   (idle_frame_ind),
               .header_cnt (header_cnt[7:0]),
               .slice_cnt  (slice_cnt[7:0]),
               .slice_data_cnt   (slice_data_cnt[9:0]),
               .header_en  (header_en),
               .header_cmd_1_en(header_cmd_1_en),
               .header_cmd_2_en(header_cmd_2_en),
               .footer_en  (footer_en),
               .footer_1_en   (footer_1_en),
               .slice_cmd_1_en   (slice_cmd_1_en),
               .slice_cmd_2_en   (slice_cmd_2_en),
               .crc_tx_2_en   (crc_tx_2_en),
               .crc_tx_1_en   (crc_tx_1_en),
               .clear_crc  (clear_crc),
               .crc_en     (crc_en),
               .idle_slice_data_en(idle_slice_data_en),
               .view_start_cnt_half(view_start_cnt_half),
               .aurora_first_view(aurora_first_view),
               .gtx_refresh_process_en(gtx_refresh_process_en),
               .auro_frame_state_test(auro_frame_state_test[3:0]),
               // Inputs
               .ui_clk     (ui_clk),
               .ddr_user_rst  (ddr_user_rst),
               .console_reset_in(console_reset_in),
               .aurora_sw_rst (aurora_sw_rst),
               .TX_CHANNEL_UP_in(TX_CHANNEL_UP_in),
               .rst_local_t_ddr_clk(rst_local_t_ddr_clk),
               .refresh_process_en(refresh_process_en),
               .gtx_user_clk_in(gtx_user_clk_in),
               .clk_40mhz_1us_in(clk_40mhz_1us_in),
               .Fault_inject_en(Fault_inject_en),
               .slice_sel  (slice_sel[8:0]),
               .tx_dst_rdy_n_in(tx_dst_rdy_n_in),
               .aurora_frame_fifo_prog_empty(aurora_frame_fifo_prog_empty),
               .aurora_frame_fifo_empty(aurora_frame_fifo_empty),
               .idle_process_en(idle_process_en),
               .idle_trig  (idle_trig),
               .slice_length_odd(slice_length_odd[11:0]),
               .slice_length_even(slice_length_even[11:0]));

`ifdef TX_DATA_WIDTH_32
   idle_frame_gen_32                 
                      idle_frame_gen  ( 
                   .rst_local (rst_idle_frame_gen_n),          
               /*AUTOINST*/
                   // Outputs
                   .idle_process_active_out(idle_process_active_out),
                   .idle_process_active_debug_out(idle_process_active_debug_out),
                   .idle_header_ctl_word_en_out(idle_header_ctl_word_en_out),
                   .idle_slice_trans_start(idle_slice_trans_start),
                   .idle_trig (idle_trig),
                   .idle_data_out   (idle_data_out[31:0]),
                   // Inputs
                   .aurora_sw_rst   (aurora_sw_rst),
                   .gtx_user_clk_in (gtx_user_clk_in),
                   .idle_process_en (idle_process_en),
                   .conv      (conv),
                   .DMS_Type  (DMS_Type[7:0]),
                   .L_FTP_temp   (L_FTP_temp[15:0]),
                   .R_FTP_temp   (R_FTP_temp[15:0]),
                   .idle_frame_ind  (idle_frame_ind),
                   .header_cnt   (header_cnt[7:0]),
                   .slice_cnt (slice_cnt[7:0]),
                   .slice_data_cnt  (slice_data_cnt[9:0]),
                   .header_en (header_en),
                   .idle_slice_data_en(idle_slice_data_en),
                   .header_cmd_1_en (header_cmd_1_en),
                   .header_cmd_2_en (header_cmd_2_en),
                   .footer_en (footer_en),
                   .footer_1_en  (footer_1_en),
                   .slice_cmd_1_en  (slice_cmd_1_en),
                   .slice_cmd_2_en  (slice_cmd_2_en),
                   .crc_tx_1_en  (crc_tx_1_en),
                   .crc_tx_2_en  (crc_tx_2_en),
                   .clear_crc (clear_crc),
                   .crc_en    (crc_en),
                   .gtx_refresh_process_en(gtx_refresh_process_en));
`else
   
   idle_frame_gen                 
                      idle_frame_gen  ( 
                   .rst_local (rst_idle_frame_gen_n),          
               /*AUTOINST*/
                   // Outputs
                   .idle_process_active_out(idle_process_active_out),
                   .idle_process_active_debug_out(idle_process_active_debug_out),
                   .idle_header_ctl_word_en_out(idle_header_ctl_word_en_out),
                   .idle_slice_trans_start(idle_slice_trans_start),
                   .idle_trig (idle_trig),
                   .idle_data_out   (idle_data_out[63:0]),
                   // Inputs
                   .aurora_sw_rst   (aurora_sw_rst),
                   .gtx_user_clk_in (gtx_user_clk_in),
                   .idle_process_en (idle_process_en),
                   .conv      (conv),
                   .DMS_Type  (DMS_Type[7:0]),
                   .L_FTP_temp   (L_FTP_temp[15:0]),
                   .R_FTP_temp   (R_FTP_temp[15:0]),
                   .idle_frame_ind  (idle_frame_ind),
                   .header_cnt   (header_cnt[7:0]),
                   .slice_cnt (slice_cnt[7:0]),
                   .header_en (header_en),
                   .idle_slice_data_en(idle_slice_data_en),
                   .header_cmd_1_en (header_cmd_1_en),
                   .header_cmd_2_en (header_cmd_2_en),
                   .footer_en (footer_en),
                   .slice_cmd_1_en  (slice_cmd_1_en),
                   .slice_cmd_2_en  (slice_cmd_2_en),
                   .crc_tx_1_en  (crc_tx_1_en),
                   .crc_tx_2_en  (crc_tx_2_en),
                   .clear_crc (clear_crc),
                   .crc_en    (crc_en),
                   .gtx_refresh_process_en(gtx_refresh_process_en));
`endif   
   
`ifdef TX_DATA_WIDTH_32
   crc_chk_32          crc_chk     (/*AUTOINST*/
                // Outputs
                .crc_error    (crc_error),
                // Inputs
                .tx_sof_n_out (tx_sof_n_out),
                .tx_eof_n_out (tx_eof_n_out),
                .tx_src_rdy_n_out   (tx_src_rdy_n_out),
                .tx_d_out     (tx_d_out[31:0]),
                .crc_rst      (crc_rst),
                .gtx_user_clk_in (gtx_user_clk_in));
   
`else

   crc_chk             crc_chk     (/*AUTOINST*/
                // Outputs
                .crc_error    (crc_error),
                // Inputs
                .tx_sof_n_out (tx_sof_n_out),
                .tx_eof_n_out (tx_eof_n_out),
                .tx_src_rdy_n_out   (tx_src_rdy_n_out),
                .tx_d_out     (tx_d_out[63:0]),
                .crc_rst      (crc_rst),
                .gtx_user_clk_in (gtx_user_clk_in));
   
   
`endif
   //-----------------------use in chipscope ----------------------------------
   
   //monitor FIFO underflow and overflow 
   reg                aurora_tx_fifo_overflow;
   
   reg                aurora_tx_fifo_underflow;

   always  @(posedge ui_clk) begin
      if(ddr_user_rst || rst_local_t_ddr_clk || rp_back_en_rst) begin
        aurora_tx_fifo_overflow   <= 'h0;
      end
      else if (full && fifo_wr_en)  begin
        aurora_tx_fifo_overflow   <= 'h1;
      end
      else  begin
        aurora_tx_fifo_overflow   <= 'h0;
      end
   end
   
    always  @(posedge gtx_user_clk_in) begin
      if(aurora_tx_reset) begin
        aurora_tx_fifo_underflow  <= 'h0;
      end
      else if (rst_local) begin
    aurora_tx_fifo_underflow  <= 'h0;
      end
      else if (aurora_frame_fifo_empty && fifo_rd_en)  begin
        aurora_tx_fifo_underflow  <= 'h1;
      end
      else  begin
        aurora_tx_fifo_underflow  <= 'h0;
      end
   end

   

endmodule // aurora_tx_top
// local variables:
// verilog-library-flags:("-y ./ -y ../crc_chk ")
// end:
