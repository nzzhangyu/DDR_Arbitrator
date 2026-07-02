`timescale 1ns/1ps

module cross_clk_pulse(/*AUTOARG*/
   // Outputs
   o,
   // Inputs
   i, i_clk, i_rst, o_clk, o_rst
   );

   parameter  PULSE_WIDTH = 'h8;

   input i;
   input i_clk;
   input i_rst;

   input o_clk;
   input o_rst;

   output o;

   reg       i_latch;
   reg       i_d;

   wire      i_latch_cnt_rch;

   reg [3:0] i_latch_cnt;

   ////////////////////////input pulse to PULSE_WIDTH cycle  /////////////////////////

   always @(posedge i_clk ) begin
      i_d       <= i;
   end

   assign i_pose_edge = i & (~i_d);

   always @(posedge i_clk ) begin
      if(i_rst) begin
         i_latch <= 'h0;
      end
      else if(i_pose_edge) begin
         i_latch   <= 'h1;
      end
      else if (i_latch_cnt_rch) begin
         i_latch   <= 'h0;
      end
   end

   assign i_latch_cnt_rch = (PULSE_WIDTH == i_latch_cnt);


   always @(posedge i_clk ) begin
      if(i_rst) begin
         i_latch_cnt <= 'h0;
      end
      else if (i_latch_cnt_rch) begin
         i_latch_cnt <= 'h0;
      end
      else if(i_latch) begin
         i_latch_cnt <= i_latch_cnt + 'h1;
      end
   end

   ////////////////////////output pulse generate /////////////////////////

   (* ASYNC_REG = "true" *)reg i_latch_rcom_cdc_to_d;
   (* ASYNC_REG = "true" *)reg i_latch_dd;
   (* ASYNC_REG = "true" *)reg i_latch_ddd;

    always @(posedge o_clk ) begin
      if(o_rst) begin
         i_latch_rcom_cdc_to_d    <= 'h0;
         i_latch_dd               <= 'h0;
         i_latch_ddd              <= 'h0;
      end
      else  begin
         i_latch_rcom_cdc_to_d    <= i_latch;
         i_latch_dd               <= i_latch_rcom_cdc_to_d;
         i_latch_ddd              <= i_latch_dd;
      end
   end



   reg [2:0] p_state;
   reg [2:0] p_state_next;

   parameter IDLE = 0;
   parameter WAIT_HIGH = 3'h1;
   parameter HIGH_STA  = 3'h2;
   parameter WAIT_CHG  = 3'h3;
   parameter WAIT_LOW  = 3'h4;
   parameter LOW_STA   = 3'h5;



   always @(posedge o_clk ) begin
      if(o_rst) begin
         p_state   <= IDLE;
      end
      else begin
         p_state   <= p_state_next;
      end
   end

   always @(/*AS*/i_latch_dd or p_state) begin
      begin
         p_state_next    = p_state;
      end
      case (p_state)
        IDLE :
          if (i_latch_dd) begin
           p_state_next    = WAIT_HIGH;
          end
        WAIT_HIGH :
          if (i_latch_dd) begin
           p_state_next    = HIGH_STA;
          end
          else  begin
             p_state_next    = IDLE;
          end
        HIGH_STA :
          begin
             p_state_next        = WAIT_CHG;
          end
        WAIT_CHG :
          if (~i_latch_dd ) begin
             p_state_next    = WAIT_LOW;
          end
        WAIT_LOW :
          if (~i_latch_dd ) begin
             p_state_next    = LOW_STA;
          end
          else  begin
             p_state_next    = WAIT_CHG;
          end
        LOW_STA :
          begin
           p_state_next    = IDLE;
          end
        default :
          begin
             p_state_next    = IDLE;
          end
      endcase
   end // always @ (...


   assign o = p_state == HIGH_STA;


endmodule // cross_clk_pulse
