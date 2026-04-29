`timescale 1ns/1ps
`include "h80_define.sv"
module ddr_cache_and_frame_gen(
`ifdef TX_DATA_WIDTH_32
                   tx_rem_out,   tx_d_out,
`else
                   tx_rem_out,   tx_d_out,
`endif 
                   /*AUTOARG*/
   // Outputs
   ddr_rd_req, req_stop, tx_sof_n_out, tx_eof_n_out, tx_src_rdy_n_out,
   aurora_tx_fifo_overflow, aurora_tx_fifo_underflow,
   aurora_asy_fifo_almost_full, Diag_aurora_data_err_out,
   Diag_aurora_header_err_out, Diag_auroradata_en_rise_flag_out,
   rp_back_en, rp_back_view_addr, sysclk_rp_back_en,
   aurora_first_view, cache_tp, crc_error, refresh_process_en,
   rd_cache_state, rd_wr_num_equ, auro_tx_status_reg_out,
   idle_process_en_out,
   // Inputs
   ui_clk, ddr_user_rst, rst_local_t_ddr_clk, gtx_user_clk_in,
   rst_local_t_gtx_clk, ddr_rd_empty, user_r_data, user_r_valid,
   clk_40mhz_1us_in, Fault_inject_en, make_data_on, aurora_tx_reset_n,
   TX_CHANNEL_UP_in, tx_dst_rdy_n_in, DMS_Type, L_FTP_temp,
   R_FTP_temp, sampling_data_on, clk_sysclk_in, sys_rst,
   console_reset_in, conv, slice_sel, view_size, view_Reading_Done,
   last_view_wr_done, comm_ok_disable, comm_ok, slice_length_odd,
   slice_length_even, clk_40m, rst_40m, dms_err_rst
   );
  
   parameter               ADDR_WIDTH = 24; //2g
   
   parameter               SYS_CLK2UI_CLK_PULSE_WIDTH = 'h8;
   parameter               GTX_CLK2UI_CLK_PULSE_WIDTH = 'h8;
   parameter               UI_CLK2SYS_CLK_PULSE_WIDTH = 'h8;
   parameter               UI_CLK2GTX_CLK_PULSE_WIDTH = 'hc;
   
   
   input                           ui_clk;                           // ddr user clock 
   input                           ddr_user_rst;                     // ddr_controller sys_rst_buf;
   input                           rst_local_t_ddr_clk;              // local reset for ddr ui_clk 
                                   
   input                           gtx_user_clk_in;                  // GTP clock  
   input               rst_local_t_gtx_clk;              //0 active
   
   
   input               ddr_rd_empty;
   output                          ddr_rd_req;                       //request for reading the data from DDR 
   output              req_stop;
   //ddr read data 
   input [127:0]           user_r_data;                      //ddr mig read data 
   input                           user_r_valid;                     //ddr mig read data valid 
                                   
  
   
   input               clk_40mhz_1us_in;                // 40Mhz clock      
   input                Fault_inject_en;                            
                                    
   input                           make_data_on;

   input               aurora_tx_reset_n;                //from reset_clock_ctrl.vhd
   
  
   // aurora_8b10b interface
`ifdef TX_DATA_WIDTH_32
   output [1:0]            tx_rem_out ;                     
   output [31:0]           tx_d_out; 
`else   
   output [2:0]            tx_rem_out ;                     
   output [63:0]           tx_d_out; 
`endif

   input               TX_CHANNEL_UP_in;
   
   input               tx_dst_rdy_n_in ;
   
   output                           tx_sof_n_out ;
   output                           tx_eof_n_out ;
   output                           tx_src_rdy_n_out ;
   
   output                           aurora_tx_fifo_overflow;          //pulse 
   output                           aurora_tx_fifo_underflow;         //pulse 

   
   //idle frame gen interface
   input [7:0]              DMS_Type;
   input [15:0]             L_FTP_temp;
   input [15:0]             R_FTP_temp;
   
   input                sampling_data_on;

   //////////////////////////////////////////
   
   output                           aurora_asy_fifo_almost_full ;// FIFO almost full with threshold  512 
   output                           Diag_aurora_data_err_out;        
   output                           Diag_aurora_header_err_out; 
   output                           Diag_auroradata_en_rise_flag_out;

   input                clk_sysclk_in;
   input                sys_rst;
   
   input                console_reset_in;
   input                conv;
   input [8:0]              slice_sel;
   input [15:0]             view_size;
   
   input                view_Reading_Done; //from reading_header_slice_gen
   //input              LastViewFlag; 
   input                last_view_wr_done;
   
   
   input                comm_ok_disable;
   input                comm_ok;
   
   //output                 last_view_trans_ok;  //ui_clock pulse of 16 cycle 
   //output                 last_view_retran_end;
   
   //input [ADDR_WIDTH-1:0]         user_ad_rd;        // from user_rw_cmd_gen.v 
   //output [ADDR_WIDTH-1:0]        rp_user_ad_rd;     //  to  user_rw_cmd_gen.v 
   output               rp_back_en;        //  to  user_rw_cmd_gen.v
   //output [1:0]           rp_back_num;
   output [ADDR_WIDTH-1:0]      rp_back_view_addr;

   
   output               sysclk_rp_back_en; //to reading_header  and glue.vhd 
   
   //output                 clr_cache_view_cnt;
   //output [11:0]          view_size;

  
   output               aurora_first_view;
   output [3:0]             cache_tp;
   
   input [11:0]             slice_length_odd;
   input [11:0]             slice_length_even;
   output               crc_error;

 
   output               refresh_process_en;      
   output [1:0]             rd_cache_state;
   output               rd_wr_num_equ;

   input                         clk_40m;
   input                 rst_40m;
   input                 dms_err_rst;

   output [15:0]             auro_tx_status_reg_out;
   output                idle_process_en_out;
   
   
   /*AUTOREGINPUT*/

   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire [3:0]       auro_frame_state_test;  // From aurora_tx_top of aurora_tx_top.v
   wire         aurora_frame_fifo_empty;// From aurora_tx_top of aurora_tx_top.v
   wire         aurora_frame_fifo_prog_empty;// From aurora_tx_top of aurora_tx_top.v
   wire         idle_process_en;    // From aurora_tx_top of aurora_tx_top.v
   wire         last_view_trans_ok; // From rd_cache_ctrl of rd_cache_ctrl.v
   wire         make_data_p_rst_gtx;    // From aurora_tx_top of aurora_tx_top.v
   wire         rp_back_cnt_add_en; // From commok_check of commok_check.v
   wire         rp_back_en_i;       // From commok_check of commok_check.v
   wire         rp_back_en_rst;     // From commok_check of commok_check.v
   wire         sample_frame_rd_done;   // From rd_cache_ctrl of rd_cache_ctrl.v
   wire         uiclk_pulse_1us;    // From commok_check of commok_check.v
   wire         view_trans_ok;      // From commok_check of commok_check.v
   wire         view_tx_done;       // From aurora_tx_top of aurora_tx_top.v
   // End of automatics
   wire         ui_clk_rd_view_pulse;
   wire         uiclk_update_rd_view_num;
   
   wire         gtx_clk_last_view_trans_fsh;
   wire         aurora_tx_reset;                //from reset_clock_ctrl.vhd

   assign       aurora_tx_reset = ~aurora_tx_reset_n;
   
   
   assign       cache_tp = {2'h0,last_view_trans_ok,1'h0};
 
   (* ASYNC_REG = "true" *) reg idle_process_en_rcom_cdc_to_d;
   (* ASYNC_REG = "true" *) reg idle_process_en_dd;
   
   always @(posedge ui_clk) begin
      if(ddr_user_rst) begin
     idle_process_en_rcom_cdc_to_d   <= 'h0;
     idle_process_en_dd          <= 'h0;
      end
      else begin 
     idle_process_en_rcom_cdc_to_d   <= idle_process_en;
     idle_process_en_dd          <= idle_process_en_rcom_cdc_to_d;
      end
   end
   
   rd_cache_ctrl                          #(
                          .ADDR_WIDTH                      (ADDR_WIDTH),
                          .GTX_CLK2UI_CLK_PULSE_WIDTH      (GTX_CLK2UI_CLK_PULSE_WIDTH),
                          .SYS_CLK2UI_CLK_PULSE_WIDTH      (SYS_CLK2UI_CLK_PULSE_WIDTH),
                          .UI_CLK2GTX_CLK_PULSE_WIDTH      (UI_CLK2GTX_CLK_PULSE_WIDTH)
                          )
                               rd_cache_ctrl (.idle_process_en  (idle_process_en_dd),
                          /*AUTOINST*/
                          // Outputs
                          .ddr_rd_req   (ddr_rd_req),
                          .req_stop     (req_stop),
                          .rp_back_view_addr(rp_back_view_addr[ADDR_WIDTH-1:0]),
                          .last_view_trans_ok(last_view_trans_ok),
                          .sample_frame_rd_done(sample_frame_rd_done),
                          .rd_cache_state   (rd_cache_state[1:0]),
                          .rd_wr_num_equ    (rd_wr_num_equ),
                          // Inputs
                          .ui_clk       (ui_clk),
                          .ddr_user_rst (ddr_user_rst),
                          .rst_local_t_ddr_clk(rst_local_t_ddr_clk),
                          .clk_sysclk_in    (clk_sysclk_in),
                          .sys_rst      (sys_rst),
                          .view_Reading_Done(view_Reading_Done),
                          .last_view_wr_done(last_view_wr_done),
                          .refresh_process_en(refresh_process_en),
                          .TX_CHANNEL_UP_in (TX_CHANNEL_UP_in),
                          .aurora_asy_fifo_almost_full(aurora_asy_fifo_almost_full),
                          .ddr_rd_empty (ddr_rd_empty),
                          .make_data_on (make_data_on),
                          .view_size    (view_size[15:0]),
                          .user_r_valid (user_r_valid),
                          .rp_back_en_i (rp_back_en_i),
                          .rp_back_en_rst   (rp_back_en_rst),
                          .uiclk_pulse_1us  (uiclk_pulse_1us),
                          .view_trans_ok    (view_trans_ok));
   
   
   aurora_tx_top               aurora_tx_top (
`ifdef TX_DATA_WIDTH_32

                          .tx_rem_out   (tx_rem_out[1:0]),
                          .tx_d_out     (tx_d_out[31:0]),
`else

                          .tx_rem_out   (tx_rem_out[2:0]),
                          .tx_d_out     (tx_d_out[63:0]),
`endif
                          
                          /*AUTOINST*/
                          // Outputs
                          .aurora_asy_fifo_almost_full(aurora_asy_fifo_almost_full),
                          .Diag_aurora_data_err_out(Diag_aurora_data_err_out),
                          .Diag_aurora_header_err_out(Diag_aurora_header_err_out),
                          .Diag_auroradata_en_rise_flag_out(Diag_auroradata_en_rise_flag_out),
                          .tx_sof_n_out (tx_sof_n_out),
                          .tx_eof_n_out (tx_eof_n_out),
                          .tx_src_rdy_n_out (tx_src_rdy_n_out),
                          .aurora_tx_fifo_overflow(aurora_tx_fifo_overflow),
                          .aurora_tx_fifo_underflow(aurora_tx_fifo_underflow),
                          .idle_process_en  (idle_process_en),
                          .view_tx_done (view_tx_done),
                          .aurora_first_view(aurora_first_view),
                          .crc_error    (crc_error),
                          .auro_frame_state_test(auro_frame_state_test[3:0]),
                          .make_data_p_rst_gtx(make_data_p_rst_gtx),
                          .aurora_frame_fifo_empty(aurora_frame_fifo_empty),
                          .aurora_frame_fifo_prog_empty(aurora_frame_fifo_prog_empty),
                          // Inputs
                          .user_r_data  (user_r_data[127:0]),
                          .user_r_valid (user_r_valid),
                          .ui_clk       (ui_clk),
                          .ddr_user_rst (ddr_user_rst),
                          .console_reset_in (console_reset_in),
                          .aurora_tx_reset  (aurora_tx_reset),
                          .TX_CHANNEL_UP_in (TX_CHANNEL_UP_in),
                          .rst_local_t_ddr_clk(rst_local_t_ddr_clk),
                          .rst_local_t_gtx_clk(rst_local_t_gtx_clk),
                          .refresh_process_en(refresh_process_en),
                          .gtx_user_clk_in  (gtx_user_clk_in),
                          .clk_40mhz_1us_in (clk_40mhz_1us_in),
                          .Fault_inject_en  (Fault_inject_en),
                          .slice_sel    (slice_sel[8:0]),
                          .tx_dst_rdy_n_in  (tx_dst_rdy_n_in),
                          .DMS_Type     (DMS_Type[7:0]),
                          .L_FTP_temp   (L_FTP_temp[15:0]),
                          .R_FTP_temp   (R_FTP_temp[15:0]),
                          .make_data_on (make_data_on),
                          .sampling_data_on (sampling_data_on),
                          .conv     (conv),
                          .gtx_clk_last_view_trans_fsh(gtx_clk_last_view_trans_fsh),
                          .rp_back_en_rst   (rp_back_en_rst),
                          .slice_length_odd (slice_length_odd[11:0]),
                          .slice_length_even(slice_length_even[11:0]));
   
   commok_check                              #(
                           .ADDR_WIDTH                      (ADDR_WIDTH)
                           )
              commok_check            ( 
                        .idle_process_en    (idle_process_en_dd),
                           /*AUTOINST*/
                           // Outputs
                           .rp_back_en_rst  (rp_back_en_rst),
                           .rp_back_en  (rp_back_en),
                           .rp_back_en_i    (rp_back_en_i),
                           .rp_back_cnt_add_en(rp_back_cnt_add_en),
                           .view_trans_ok   (view_trans_ok),
                           .refresh_process_en(refresh_process_en),
                           .uiclk_pulse_1us (uiclk_pulse_1us),
                           // Inputs
                           .ui_clk      (ui_clk),
                           .ddr_user_rst    (ddr_user_rst),
                           .rst_local_t_ddr_clk(rst_local_t_ddr_clk),
                           .clk_40mhz_1us_in(clk_40mhz_1us_in),
                           .comm_ok_disable (comm_ok_disable),
                           .comm_ok     (comm_ok),
                           .ui_clk_rd_view_pulse(ui_clk_rd_view_pulse),
                           .sample_frame_rd_done(sample_frame_rd_done));

   //-------------------------ui_clk to sys_clk ----------------------------------------
   
    
   cross_clk_pulse                    #(
                    .PULSE_WIDTH    (UI_CLK2SYS_CLK_PULSE_WIDTH)
                       )
                rp_back_en_sys_gen_dut (///*AUTOINST*/
                    // Outputs
                    .o      (sysclk_rp_back_en),
                    // Inputs
                    .i      (rp_back_cnt_add_en),
                    .i_clk      (ui_clk),
                    .i_rst      (ddr_user_rst),
                    .o_clk      (clk_sysclk_in),
                    .o_rst      (sys_rst));

   //-------------------------ui_clk to gtx_clk ----------------------------------------
   
   cross_clk_pulse                       #(
                       .PULSE_WIDTH        (UI_CLK2GTX_CLK_PULSE_WIDTH)
                       )
        last_view_trans_fsh_gen_dut (///*AUTOINST*/
                    // Outputs
                    .o          (gtx_clk_last_view_trans_fsh),
                    // Inputs
                    .i          (last_view_trans_ok),
                    .i_clk      (ui_clk),
                    .i_rst      (ddr_user_rst),
                    .o_clk      (gtx_user_clk_in),
                    .o_rst      (aurora_tx_reset));

   //-------------------------gtc_clk to ui_clk ----------------------------------------
    cross_clk_pulse                        #(
                       .PULSE_WIDTH        (GTX_CLK2UI_CLK_PULSE_WIDTH)
                       )
                   rd_view_pulse_gen_dut (///*AUTOINST*/
                         // Outputs
                         .o         (ui_clk_rd_view_pulse),
                         // Inputs
                         .i         (view_tx_done),
                         .i_clk         (gtx_user_clk_in),
                         .i_rst         (aurora_tx_reset),
                         .o_clk         (ui_clk),
                         .o_rst         (ddr_user_rst));

   gtx_status_reg      gtx_status_reg  (/*AUTOINST*/
                    // Outputs
                    .auro_tx_status_reg_out(auro_tx_status_reg_out[15:0]),
                    .idle_process_en_out(idle_process_en_out),
                    // Inputs
                    .clk_40m    (clk_40m),
                    .rst_40m    (rst_40m),
                    .dms_err_rst    (dms_err_rst),
                    .gtx_user_clk_in(gtx_user_clk_in),
                    .aurora_tx_reset(aurora_tx_reset),
                    .make_data_p_rst_gtx(make_data_p_rst_gtx),
                    .aurora_tx_fifo_underflow(aurora_tx_fifo_underflow),
                    .idle_process_en(idle_process_en),
                    .aurora_frame_fifo_prog_empty(aurora_frame_fifo_prog_empty),
                    .aurora_frame_fifo_empty(aurora_frame_fifo_empty),
                    .crc_error  (crc_error),
                    .auro_frame_state_test(auro_frame_state_test[3:0]),
                    .Diag_aurora_data_err_out(Diag_aurora_data_err_out),
                    .Diag_aurora_header_err_out(Diag_aurora_header_err_out),
                    .Diag_auroradata_en_rise_flag_out(Diag_auroradata_en_rise_flag_out));
   
   
   
   
endmodule // frame_tx
