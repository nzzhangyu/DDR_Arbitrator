`timescale 1ns/1ps
module user_rw_cmd_gen(/*AUTOARG*/
   // Outputs
   app_addr, app_cmd, app_en, app_wdf_data, app_wdf_end, app_wdf_mask,
   app_wdf_wren, app_sr_req, app_ref_req, app_zq_req,
   make_data_p_edge_ddr_clk, ddr_rd_empty, ddr_overrun, ddr_warning,
   ddr_wr_fifo_rd_en, qdr_dataout, qdr_dataout_en,
   // Inputs
   init_calib_complete, ui_clk, ui_clk_sync_rst, app_rd_data,
   app_rd_data_valid, app_rdy, app_wdf_rdy, qdr_rd_req, req_stop,
   make_data_on, view_size, rst_local_t_ddr_clk, fault_ddr_overrun,
   fault_ddr_warning, ddr_wr_fifo_empty, ddr_wr_fifo_prog_empty,
   ddr_wr_fifo_level, wr_fifo_overrun, ddr_wr_fifo_dout,
   cache_fifo_prog_full, cache_fifo_almost_empty, cache_fifo_data_count,
   rp_back_en, rp_back_view_addr
   );
   
    //parameter                      ADDR_WIDTH = 25;  //4g ddr
   parameter                       ADDR_WIDTH = 24;  //2g ddr 
                                   
                                    
   input                           init_calib_complete;
   input                           ui_clk;
   input                           ui_clk_sync_rst;
   
   // user interface signals
   output [30:0]                   app_addr;
   output [2:0]                    app_cmd;
   output                          app_en;
   output [127:0]                  app_wdf_data;
   output                          app_wdf_end;
   output [15:0]                   app_wdf_mask;
   output                          app_wdf_wren;
   input  [127:0]                  app_rd_data;
   //input                           app_rd_data_end;
   input                           app_rd_data_valid;
   input                           app_rdy;
   input                           app_wdf_rdy;
   output                          app_sr_req;
   output                          app_ref_req;
   output                          app_zq_req;
   //input                           app_sr_active;
   //input                           app_ref_ack;
   //input                           app_zq_ack;
                                   
   input                           qdr_rd_req;
   input 			                 req_stop;
   input                           make_data_on;
   input  [15:0] 		              view_size;
   output 			                 make_data_p_edge_ddr_clk;
      
   //input      user_wr_full;
   //input      user_rd_full;
   
   input                           rst_local_t_ddr_clk;
                                   
   
                                   
   //output [ADDR_WIDTH-1 : 0]       user_ad_wr;
   //output [ADDR_WIDTH-1 : 0]       user_ad_rd;
                                   
   //                              
   //output                            ddr_rd_empty;
   output                          ddr_rd_empty;
                                   
   input                           fault_ddr_overrun;
   input                           fault_ddr_warning;
                                   
   output                          ddr_overrun ;
   output                          ddr_warning;
   
   
   // rd_en of ddr_wr_fifo
   output                          ddr_wr_fifo_rd_en;
   input                           ddr_wr_fifo_empty;
                                   
   input                           ddr_wr_fifo_prog_empty;
   input  [13:0] 		              ddr_wr_fifo_level;
   input 			                 wr_fifo_overrun;
   //output 			   wr_fifo_underrun;
   
   
   //ddr_wr_fifo dout 
   input  [127:0]                  ddr_wr_fifo_dout;
   //input                           ddr_wr_fifo_dout_valid;
   
   //input from rd_coache
   input                           cache_fifo_prog_full;
   input                           cache_fifo_almost_empty;
   input  [13:0]                   cache_fifo_data_count;

   
   //output to qdriiplus_rd_top module 
   output [127:0]                  qdr_dataout;
   output                          qdr_dataout_en;

   //input [ADDR_WIDTH-1:0] 	   rp_user_ad_rd;     //  from user_rw_cmd_gen.v 
   input 			                 rp_back_en;        //  from rd_cache_ctrl.v 
   input  [ADDR_WIDTH-1:0] 	     rp_back_view_addr;
   //input [1:0] 			   rp_back_num;
   //input [ADDR_WIDTH-1:0] 	   rp_back_last_view_addr;

   //input 			   clr_cache_view_cnt;//  from user_rw_cmd_gen.v 
   //input [11:0] 		   view_size;         //  from user_rw_cmd_gen.v 
   //input 			   update_view_size;  //  from user_rw_cmd_gen.v 

   typedef enum logic [2:0] {
      RW_IDLE,
      RW_ARB_PRE,
      RW_ARB,
      RW_READ,
      RW_WRITE,
      RW_WRITE_POST
   } rw_state_t;

   localparam logic [13:0]         WR_LEVEL_LOW      = 14'd2048;
   localparam logic [13:0]         WR_LEVEL_HIGH     = 14'd8192;
   localparam logic [13:0]         WR_LEVEL_URGENT   = 14'd12288;
   localparam logic [13:0]         WR_LEVEL_CRITICAL = 14'd14336;

   localparam logic [13:0]         RD_LEVEL_URGENT   = 14'd4096;
   localparam logic [13:0]         RD_LEVEL_LOW      = 14'd8192;
   localparam logic [13:0]         RD_LEVEL_HIGH     = 14'd12288;

   localparam logic [8:0]          WR_GRANT_MAX      = 9'd256;
   localparam logic [9:0]          RD_GRANT_MAX      = 10'd512;
   localparam logic [9:0]          RD_GRANT_WR_HIGH  = 10'd128;
   
   
   //wire 			   read_one_view_lim;
   
   (* ASYNC_REG = "true" *) reg make_data_on_rcom_cdc_to_d;
   (* ASYNC_REG = "true" *) reg make_data_on_dd;
   (* ASYNC_REG = "true" *) reg make_data_on_ddd;
   logic                           make_data_on_edge;
   
   always_ff @(posedge ui_clk)  begin 
      if (ui_clk_sync_rst) begin
         make_data_on_rcom_cdc_to_d   <= 'h0;
         make_data_on_dd 	      <= 'h0;
         make_data_on_ddd 	      <= 'h0;
      end
      else begin
 	      make_data_on_rcom_cdc_to_d   <= make_data_on;
         make_data_on_dd 	           <= make_data_on_rcom_cdc_to_d;
         make_data_on_ddd 	           <= make_data_on_dd;
      end
   end
   
   assign make_data_on_edge 	       = make_data_on_dd & (~make_data_on_ddd);
   assign make_data_p_edge_ddr_clk = make_data_on_edge;
   

   //delay rp_back_en 256 cycle to wait ddr3_mig in idle state .
   logic [7:0]	  rp_back_en_dly_cnt;
   
   always_ff @(posedge ui_clk ) begin
      if (ui_clk_sync_rst) begin
         rp_back_en_dly_cnt  <= 'h0;
      end
      else if (rp_back_en) begin
         rp_back_en_dly_cnt   <= 'h1;
      end
      else if (|rp_back_en_dly_cnt) begin
        rp_back_en_dly_cnt   <= rp_back_en_dly_cnt + 'h1;
      end
   end

   //write requist generate
   logic      ddr_wr_req;
   logic      clr_wr_req;
   logic      wr_burst_cnt_rch;
   logic [8:0] wr_burst_cnt;


   logic [10:0] ddr_wr_fifo_notempty_cnt;
   logic      ddr_wr_fifo_notempty_cnt_rch;

   assign ddr_wr_fifo_notempty_cnt_rch = ddr_wr_fifo_notempty_cnt[10];

   logic      wr_level_low;
   logic      wr_level_high;
   logic      wr_level_urgent;
   logic      wr_level_critical;
   logic      wr_fifo_has_burst;
   logic      rd_level_low;
   logic      rd_level_urgent;
   logic      rd_cache_can_prefetch;

   assign wr_level_low      = ddr_wr_fifo_level >= WR_LEVEL_LOW;
   assign wr_level_high     = ddr_wr_fifo_level >= WR_LEVEL_HIGH;
   assign wr_level_urgent   = ddr_wr_fifo_level >= WR_LEVEL_URGENT;
   assign wr_level_critical = ddr_wr_fifo_level >= WR_LEVEL_CRITICAL;
   assign wr_fifo_has_burst = ~ddr_wr_fifo_prog_empty;

   assign rd_level_urgent   = cache_fifo_almost_empty |
                              (cache_fifo_data_count <= RD_LEVEL_URGENT);
   assign rd_level_low      = cache_fifo_data_count <= RD_LEVEL_LOW;
   assign rd_cache_can_prefetch = (~cache_fifo_prog_full) &
                                  (cache_fifo_data_count < RD_LEVEL_HIGH);
   
   assign ddr_wr_req = (~ddr_wr_fifo_empty) &
                       (wr_level_low | wr_fifo_has_burst |
                        ddr_wr_fifo_notempty_cnt_rch);
   //assign    wr_burst_cnt_rch = wr_burst_cnt[6] ;

   //simulate ddr3 read and write arbitor
   //assign    ddr_wr_req = (ddr_wr_fifo_level > 20) | ddr_wr_fifo_notempty_cnt_rch;
   //assign    wr_burst_cnt_rch = wr_burst_cnt[3] ;
   
   
   always_ff @(posedge ui_clk ) begin
      if (ui_clk_sync_rst) begin
	      ddr_wr_fifo_notempty_cnt 	 <= 'h0;
      end
      else if (clr_wr_req) begin
	      ddr_wr_fifo_notempty_cnt 	 <= 'h0;
      end
      else if (ddr_wr_fifo_empty) begin 
	      ddr_wr_fifo_notempty_cnt 	 <= 'h0;
      end
      else if (~ddr_wr_fifo_notempty_cnt_rch) begin
         ddr_wr_fifo_notempty_cnt   <= ddr_wr_fifo_notempty_cnt + 1'h1;
      end
   end
      
   
  
   
   
   //read and write arbit
   logic             wr_cmd_rdy ;
  
   rw_state_t        rw_state;
   rw_state_t        rw_next_state;
                                   
   logic             ddr_rd_req;
   logic             ddr_rd_empty;
   logic             rd_burst_cnt_rch;

   logic 				remember_write_grant;
   logic 				remember_read_grant;
   logic 				clear_last_grant;
   logic 				last_grant_was_write;
   logic 				last_grant_was_read;
   
    
   always_ff @(posedge ui_clk ) begin
      if (ui_clk_sync_rst) begin
         last_grant_was_write  <= 'h0;
      end
      else if (clear_last_grant) begin
         last_grant_was_write  <= 'h0;
      end
      else if (remember_read_grant) begin
         last_grant_was_write  <= 'h0;
      end
      else if (remember_write_grant) begin
         last_grant_was_write  <= 'h1;
      end
   end

    always_ff @(posedge ui_clk ) begin
      if(ui_clk_sync_rst) begin
         last_grant_was_read  <= 'h0;
      end
      else if (clear_last_grant) begin
         last_grant_was_read  <= 'h0;
      end
      else if (remember_write_grant) begin
         last_grant_was_read  <= 'h0;
      end
      else if (remember_read_grant) begin
         last_grant_was_read  <= 'h1;
      end
   end

   
   
   always_ff @(posedge ui_clk ) begin
      if (ui_clk_sync_rst) begin
         rw_state   <= RW_IDLE;
      end
      else if (rst_local_t_ddr_clk || make_data_on_edge) begin
         rw_state   <= RW_IDLE;
      end
      else begin
         rw_state   <= rw_next_state;
      end
   end


   always_comb begin
      if ((~init_calib_complete) ) begin
         rw_next_state 		   = RW_IDLE;
         remember_write_grant 	= 'h0;
         remember_read_grant 	= 'h0;
         clear_last_grant  	= 'h0;
         clr_wr_req 		      = 'h0;
	 
      end
      else begin
         remember_write_grant 	= 'h0;
         remember_read_grant 	= 'h0;
         clear_last_grant 	   = 'h0;
         clr_wr_req 		      = 'h0;
         case (rw_state)
            RW_IDLE : begin
               if (rp_back_en || (|rp_back_en_dly_cnt)) begin
                  rw_next_state = RW_IDLE;
               end
               else begin
                  rw_next_state 	= RW_ARB_PRE;
               end
               clear_last_grant 	= 'h1;
            end
            RW_ARB_PRE : begin
               if (rp_back_en || (|rp_back_en_dly_cnt)) begin
                  rw_next_state 	    = RW_IDLE;
                  clear_last_grant   = 'h1;
               end
               else if ((wr_level_urgent || wr_level_critical) && ddr_wr_req) begin
                  rw_next_state       = RW_WRITE;
                  clear_last_grant    = 'h1;
               end
               else if (rd_level_urgent && ddr_rd_req && (~wr_level_high)) begin
                  rw_next_state       = RW_READ;
                  clear_last_grant    = 'h1;
               end
               else if (~ddr_wr_fifo_prog_empty) begin
                  rw_next_state 	    = RW_WRITE;
                  clear_last_grant   = 'h1;
               end
               else if (ddr_rd_req && ddr_wr_req) begin
                  rw_next_state      = RW_ARB;
                  clear_last_grant   = 'h0;
               end
               else if (ddr_rd_req) begin
                  rw_next_state      = RW_READ;
                  clear_last_grant   = 'h1;
               end
               else if (ddr_wr_req) begin
                  rw_next_state      = RW_WRITE;
                  clear_last_grant   = 'h1;
               end
               else begin
                  rw_next_state  	 = RW_ARB_PRE;
                  clear_last_grant   = 'h0;
               end
            end
            RW_ARB : begin
               if ((wr_level_high || wr_level_urgent || wr_level_critical) && ddr_wr_req) begin
                  rw_next_state        = RW_WRITE;
                  remember_write_grant  = 'h1;
               end
               else if ((rd_level_low || rd_level_urgent) && ddr_rd_req && (~wr_level_high)) begin
                  rw_next_state        = RW_READ;
                  remember_read_grant  = 'h1;
               end
               else if (ddr_wr_req && (~last_grant_was_write)) begin
                  rw_next_state 	       = RW_WRITE;
                  remember_write_grant   = 'h1;
               end
               else if (ddr_rd_req && (~last_grant_was_read)) begin
                  rw_next_state 	       = RW_READ;
                  remember_read_grant   = 'h1;
               end
               else begin
                  rw_next_state 	       = RW_WRITE;
                  clear_last_grant      = 'h1;
               end
            end
         
            RW_WRITE : begin
               if (wr_burst_cnt_rch || (ddr_wr_fifo_empty)) begin
                  rw_next_state 	 = RW_WRITE_POST;
               end
               else begin
                  rw_next_state 	 = RW_WRITE;
               end
               clr_wr_req 		= 'h1;
            end
            RW_WRITE_POST : begin
               if (wr_cmd_rdy) begin
                  rw_next_state 	 = RW_ARB_PRE;
               end
               else begin
                  rw_next_state 	 = RW_WRITE_POST;
               end
            end
            RW_READ : begin
               if (rd_burst_cnt_rch || wr_level_urgent || wr_level_critical ||
                   req_stop || ddr_rd_empty || rp_back_en || (|rp_back_en_dly_cnt)) begin
                  rw_next_state 	 = RW_ARB_PRE;
               end
               else begin
                  rw_next_state   = RW_READ;
               end
            end
            default : begin
               rw_next_state      = RW_IDLE;
            end
         endcase // case (rw_state)
      end
   end
   

   //write command generate
   
   logic                           fifo_data_rdy;
                                   
   logic                           update_fifo_data_rdy;
                                   
   logic                           wr_cmd_en;
   logic                           wr_cmd_en_valid;
   logic                           wr_burst_cnt_add;
   logic                           wr_sta_wr_cmd_en;
   logic                           wr_post_sta_wr_cmd_en;
   logic                           wr_sta_wr_cmd_en_valid;
   logic                           wr_post_sta_wr_cmd_en_valid;
   
   
   assign wr_cmd_rdy  = app_rdy & app_wdf_rdy;
     
         
  
   assign ddr_wr_fifo_rd_en = (rw_state    == RW_WRITE) & 
                              (~ddr_wr_fifo_empty) & 
                              (~wr_burst_cnt_rch) &
                              wr_cmd_rdy ;
     
   assign update_fifo_data_rdy = wr_cmd_rdy &  (rw_state    == RW_WRITE);
   
   always_ff @(posedge ui_clk ) begin
      if (ui_clk_sync_rst ||  rst_local_t_ddr_clk || make_data_on_edge) begin
         fifo_data_rdy   <= 'h0;
      end
      else if(ddr_wr_fifo_rd_en ) begin
         fifo_data_rdy   <= 'h1;
      end
      else if (wr_cmd_en_valid)begin
         fifo_data_rdy 	 <= 'h0;
      end
   end

   
   assign wr_burst_cnt_rch = wr_burst_cnt >= WR_GRANT_MAX;
   //assign wr_burst_cnt_rch = wr_burst_cnt[4] ;

   assign  wr_burst_cnt_add = ddr_wr_fifo_rd_en;
   
   always_ff @(posedge ui_clk) begin
      if(ui_clk_sync_rst || rst_local_t_ddr_clk || make_data_on_edge) begin
        wr_burst_cnt   <= 'h0;
      end
      else if (rw_state    != RW_WRITE) begin
        wr_burst_cnt   <= 'h0;
      end
      else if (wr_burst_cnt_add) begin
        wr_burst_cnt   <= wr_burst_cnt + 'h1;
      end
   end

    //--------------------calculate write view number ----------------------
  
   logic [15:0] wr_data_cnt;
   logic      wr_data_cnt_lim;
   logic      add_wr_view_cnt;

   assign     wr_data_cnt_lim = (wr_data_cnt == (view_size-1));

   assign     add_wr_view_cnt = wr_burst_cnt_add & wr_data_cnt_lim;
   

   always_ff @(posedge ui_clk) begin
      if(ui_clk_sync_rst || rst_local_t_ddr_clk || make_data_on_edge) begin
         wr_data_cnt  <= 'h0;
      end
      else if( add_wr_view_cnt) begin
	 wr_data_cnt  <= 'h0;
      end
      else if (wr_burst_cnt_add) begin
         wr_data_cnt   <= wr_data_cnt + 'h1;
      end
   end

   logic [16:0] 		   wr_view_num;
  
   always_ff @(posedge ui_clk) begin
      if(ui_clk_sync_rst || rst_local_t_ddr_clk || make_data_on_edge) begin
 	 wr_view_num	       <= 'h0;
      end
      else if (add_wr_view_cnt) begin
        wr_view_num    <= wr_view_num + 'h1;
      end
   end
   
   //--------------------------------------------------------
   
   assign wr_sta_wr_cmd_en         = (rw_state == RW_WRITE) & fifo_data_rdy  & app_wdf_rdy;
   assign wr_post_sta_wr_cmd_en 	  = (rw_state == RW_WRITE_POST) & fifo_data_rdy  & app_wdf_rdy;
   
   assign wr_sta_wr_cmd_en_valid         = (rw_state    == RW_WRITE) & fifo_data_rdy  & wr_cmd_rdy;
   assign wr_post_sta_wr_cmd_en_valid 	  = (rw_state    == RW_WRITE_POST) & fifo_data_rdy  & wr_cmd_rdy;
   

   assign wr_cmd_en       = wr_sta_wr_cmd_en       | wr_post_sta_wr_cmd_en;
   assign wr_cmd_en_valid = wr_sta_wr_cmd_en_valid | wr_post_sta_wr_cmd_en_valid;
   
   assign app_wdf_data = ddr_wr_fifo_dout;
   //assign app_wdf_wren = wr_cmd_en;
   
   
   //read command generate

   logic                           rd_cmd_en;
   logic                           rd_cmd_en_valid;
                                   
   logic [9:0]                     rd_burst_cnt;
   logic                           rd_burst_cnt_add;
                                   
   logic                           qdr_rd_req_d;
   logic                           qdr_rd_req_dd;
   
   
    always_ff @(posedge ui_clk ) begin
      if (ui_clk_sync_rst ||  rst_local_t_ddr_clk) begin
        qdr_rd_req_d    <= 'h0;
        qdr_rd_req_dd   <= 'h0;
      end
      else begin
        qdr_rd_req_d    <= qdr_rd_req;
        qdr_rd_req_dd   <= qdr_rd_req_d;
      end
    end
   /*
   ///////////////////////////////////////////////////////////////////////////
   reg [16:0] 			   rd_view_num;
  
        
   wire [16:0] rd_num_sub_same;
   wire [16:0] rd_num_sub_diff;
   
   assign rd_num_sub_same        = rd_view_num[15:0] - wr_view_num[15:0];
   assign rd_num_sub_diff        = rd_view_num[15:0] - (wr_view_num[15:0] + 'h10000);
   assign rd_num_sub_same_signal = rd_num_sub_same[16];
   assign rd_num_sub_diff_signal = rd_num_sub_diff[16];
   
   
   assign wr_rd_diff_signal = wr_view_num[16] ^ rd_view_num[16] ;
   
   assign rd_num_sub_wr_num = wr_rd_diff_signal ? rd_num_sub_diff_signal : rd_num_sub_same_signal;
    */
   ////////////////////////////////////////////////////////////////
   
   assign ddr_rd_req = (~ddr_rd_empty ) &
                       qdr_rd_req_dd  & 
                       rd_cache_can_prefetch;
   
   assign rd_cmd_en = (rw_state    == RW_READ) &
		      (~rd_burst_cnt_rch) &
                      (~wr_level_urgent) &
                      (~wr_level_critical) &
                      (~ddr_rd_empty );
   
  assign rd_cmd_en_valid = (rw_state    == RW_READ) &  
			   app_rdy &
			   (~rd_burst_cnt_rch) &
			   (~wr_level_urgent) &
			   (~wr_level_critical) &
			   (~ddr_rd_empty );
   
   assign rd_burst_cnt_add = rd_cmd_en_valid;

   logic [9:0] rd_grant_limit;

   assign rd_grant_limit = wr_level_high ? RD_GRANT_WR_HIGH : RD_GRANT_MAX;
   assign rd_burst_cnt_rch = rd_burst_cnt >= rd_grant_limit;
      
   always_ff @(posedge ui_clk) begin
      if(ui_clk_sync_rst || rst_local_t_ddr_clk || make_data_on_edge) begin
        rd_burst_cnt   <= 'h0;
      end
      else if (rw_state    != RW_READ) begin
        rd_burst_cnt   <= 'h0;
      end
      else if (rd_burst_cnt_add) begin
         rd_burst_cnt 	<= rd_burst_cnt + 'h1;
      end
   end

    //--------------------calculate read view number ----------------------

   logic [15:0] rd_data_cnt;
   logic      rd_data_cnt_lim;
   logic      add_rd_view_cnt;

   assign     rd_data_cnt_lim = (rd_data_cnt == (view_size-1));

   assign     add_rd_view_cnt =  rd_cmd_en_valid & rd_data_cnt_lim;
   

   always_ff @(posedge ui_clk) begin
      if(ui_clk_sync_rst || rst_local_t_ddr_clk || make_data_on_edge) begin
         rd_data_cnt  <= 'h0;
      end
      else if( add_rd_view_cnt) begin
	rd_data_cnt   <= 'h0;
      end
      else if (rd_cmd_en_valid) begin
        rd_data_cnt    <= rd_data_cnt + 'h1;
      end
   end

   /*
   always_ff @(posedge ui_clk) begin
      if(ui_clk_sync_rst || rst_local_t_ddr_clk || make_data_on_edge) begin
 	 rd_view_num	       <= 'h0;
      end
      else if (add_rd_view_cnt) begin
        rd_view_num    <= rd_view_num + 'h1;
      end
   end
   */
   
   
   

   //mig user interface
   logic [2:0]                     app_cmd;
   logic [15:0]                    app_wdf_mask;
   logic                           app_ref_req;
   logic                           app_zq_req;
   logic                           app_sr_req;
                                   
   logic                           app_wdf_end;
   logic                           app_wdf_wren;
   
   assign app_en       = rd_cmd_en | wr_cmd_en;
                       
   assign app_cmd      = rd_cmd_en ? 'h1 : 'h0 ;
                       
   assign app_ref_req  = 'h0;
   assign app_zq_req   = 'h0;
   assign app_sr_req   = 'h0;
   
   assign app_wdf_mask = 'h0;

   //assign app_wdf_end = 1'h1;
   
   assign app_wdf_wren = wr_cmd_en_valid;
   assign app_wdf_end  = wr_cmd_en_valid;
   
   
   //
   
   logic [127:0]                   qdr_dataout;
   logic                           qdr_dataout_en;
      
   assign   qdr_dataout = app_rd_data;
   assign   qdr_dataout_en = app_rd_data_valid;
   
   logic [ADDR_WIDTH   :0] user_ad_wr_i;
   logic [ADDR_WIDTH-1 :0] user_ad_wr;

   assign        user_ad_wr = user_ad_wr_i[ADDR_WIDTH-1 :0];
   
   
   always_ff @(posedge ui_clk ) begin 
      if (ui_clk_sync_rst || rst_local_t_ddr_clk || make_data_on_edge) begin
         user_ad_wr_i   <= 'h0;
      end
      else if(wr_cmd_en_valid) begin
         user_ad_wr_i <= user_ad_wr_i + 1;
      end
   end
   
   //recoder the bandary of the view
   logic [ADDR_WIDTH :0]          user_ad_rd_i;
   logic [ADDR_WIDTH-1:0]         user_ad_rd ;

  
   
   //read address generator 
  
   
   assign      user_ad_rd = user_ad_rd_i[ADDR_WIDTH-1:0];

  
   always_ff @(posedge ui_clk ) begin 
      if (ui_clk_sync_rst || rst_local_t_ddr_clk || make_data_on_edge) begin
         user_ad_rd_i    <= 'h0;
      end
      else if (rp_back_en) begin
         user_ad_rd_i    <= rp_back_view_addr ;
      end
      else if(rd_cmd_en_valid) begin
         user_ad_rd_i    <= user_ad_rd_i + 1;
      end
   end

   logic                           ddr_rd_empty_i;
   
   assign ddr_rd_empty_i =  (user_ad_wr_i   == user_ad_rd_i);
   
     
   
   assign  ddr_rd_empty = ddr_rd_empty_i;
   
   
   assign app_addr =  wr_cmd_en ? {user_ad_wr,3'h0} : {user_ad_rd,3'h0};
   
 	  
       
   
  //----------------------------------
  //--     qdr overrun generator    --
  //----------------------------------
  
  //-- write address is larger read address more than the whole QDRII+ space(less one reading), --almost full 
  //-- or read address is larger write address only one reading space.-- overwrite will be occur

   logic [ADDR_WIDTH :0]          wr_sub_rd;
   logic [ADDR_WIDTH :0]          wr_sub_rd_diff;
   logic                          wr_rd_same_signal;
   logic                          wr_rd_diff_signal;
   logic                          set_ddr_overrun;
   
   
   //((32 + 680/4 * 64)*2)

   assign wr_rd_same_signal = (user_ad_wr_i[ADDR_WIDTH] == user_ad_rd_i[ADDR_WIDTH]);
   assign wr_rd_diff_signal = (user_ad_wr_i[ADDR_WIDTH] ^ user_ad_rd_i[ADDR_WIDTH]);
   
   assign set_ddr_overrun =  wr_rd_diff_signal &
			    (user_ad_wr_i[ADDR_WIDTH-1:0] == user_ad_rd_i[ADDR_WIDTH-1:0]);
   
   logic ddr_overrun;
      
   always_ff @(posedge ui_clk ) begin 
      if (ui_clk_sync_rst) begin
         ddr_overrun   <= 'h0;
      end
      else if(rst_local_t_ddr_clk || (~init_calib_complete)) begin
         ddr_overrun   <= 'h0;
      end
      else if (make_data_on_edge) begin
         ddr_overrun   <= 'h0;
      end
      else if (fault_ddr_overrun) begin
         ddr_overrun   <= 'h1;
      end
      else if (set_ddr_overrun) begin
         ddr_overrun   <= 'h1;
      end
      else begin 
         ddr_overrun   <= 'h0;
      end
   end
   
   assign  wr_sub_rd       = {1'h0,user_ad_wr_i[ADDR_WIDTH-1:0]} -  {1'h0,user_ad_rd_i[ADDR_WIDTH-1:0]};
   assign  wr_sub_rd_diff  = {1'h1,user_ad_wr_i[ADDR_WIDTH-1:0]} -  {1'h0,user_ad_rd_i[ADDR_WIDTH-1:0]};
   
   logic ddr_warning;
  
   always_ff @(posedge ui_clk ) begin 
      if (ui_clk_sync_rst) begin
         ddr_warning  <= 'h0;
      end
      else if (rst_local_t_ddr_clk || (~init_calib_complete)) begin
         ddr_warning  <= 'h0;
      end
      else if (make_data_on_edge) begin
         ddr_warning  <= 'h0;
      end
      else if (fault_ddr_warning) begin
         ddr_warning  <= 'h1;
      end
      else if (wr_rd_same_signal && (|wr_sub_rd[ADDR_WIDTH : ADDR_WIDTH-2] )) begin //write address is large than read address, and left half memory
         ddr_warning  <= 'h1;
      end
      else if (wr_rd_diff_signal && (|wr_sub_rd_diff[ADDR_WIDTH : ADDR_WIDTH-2])) begin  //write address is less than read address,and left half memory
         ddr_warning  <= 'h1;
      end
      else  begin
         ddr_warning  <= 'h0;
      end
   end
   

  (* ASYNC_REG = "true" *) logic  wr_fifo_overrun_d;
  (* ASYNC_REG = "true" *) logic  wr_fifo_overrun_dd;
   
   
   always_ff @(posedge ui_clk)  begin
      wr_fifo_overrun_d    <= wr_fifo_overrun;
      wr_fifo_overrun_dd   <= wr_fifo_overrun_d;
   end

   
      

endmodule // user_rw_cmd_gen



