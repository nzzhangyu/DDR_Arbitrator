//--------------------------------------------------------------------------------
// Company: Neusoft Medical Systems
// Engineer: 
// 
// Create Date:     29/6/2020 
// Design Name:    
// Module Name:    aurora_tx_frame 
// Project Name:   H72
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
module  commok_check(/*AUTOARG*/
   // Outputs
   rp_back_en_rst, rp_back_en, rp_back_en_i, rp_back_cnt_add_en,
   view_trans_ok, refresh_process_en, uiclk_pulse_1us,
   // Inputs
   ui_clk, ddr_user_rst, rst_local_t_ddr_clk, clk_40mhz_1us_in,
   comm_ok_disable, comm_ok, idle_process_en, ui_clk_rd_view_pulse,
   sample_frame_rd_done
   );
   
   parameter                       ADDR_WIDTH = 24; //2g
  
   input             ui_clk;                  // GTP clock  
   input             ddr_user_rst;              //
   input             rst_local_t_ddr_clk;
   

   input             clk_40mhz_1us_in;                // 40Mhz clock      
   
   //input           make_data_on;
   input             comm_ok_disable;
   input             comm_ok;

   input             idle_process_en;
   input             ui_clk_rd_view_pulse;
   input             sample_frame_rd_done;
   
     
   output            rp_back_en_rst;    //to aurora_tx_frame.v
   output            rp_back_en;        //  to  user_rw_cmd_gen.v 
   output            rp_back_en_i;        //  to  user_rw_cmd_gen.v 
   output            rp_back_cnt_add_en;        //  to  user_rw_cmd_gen.v 
   //output [1:0]          rp_back_num;
   output            view_trans_ok;
   
   output            refresh_process_en;

   output            uiclk_pulse_1us;
   
   
   assign            rst_local = rst_local_t_ddr_clk | ddr_user_rst;

   
   assign            rd_view_pulse = (  idle_process_en  & ui_clk_rd_view_pulse) | 
                     ((~idle_process_en) & sample_frame_rd_done);

   reg               idle_process_en_d;

  
     
   always @(posedge ui_clk) begin 
         idle_process_en_d  <= idle_process_en;
   end

   assign idle_process_en_fall_edge = (~idle_process_en) & idle_process_en_d;
   
  
    //---------------calculate view size of 128 bits in DDR3 SDRAM ----------
   /*
   reg [9:0] cal_cnt;
      
   reg [11:0] view_size_acc;
   reg [11:0] view_size;
   
   wire       cal_view_size_fsh;
   reg         cal_view_size_fsh_d;
   
   assign     cal_view_size_fsh = cal_cnt[9];
   
   always @(posedge ui_clk) begin
      if(rst_local) begin
    cal_cnt   <= 'h0;
      end
      else if (make_data_on_r_edge) begin
    cal_cnt   <= 'h0;
      end
      else if (~cal_view_size_fsh) begin
    cal_cnt   <= cal_cnt + 1'h1;
      end
   end

   always @(posedge ui_clk) begin
      if(rst_local) begin
    cal_view_size_fsh_d   <= 'h0;
      end
      else begin
    cal_view_size_fsh_d   <= cal_view_size_fsh;
      end
   end

   assign update_view_size = cal_view_size_fsh & (~cal_view_size_fsh_d);
   
   
   reg view_size_acc_add_en;

   always @(posedge ui_clk) begin
      if(rst_local) begin
    view_size_acc_add_en   <= 'h0;
      end
      else if (make_data_on_r_edge) begin
    view_size_acc_add_en   <= 'h1;
      end
      else if (cal_cnt[8:0] == slice_sel-1) begin
    view_size_acc_add_en   <= 'h0;
      end
   end
   
   always @(posedge ui_clk) begin
      if(rst_local) begin
    view_size_acc   <= 'h0;
      end
      else if (make_data_on_r_edge) begin
    view_size_acc   <= 'h11;   //17 * 128bits 
      end
      else if (view_size_acc_add_en) begin
    //view_size_acc   <= view_size_acc + 'h5a;  //90 * 128 bits
    view_size_acc   <= view_size_acc + (SLICE_DATA_NUM/8+2);  //112 * 128 bits 
      end
   end
   
    always @(posedge ui_clk) begin
       if(rst_local) begin
     view_size   <= 'h5b1;
       end
       else if (update_view_size) begin
     view_size   <= view_size_acc;
       end
    end

   */
   //-------------------communication state ---------------------------

   (* ASYNC_REG = "true" *)reg     comm_ok_d;
   (* ASYNC_REG = "true" *)reg     comm_ok_dd;
   (* ASYNC_REG = "true" *)reg     comm_ok_ddd;
   
   always @(posedge ui_clk) begin
      if(rst_local) begin
         comm_ok_d     <= 'h0;
         comm_ok_dd    <= 'h0;
         comm_ok_ddd   <= 'h0;
      end
      else begin
         comm_ok_d     <= comm_ok;
         comm_ok_dd    <= comm_ok_d;
         comm_ok_ddd   <= comm_ok_dd;
      end
   end

   assign comm_ok_edge = comm_ok_ddd ^ comm_ok_dd;
      
   reg [1:0]             comm_state;
   reg [1:0]             comm_next_state;
   parameter             IDLE = 0;
   parameter             WAIT_COMM_OK_STA = 1;
   parameter             REFRESH_STA1 =2 ;
   parameter             REFRESH_STA2 = 3;

   
   always @(posedge ui_clk) begin
      if(rst_local) begin
         comm_state   <= IDLE;
      end
      else begin
         comm_state   <= comm_next_state;
      end
   end

   (* ASYNC_REG = "true" *)reg  pulse_1us_in_d;
   (* ASYNC_REG = "true" *)reg  pulse_1us_in_dd;
   (* ASYNC_REG = "true" *)reg  pulse_1us_in_ddd;
   wire pulse_1us;
   
   assign uiclk_pulse_1us = pulse_1us;
   

   always @(posedge ui_clk) begin
      pulse_1us_in_d     <= clk_40mhz_1us_in;
      pulse_1us_in_dd    <= pulse_1us_in_d;
      pulse_1us_in_ddd   <= pulse_1us_in_dd;
   end

   assign pulse_1us = pulse_1us_in_dd & (~pulse_1us_in_ddd);
   
   reg [11:0] time_out_cnt;
   
   always @(posedge ui_clk) begin
      if(rst_local) begin
         time_out_cnt   <= 'h0;
      end
      else if (comm_state != WAIT_COMM_OK_STA) begin
         time_out_cnt   <= 'h0;
      end
      else if (~(&time_out_cnt) && pulse_1us) begin 
         time_out_cnt   <= time_out_cnt+ 'h1;
      end
   end

   assign comm_ok_timeout = ('d1500 == time_out_cnt);
   

   (* ASYNC_REG = "true" *)reg     comm_ok_disable_d;
   (* ASYNC_REG = "true" *)reg     comm_ok_disable_dd;

   always @(posedge ui_clk) begin
      comm_ok_disable_d    <= comm_ok_disable;
      comm_ok_disable_dd   <= comm_ok_disable_d;
   end

   reg [7:0] commok_wait_cnt;

   assign    commok_disable_trig = pulse_1us & (commok_wait_cnt == 'd49);
   
   always @(posedge ui_clk) begin
      if(rst_local) begin
         commok_wait_cnt   <= 'h0;
      end
      else if ( (comm_state != WAIT_COMM_OK_STA) || (~comm_ok_disable_dd)) begin
         commok_wait_cnt   <= 'h0;
      end
      else if ( (comm_state == WAIT_COMM_OK_STA) && commok_disable_trig ) begin
         commok_wait_cnt   <= 'h0;
      end
      else if ( (comm_state == WAIT_COMM_OK_STA) && pulse_1us ) begin
         commok_wait_cnt   <= commok_wait_cnt + 1'h1;
      end
   end
         
   
   reg  rp_back_en_t;
   
   
   always @(/*AS*/comm_ok_disable_dd or comm_ok_edge
       or comm_ok_timeout or comm_state or commok_disable_trig
       or idle_process_en_fall_edge or rd_view_pulse) begin
      begin
    comm_next_state = comm_state;
    rp_back_en_t   = 'h0;
      end
      case (comm_state)
         IDLE : begin
            if(rd_view_pulse) begin
               comm_next_state    = WAIT_COMM_OK_STA;
            end
         end
         WAIT_COMM_OK_STA : begin 
            if( idle_process_en_fall_edge) begin
               comm_next_state    = IDLE;
            end
            else if ((~comm_ok_disable_dd) && comm_ok_edge && rd_view_pulse) begin
               comm_next_state   = WAIT_COMM_OK_STA;
            end
            else if (comm_ok_disable_dd && commok_disable_trig && rd_view_pulse) begin
               comm_next_state   = WAIT_COMM_OK_STA;
            end
            else if (((~comm_ok_disable_dd) && comm_ok_edge) || (comm_ok_disable_dd && commok_disable_trig))  begin
               comm_next_state   = IDLE;
            end
            else if (rd_view_pulse) begin 
               comm_next_state   = REFRESH_STA1;
               rp_back_en_t      = 'h1;
            end
            else if (comm_ok_timeout)begin 
               comm_next_state   = REFRESH_STA1;
               rp_back_en_t      = 'h1;
            end
         end
         REFRESH_STA1: begin
            if(comm_ok_edge || comm_ok_disable_dd) begin
               comm_next_state = REFRESH_STA2;
         end
         end
         REFRESH_STA2: begin
            if(comm_ok_edge || comm_ok_disable_dd) begin
               comm_next_state = IDLE;
         end
         end
         default : begin
            comm_next_state    = IDLE;
         end
      endcase // case (comm_state)
   end

   wire refresh_process_en_t;
   
   reg  refresh_process_en;

   assign refresh_process_en_t = (comm_state == REFRESH_STA1 ) | 
            (comm_state == REFRESH_STA2 );
      
   always @(posedge ui_clk) begin
      if(rst_local) begin
         refresh_process_en  <= 'h0;
      end
      else begin
         refresh_process_en  <= refresh_process_en_t;
      end
   end

   reg  rp_back_en_i; 
   reg  rp_back_en; //delay a cycle 
   reg  rp_back_cnt_add_en;
   
   assign rp_back_en_temp = rp_back_en_t & (~idle_process_en);
   
   always @(posedge ui_clk) begin
      if(rst_local) begin
         rp_back_en_i <= 'h0;
         rp_back_en   <= 'h0;
      end
      else begin
         rp_back_en_i <= rp_back_en_temp;
         rp_back_en   <= rp_back_en_i;
      end
   end

   always @(posedge ui_clk) begin
      if(rst_local) begin
         rp_back_cnt_add_en   <= 'h0;
      end
      else begin
         rp_back_cnt_add_en    <= rp_back_en_t;
      end
   end
   
   
   assign view_trans_ok = (comm_state == WAIT_COMM_OK_STA) & 
              (((~comm_ok_disable_dd) & comm_ok_edge) | (comm_ok_disable_dd & commok_disable_trig) );
   
 
 
      //------------------rp_back reset the aurora_tx_frame module  -------------------------

   wire   rp_back_en_rst;

   wire   rp_back_en_trig;

   assign rp_back_en_trig = rp_back_en_t;
   
   //delay rp_back_en 256 cycle to wait ddr3_mig in idle state .
   reg [7:0]     rp_back_en_dly_cnt;
   
   always @(posedge ui_clk ) begin
      if(ddr_user_rst) begin
         rp_back_en_dly_cnt   <= 'h0;
      end
      else if (rst_local_t_ddr_clk ) begin 
         rp_back_en_dly_cnt   <= 'h0;
      end
      else if (rp_back_en_trig) begin
         rp_back_en_dly_cnt   <= 'h1;
      end
      else if(|rp_back_en_dly_cnt) begin
         rp_back_en_dly_cnt   <= rp_back_en_dly_cnt + 'h1;
      end
   end

   reg rp_back_en_extend_uiclk;
   

   always @(posedge ui_clk ) begin
      if(ddr_user_rst) begin
         rp_back_en_extend_uiclk <= 'h0;
      end
      else if (rst_local_t_ddr_clk ) begin 
         rp_back_en_extend_uiclk <= 'h0;
      end
      else if (rp_back_en_trig) begin
        rp_back_en_extend_uiclk  <= 'h1;
      end
      else if(&rp_back_en_dly_cnt) begin
         rp_back_en_extend_uiclk <= 'h0;
      end
   end

 

   assign rp_back_en_rst = rp_back_en_extend_uiclk;
   

 

endmodule // commok_check
