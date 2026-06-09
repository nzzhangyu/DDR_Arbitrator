//--------------------------------------------------------------------------------
// Company: Neusoft Medical Systems
// Module Name: idle_frame_gen
// Description: Generate idle frame data, idle payload pattern, and CRC words.
//--------------------------------------------------------------------------------

`include "h80_define.sv"
`timescale 1ns/1ps

module idle_frame_gen (
    input  logic        aurora_sw_rst,
    input  logic        rst_local,
    input  logic        gtx_user_clk_in,

    input  logic        idle_process_en,
    input  logic        conv,

    input  logic [7:0]  DMS_Type,
    input  logic [15:0] L_FTP_temp,
    input  logic [15:0] R_FTP_temp,

    input  logic        idle_frame_ind,
    input  logic [7:0]  header_cnt,
    input  logic [7:0]  slice_cnt,
    input  logic        header_en,
    input  logic        idle_slice_data_en,
    input  logic        header_cmd_1_en,
    input  logic        header_cmd_2_en,
    input  logic        footer_en,
    input  logic        slice_cmd_1_en,
    input  logic        slice_cmd_2_en,
    input  logic        crc_tx_1_en,
    input  logic        crc_tx_2_en,
    input  logic        clear_crc,
    input  logic        crc_en,
    input  logic        gtx_refresh_process_en,

    output logic        idle_process_active_out,
    output logic        idle_process_active_debug_out,
    output logic        idle_header_ctl_word_en_out,
    output logic        idle_slice_trans_start,
    output logic        idle_trig,
    output logic [63:0] idle_data_out
);

    localparam logic [63:0] H_FRAME_HEADER_DATA = 64'h04331000_00002100;
    localparam logic [63:0] FOOTER_DATA         = 64'hFACEEACE_CACEBACE;

    logic [15:0] idle_head_005_r;
    logic [15:0] idle_head_006_r;

    logic        conv_d;
    logic        conv_dd;
    logic        conv_ddd;
    logic        conv_edge_pulse;

    logic        idle_process_en_i;
    logic        idle_process_active;
    logic        idle_process_active_debug_i;
    logic        gtx_refresh_process_en_active;
    logic        refresh_process_en;

    logic [11:0] idle_counter;
    logic        idle_counter_lim;
    logic        idle_trig_t;

    logic [11:0] all_slice_number;
    logic [63:0] s_frame_header_data;
    logic [63:0] header_data;
    logic [63:0] idle_data_out_t;

    logic [15:0] data_lfsr_r;
    logic [15:0] data_lfsr_r_t;
    logic        data_lfst_fb;
    logic        idle_data_gen_en;

    logic [15:0] crc_0_in;
    logic [15:0] crc_1_in;
    logic [15:0] crc_2_in;
    logic [15:0] crc_3_in;
    logic [15:0] crc_0_out;
    logic [15:0] crc_1_out;
    logic [15:0] crc_2_out;
    logic [15:0] crc_3_out;
    logic [63:0] crc_out;
    logic        crc_clear;

    assign idle_header_ctl_word_en_out = idle_trig;
    assign idle_process_en_i           = idle_process_en;
    assign idle_counter_lim            = idle_counter[11];
    assign idle_trig_t                 = idle_counter == 12'h258;

    assign all_slice_number            = slice_cnt;
    assign s_frame_header_data         = {20'h04330, all_slice_number, 32'h0000db00};
    assign idle_data_out_t             = {data_lfsr_r, data_lfsr_r, data_lfsr_r, data_lfsr_r};

    assign idle_data_gen_en            = idle_slice_data_en;
    assign data_lfst_fb                = (~(data_lfsr_r[12] ^ data_lfsr_r[3] ^ data_lfsr_r[1])) ^ data_lfsr_r[0];
    assign data_lfsr_r_t               = {data_lfst_fb, data_lfsr_r[15:1]};

    assign crc_0_in                    = idle_data_out[15:0];
    assign crc_1_in                    = idle_data_out[31:16];
    assign crc_2_in                    = idle_data_out[47:32];
    assign crc_3_in                    = idle_data_out[63:48];
    assign crc_out                     = {crc_3_out, crc_2_out, crc_1_out, crc_0_out};
    assign crc_clear                   = clear_crc;

    function automatic logic [15:0] idle_header_word(input logic [7:0] word_idx);
        case (word_idx)
            8'd0:    idle_header_word = {DMS_Type, 8'h01};
            8'd1:    idle_header_word = 16'h0000;
            8'd2:    idle_header_word = 16'h0010;
            8'd3:    idle_header_word = 16'h0011;
            8'd4:    idle_header_word = 16'h0100;
            8'd5:    idle_header_word = idle_head_005_r;
            8'd6:    idle_header_word = idle_head_006_r;
            8'd7:    idle_header_word = 16'h0111;
            8'd8:    idle_header_word = 16'hFACE;
            8'd9:    idle_header_word = 16'h1001;
            8'd10:   idle_header_word = 16'h1010;
            8'd11:   idle_header_word = 16'h1011;
            8'd12:   idle_header_word = 16'h1100;
            8'd13:   idle_header_word = 16'h1101;
            8'd14:   idle_header_word = 16'h1110;
            8'd15:   idle_header_word = 16'h1111;
            8'd16:   idle_header_word = 16'hFACE;
            8'd17:   idle_header_word = 16'h2001;
            8'd18:   idle_header_word = 16'h2010;
            8'd19:   idle_header_word = 16'h2011;
            8'd20:   idle_header_word = 16'h2100;
            8'd21:   idle_header_word = 16'h2101;
            8'd22:   idle_header_word = 16'h2110;
            8'd23:   idle_header_word = 16'h2111;
            8'd24:   idle_header_word = 16'hFACE;
            8'd25:   idle_header_word = 16'h3001;
            8'd26:   idle_header_word = 16'h3010;
            8'd27:   idle_header_word = 16'h3011;
            8'd28:   idle_header_word = 16'h3100;
            8'd29:   idle_header_word = 16'h3101;
            8'd30:   idle_header_word = 16'h3110;
            8'd31:   idle_header_word = 16'h0020;
            8'd32:   idle_header_word = 16'hFACE;
            8'd33:   idle_header_word = 16'h4001;
            8'd34:   idle_header_word = 16'h4010;
            8'd35:   idle_header_word = 16'h4011;
            8'd36:   idle_header_word = 16'h4100;
            8'd37:   idle_header_word = 16'h4101;
            8'd38:   idle_header_word = 16'h4110;
            8'd39:   idle_header_word = 16'h4111;
            8'd40:   idle_header_word = 16'hFACE;
            8'd41:   idle_header_word = 16'h5001;
            8'd42:   idle_header_word = 16'h5010;
            8'd43:   idle_header_word = 16'h5011;
            8'd44:   idle_header_word = 16'h5100;
            8'd45:   idle_header_word = 16'h5101;
            8'd46:   idle_header_word = 16'h5110;
            8'd47:   idle_header_word = 16'h5111;
            8'd48:   idle_header_word = 16'hFACE;
            8'd49:   idle_header_word = 16'h6001;
            8'd50:   idle_header_word = 16'h6010;
            8'd51:   idle_header_word = 16'h6011;
            8'd52:   idle_header_word = 16'h6100;
            8'd53:   idle_header_word = 16'h6101;
            8'd54:   idle_header_word = 16'h6110;
            8'd55:   idle_header_word = 16'h6111;
            8'd56:   idle_header_word = 16'hFACE;
            8'd57:   idle_header_word = 16'h7001;
            8'd58:   idle_header_word = 16'h7010;
            8'd59:   idle_header_word = 16'h7111;
            8'd60:   idle_header_word = 16'h7100;
            8'd61:   idle_header_word = 16'h7101;
            8'd62:   idle_header_word = 16'h7110;
            8'd63:   idle_header_word = 16'h7011;
            8'd64:   idle_header_word = 16'hFACE;
            8'd65:   idle_header_word = 16'h8001;
            8'd66:   idle_header_word = 16'h8010;
            8'd67:   idle_header_word = 16'h8011;
            8'd68:   idle_header_word = 16'h8100;
            8'd69:   idle_header_word = 16'h8101;
            8'd70:   idle_header_word = 16'h8110;
            8'd71:   idle_header_word = 16'h8111;
            8'd72:   idle_header_word = 16'hFACE;
            8'd73:   idle_header_word = 16'h9001;
            8'd74:   idle_header_word = 16'h9010;
            8'd75:   idle_header_word = 16'h9011;
            8'd76:   idle_header_word = 16'h9100;
            8'd77:   idle_header_word = 16'h9101;
            8'd78:   idle_header_word = 16'h9110;
            8'd79:   idle_header_word = 16'h9111;
            8'd80:   idle_header_word = 16'hFACE;
            8'd81:   idle_header_word = 16'hA001;
            8'd82:   idle_header_word = 16'hA010;
            8'd83:   idle_header_word = 16'hA011;
            8'd84:   idle_header_word = 16'hA100;
            8'd85:   idle_header_word = 16'hA101;
            8'd86:   idle_header_word = 16'hA110;
            8'd87:   idle_header_word = 16'hA111;
            8'd88:   idle_header_word = 16'hFACE;
            8'd89:   idle_header_word = 16'hB001;
            8'd90:   idle_header_word = 16'hB010;
            8'd91:   idle_header_word = 16'hB011;
            8'd92:   idle_header_word = 16'hB100;
            8'd93:   idle_header_word = 16'hB101;
            8'd94:   idle_header_word = 16'hB110;
            8'd95:   idle_header_word = 16'hB111;
            8'd96:   idle_header_word = 16'hFACE;
            8'd97:   idle_header_word = 16'hC001;
            8'd98:   idle_header_word = 16'hC010;
            8'd99:   idle_header_word = 16'hC011;
            8'd100:  idle_header_word = 16'hC100;
            8'd101:  idle_header_word = 16'hC101;
            8'd102:  idle_header_word = 16'hC110;
            8'd103:  idle_header_word = 16'hC111;
            8'd104:  idle_header_word = 16'hFACE;
            8'd105:  idle_header_word = 16'hD001;
            8'd106:  idle_header_word = 16'hD010;
            8'd107:  idle_header_word = 16'hD011;
            8'd108:  idle_header_word = 16'hD100;
            8'd109:  idle_header_word = 16'hD101;
            8'd110:  idle_header_word = 16'hD110;
            8'd111:  idle_header_word = 16'hD111;
            8'd112:  idle_header_word = 16'hFACE;
            8'd113:  idle_header_word = 16'hE001;
            8'd114:  idle_header_word = 16'hE010;
            8'd115:  idle_header_word = 16'hE011;
            8'd116:  idle_header_word = 16'hE100;
            8'd117:  idle_header_word = 16'hE101;
            8'd118:  idle_header_word = 16'hE110;
            8'd119:  idle_header_word = 16'hE111;
            8'd120:  idle_header_word = 16'hFACE;
            8'd121:  idle_header_word = 16'hF001;
            8'd122:  idle_header_word = 16'hF010;
            8'd123:  idle_header_word = 16'hF011;
            8'd124:  idle_header_word = 16'hF100;
            8'd125:  idle_header_word = 16'hF101;
            8'd126:  idle_header_word = 16'hFACE;
            8'd127:  idle_header_word = 16'hF111;
            default: idle_header_word = 16'h0000;
        endcase
    endfunction

    always_ff @(posedge gtx_user_clk_in) begin
        conv_d   <= conv;
        conv_dd  <= conv_d;
        conv_ddd <= conv_dd;
    end

    assign conv_edge_pulse = conv_dd ^ conv_ddd;

    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst || rst_local) begin
            idle_head_005_r <= 16'h0000;
            idle_head_006_r <= 16'h0000;
        end
        else begin
            idle_head_005_r <= L_FTP_temp;
            idle_head_006_r <= R_FTP_temp;
        end
    end

    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            idle_process_active <= 1'b0;
        end
        else if (rst_local) begin
            idle_process_active <= 1'b0;
        end
        else if (idle_process_en_i && conv_edge_pulse) begin
            idle_process_active <= 1'b1;
        end
        else if ((~idle_process_en_i) && conv_edge_pulse) begin
            idle_process_active <= 1'b0;
        end
    end

    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            gtx_refresh_process_en_active <= 1'b0;
        end
        else if (gtx_refresh_process_en) begin
            gtx_refresh_process_en_active <= 1'b1;
        end
        else if ((~gtx_refresh_process_en) && conv_edge_pulse) begin
            gtx_refresh_process_en_active <= 1'b0;
        end
    end

    assign refresh_process_en = gtx_refresh_process_en | gtx_refresh_process_en_active;

    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            idle_process_active_out <= 1'b0;
        end
        else begin
            idle_process_active_out <= idle_process_active;
        end
    end

    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst) begin
            idle_process_active_debug_i   <= 1'b0;
            idle_process_active_debug_out <= 1'b0;
        end
        else begin
            idle_process_active_debug_i   <= idle_process_active;
            idle_process_active_debug_out <= idle_process_active_debug_i;
        end
    end

    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst || rst_local) begin
            idle_counter <= 12'h000;
        end
        else if (refresh_process_en) begin
            idle_counter <= 12'h000;
        end
        else if (idle_process_en_i && conv_edge_pulse) begin
            idle_counter <= 12'h000;
        end
        else if ((~idle_counter_lim) && idle_process_active) begin
            idle_counter <= idle_counter + 12'h001;
        end
    end

    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst || rst_local) begin
            idle_trig <= 1'b0;
        end
        else begin
            idle_trig <= idle_trig_t;
        end
    end

    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst || rst_local) begin
            idle_slice_trans_start <= 1'b0;
        end
        else if (idle_trig_t) begin
            idle_slice_trans_start <= 1'b0;
        end
        else if (idle_counter == 12'h1e0) begin
            idle_slice_trans_start <= 1'b1;
        end
    end

    always_comb begin
        if (header_cnt <= 8'd30) begin
            header_data = {
                idle_header_word({header_cnt, 2'b11}),
                idle_header_word({header_cnt, 2'b10}),
                idle_header_word({header_cnt, 2'b01}),
                idle_header_word({header_cnt, 2'b00})
            };
        end
        else begin
            header_data = 64'h0000_0000_0000_0000;
        end
    end

    always_comb begin
        if (crc_tx_2_en) begin
            idle_data_out = crc_out;
        end
        else if (header_cmd_2_en) begin
            idle_data_out = H_FRAME_HEADER_DATA;
        end
        else if (slice_cmd_2_en) begin
            idle_data_out = s_frame_header_data;
        end
        else if (header_en) begin
            idle_data_out = header_data;
        end
        else if (footer_en) begin
            idle_data_out = FOOTER_DATA;
        end
        else begin
            idle_data_out = idle_data_out_t;
        end
    end

    always_ff @(posedge gtx_user_clk_in) begin
        if (aurora_sw_rst || rst_local) begin
            data_lfsr_r <= 16'hABCD;
        end
        else if (idle_trig) begin
            data_lfsr_r <= 16'hABCD;
        end
        else if (idle_data_gen_en) begin
            data_lfsr_r <= data_lfsr_r_t;
        end
    end

    CRC_16_header_data CRC_0_uut (
        .Clk       (gtx_user_clk_in),
        .Reset     (aurora_sw_rst),
        .CRC_Clear (crc_clear),
        .CRC_En    (crc_en),
        .DataIn    (crc_0_in[15:0]),
        .CRC_CODE  (crc_0_out[15:0])
    );

    CRC_16_header_data CRC_1_uut (
        .Clk       (gtx_user_clk_in),
        .Reset     (aurora_sw_rst),
        .CRC_Clear (crc_clear),
        .CRC_En    (crc_en),
        .DataIn    (crc_1_in[15:0]),
        .CRC_CODE  (crc_1_out[15:0])
    );

    CRC_16_header_data CRC_2_uut (
        .Clk       (gtx_user_clk_in),
        .Reset     (aurora_sw_rst),
        .CRC_Clear (crc_clear),
        .CRC_En    (crc_en),
        .DataIn    (crc_2_in[15:0]),
        .CRC_CODE  (crc_2_out[15:0])
    );

    CRC_16_header_data CRC_3_uut (
        .Clk       (gtx_user_clk_in),
        .Reset     (aurora_sw_rst),
        .CRC_Clear (crc_clear),
        .CRC_En    (crc_en),
        .DataIn    (crc_3_in[15:0]),
        .CRC_CODE  (crc_3_out[15:0])
    );

endmodule
