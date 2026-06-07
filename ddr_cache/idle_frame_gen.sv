//--------------------------------------------------------------------------------
// Company: Neusoft Medical Systems
// Engineer: 
//  
// Create Date:     15/1/2019 
// Design Name:    
// Module Name:    idle_frame_gen 
// Project Name:   H71
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: generate idle frame data   
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: make
//
//--------------------------------------------------------------------------------
`include "h80_define.sv"
`timescale 1ns/1ps
module idle_frame_gen(
          /*AUTOARG*/
   // Outputs
   idle_process_active_out, idle_process_active_debug_out,
   idle_header_ctl_word_en_out, idle_slice_trans_start, idle_trig,
   idle_data_out,
   // Inputs
   aurora_sw_rst, rst_local, gtx_user_clk_in, idle_process_en, conv,
   DMS_Type, L_FTP_temp, R_FTP_temp, idle_frame_ind, header_cnt,
   slice_cnt, header_en, idle_slice_data_en, header_cmd_1_en,
   header_cmd_2_en, footer_en, slice_cmd_1_en, slice_cmd_2_en,
   crc_tx_1_en, crc_tx_2_en, clear_crc, crc_en,
   gtx_refresh_process_en
   );
                                   
   input                           aurora_sw_rst;                                    //from aurora_8b10b
   input                           rst_local;                              //local reset in system clock 
   input                           gtx_user_clk_in;                                    //system clock 100M
                                  
   input                           idle_process_en;                      
                                   
                                   
   input                           conv;                                   //conv
   
   input [7:0]                     DMS_Type;
   input [15:0]                    L_FTP_temp;
   input [15:0]                    R_FTP_temp;
                                   
   output                          idle_process_active_out;                // to view_trans_ctrl 
   output                          idle_process_active_debug_out;          
   output                          idle_header_ctl_word_en_out;            // to aurora_tx_frame 
   output                          idle_slice_trans_start;                 // to aurora_tx_frame 
                                   
   output                          idle_trig;  
   //input         idle_process_en;

   input         idle_frame_ind;
   input [7:0]   header_cnt;   // from aurora_tx_frame 
   input [7:0]   slice_cnt;    // from aurora_tx_frame 

   input         header_en;
   input         idle_slice_data_en;
   
   input         header_cmd_1_en;
   input         header_cmd_2_en;
   input         footer_en;
   //input         footer_2_en;
   input         slice_cmd_1_en;
   input         slice_cmd_2_en;
   input         crc_tx_1_en;
   input         crc_tx_2_en;
   
   input         clear_crc;
   input         crc_en;

   input         gtx_refresh_process_en;
   output [63:0] idle_data_out;
   
   //---------------CRC GENERATE interface --------------

   /*
   output          crc_clear;
   
   output          crc_0_en;
   output          crc_1_en;
   output          crc_2_en;
   output          crc_3_en;
   
   output [15:0]       crc_0_in;
   output [15:0]       crc_1_in;
   output [15:0]       crc_2_in;
   output [15:0]       crc_3_in;
   
   input [15:0]        crc_0_out;
   input [15:0]        crc_1_out;
   input [15:0]        crc_2_out;
   input [15:0]        crc_3_out;
   */
      
   
   reg [15:0]            idle_head_005_r;
   reg [15:0]            idle_head_006_r;
   
   
   wire [15:0]           idle_head_000    ={DMS_Type, 8'h01};  // word 0,
   wire [15:0]           idle_head_001    ='h0000;  // word 1 -- bit1: make data on flag, bit 8: A/B side flag
   wire [15:0]           idle_head_002    ='h0010;  // word 2
   wire [15:0]           idle_head_003    ='h0011;  // word 3 -- Integration time
   wire [15:0]           idle_head_004    ='h0100;  // word 4
   wire [15:0]           idle_head_005    ='h0101;  // word 5
   wire [15:0]           idle_head_006    ='h0110;  // word 6
   wire [15:0]           idle_head_007    ='h0111;  // word 7
   wire [15:0]           idle_head_008    ='hFACE;  // word 8
   wire [15:0]           idle_head_009    ='h1001;  // word 9
   
   wire [15:0]           idle_head_010    = 'h1010;  // word 10
   wire [15:0]           idle_head_011    = 'h1011;  // word 11
   wire [15:0]           idle_head_012    = 'h1100;  // word 12
   wire [15:0]           idle_head_013    = 'h1101;  // word 13
   wire [15:0]           idle_head_014    = 'h1110;  // word 14
   wire [15:0]           idle_head_015    = 'h1111;  // word 15
   wire [15:0]           idle_head_016    = 'hFACE;  // word 16
   wire [15:0]           idle_head_017    = 'h2001;  // word 17
   wire [15:0]           idle_head_018    = 'h2010;  // word 18
   wire [15:0]           idle_head_019    = 'h2011;  // word 19
   
   wire [15:0]           idle_head_020    = 'h2100;  // word 20
   wire [15:0]           idle_head_021    = 'h2101;  // word 21
   wire [15:0]           idle_head_022    = 'h2110;  // word 22
   wire [15:0]           idle_head_023    = 'h2111;  // word 23
   wire [15:0]           idle_head_024    = 'hFACE;  // word 24
   wire [15:0]           idle_head_025    = 'h3001;  // word 25
   wire [15:0]           idle_head_026    = 'h3010;  // word 26
   wire [15:0]           idle_head_027    = 'h3011;  // word 27
   wire [15:0]           idle_head_028    = 'h3100;  // word 28
   wire [15:0]           idle_head_029    = 'h3101;  // word 29
   
   wire [15:0]           idle_head_030    = 'h3110;  // word 30
   wire [15:0]           idle_head_031    = 'h0020;  // word 31, slice number,32 slices
   wire [15:0]           idle_head_032    = 'hFACE;  // word 32
   wire [15:0]           idle_head_033    = 'h4001;  // word 33
   wire [15:0]           idle_head_034    = 'h4010;  // word 34
   wire [15:0]           idle_head_035    = 'h4011;  // word 35
   wire [15:0]           idle_head_036    = 'h4100;  // word 36
   wire [15:0]           idle_head_037    = 'h4101;  // word 37
   wire [15:0]           idle_head_038    = 'h4110;  // word 38
   wire [15:0]           idle_head_039    = 'h4111;  // word 39
   
   wire [15:0]           idle_head_040    = 'hFACE;  // word 40
   wire [15:0]           idle_head_041    = 'h5001;  // word 41
   wire [15:0]           idle_head_042    = 'h5010;  // word 42
   wire [15:0]           idle_head_043    = 'h5011;  // word 43
   wire [15:0]           idle_head_044    = 'h5100;  // word 44
   wire [15:0]           idle_head_045    = 'h5101;  // word 45
   wire [15:0]           idle_head_046    = 'h5110;  // word 46
   wire [15:0]           idle_head_047    = 'h5111;  // word 47
   wire [15:0]           idle_head_048    = 'hFACE;  // word 48
   wire [15:0]           idle_head_049    = 'h6001;  // word 49
   
   wire [15:0]           idle_head_050    = 'h6010;  // word 50
   wire [15:0]           idle_head_051    = 'h6011;  // word 51
   wire [15:0]           idle_head_052    = 'h6100;  // word 52
   wire [15:0]           idle_head_053    = 'h6101;  // word 53
   wire [15:0]           idle_head_054    = 'h6110;  // word 54
   wire [15:0]           idle_head_055    = 'h6111;  // word 55
   wire [15:0]           idle_head_056    = 'hFACE;  // word 56
   wire [15:0]           idle_head_057    = 'h7001;  // word 57
   wire [15:0]           idle_head_058    = 'h7010;  // word 58
   wire [15:0]           idle_head_059    = 'h7111;  // word 59
   
   wire [15:0]           idle_head_060    = 'h7100;  // word 60
   wire [15:0]           idle_head_061    = 'h7101;  // word 61
   wire [15:0]           idle_head_062    = 'h7110;  // word 62
   wire [15:0]           idle_head_063    = 'h7011;  // word 63
   wire [15:0]           idle_head_064    = 'hFACE;  // word 64
   wire [15:0]           idle_head_065    = 'h8001;  // word 65
   wire [15:0]           idle_head_066    = 'h8010;  // word 66
   wire [15:0]           idle_head_067    = 'h8011;  // word 67
   wire [15:0]           idle_head_068    = 'h8100;  // word 68
   wire [15:0]           idle_head_069    = 'h8101;  // word 69
   
   wire [15:0]           idle_head_070    = 'h8110;  // word 70
   wire [15:0]           idle_head_071    = 'h8111;  // word 71
   wire [15:0]           idle_head_072    = 'hFACE;  // word 72
   wire [15:0]           idle_head_073    = 'h9001;  // word 73
   wire [15:0]           idle_head_074    = 'h9010;  // word 74
   wire [15:0]           idle_head_075    = 'h9011;  // word 75
   wire [15:0]           idle_head_076    = 'h9100;  // word 76
   wire [15:0]           idle_head_077    = 'h9101;  // word 77
   wire [15:0]           idle_head_078    = 'h9110;  // word 78
   wire [15:0]           idle_head_079    = 'h9111;  // word 79
   
   wire [15:0]           idle_head_080    = 'hFACE;  // word 80
   wire [15:0]           idle_head_081    = 'hA001;  // word 81
   wire [15:0]           idle_head_082    = 'hA010;  // word 82
   wire [15:0]           idle_head_083    = 'hA011;  // word 83
   wire [15:0]           idle_head_084    = 'hA100;  // word 84
   wire [15:0]           idle_head_085    = 'hA101;  // word 85
   wire [15:0]           idle_head_086    = 'hA110;  // word 86
   wire [15:0]           idle_head_087    = 'hA111;  // word 87
   wire [15:0]           idle_head_088    = 'hFACE;  // word 88
   wire [15:0]           idle_head_089    = 'hB001;  // word 89
   
   wire [15:0]           idle_head_090    = 'hB010;  // word 90
   wire [15:0]           idle_head_091    = 'hB011;  // word 91
   wire [15:0]           idle_head_092    = 'hB100;  // word 92
   wire [15:0]           idle_head_093    = 'hB101;  // word 93
   wire [15:0]           idle_head_094    = 'hB110;  // word 94
   wire [15:0]           idle_head_095    = 'hB111;  // word 95
   wire [15:0]           idle_head_096    = 'hFACE;  // word 96
   wire [15:0]           idle_head_097    = 'hC001;  // word 97
   wire [15:0]           idle_head_098    = 'hC010;  // word 98
   wire [15:0]           idle_head_099    = 'hC011;  // word 99
   
   wire [15:0]           idle_head_100    = 'hC100;  // word 100
   wire [15:0]           idle_head_101    = 'hC101;  // word 101
   wire [15:0]           idle_head_102    = 'hC110;  // word 102
   wire [15:0]           idle_head_103    = 'hC111;  // word 103
   wire [15:0]           idle_head_104    = 'hFACE;  // word 104
   wire [15:0]           idle_head_105    = 'hD001;  // word 105
   wire [15:0]           idle_head_106    = 'hD010;  // word 106
   wire [15:0]           idle_head_107    = 'hD011;  // word 107
   wire [15:0]           idle_head_108    = 'hD100;  // word 108
   wire [15:0]           idle_head_109    = 'hD101;  // word 109
   
   wire [15:0]           idle_head_110    = 'hD110;  // word 110
   wire [15:0]           idle_head_111    = 'hD111;  // word 111
   wire [15:0]           idle_head_112    = 'hFACE;  // word 112
   wire [15:0]           idle_head_113    = 'hE001;  // word 113
   wire [15:0]           idle_head_114    = 'hE010;  // word 114
   wire [15:0]           idle_head_115    = 'hE011;  // word 115
   wire [15:0]           idle_head_116    = 'hE100;  // word 116
   wire [15:0]           idle_head_117    = 'hE101;  // word 117
   wire [15:0]           idle_head_118    = 'hE110;  // word 118
   wire [15:0]           idle_head_119    = 'hE111;  // word 119
   
   wire [15:0]           idle_head_120    = 'hFACE;  // word 120
   wire [15:0]           idle_head_121    = 'hF001;  // word 121
   wire [15:0]           idle_head_122    = 'hF010;  // word 122
   wire [15:0]           idle_head_123    = 'hF011;  // word 123
   wire [15:0]           idle_head_124    = 'hF100;  // word 124
   wire [15:0]           idle_head_125    = 'hF101;  // word 125
   wire [15:0]           idle_head_126    = 'hFACE;  // word 126
   wire [15:0]           idle_head_127    = 'hF111;  // word 127
      
   
   wire [15:0]           HEADER_000     = idle_head_000 ;
   wire [15:0]           HEADER_001     = idle_head_001 ;
   wire [15:0]           HEADER_002     = idle_head_002 ;
   wire [15:0]           HEADER_003     = idle_head_003 ;
   wire [15:0]           HEADER_004     = idle_head_004 ;
   //wire [15:0]             HEADER_005       = idle_head_005 ;
   //wire [15:0]             HEADER_006       = idle_head_006 ;
   wire [15:0]           HEADER_005     =idle_head_005_r;
   wire [15:0]           HEADER_006     =idle_head_006_r;
   
   wire [15:0]           HEADER_007     = idle_head_007 ;
   wire [15:0]           HEADER_008     = idle_head_008 ;
   wire [15:0]           HEADER_009     = idle_head_009 ;
   
   wire [15:0]           HEADER_010     = idle_head_010 ;
   wire [15:0]           HEADER_011     = idle_head_011 ;
   wire [15:0]           HEADER_012     = idle_head_012 ;
   wire [15:0]           HEADER_013     = idle_head_013 ;
   wire [15:0]           HEADER_014     = idle_head_014 ;
   wire [15:0]           HEADER_015     = idle_head_015 ;
   wire [15:0]           HEADER_016     = idle_head_016 ;
   wire [15:0]           HEADER_017     = idle_head_017 ;
   wire [15:0]           HEADER_018     = idle_head_018 ;
   wire [15:0]           HEADER_019     = idle_head_019 ;
   
   wire [15:0]           HEADER_020     = idle_head_020 ;
   wire [15:0]           HEADER_021     = idle_head_021 ;
   wire [15:0]           HEADER_022     = idle_head_022 ;
   wire [15:0]           HEADER_023     = idle_head_023 ;
   wire [15:0]           HEADER_024     = idle_head_024 ;
   wire [15:0]           HEADER_025     = idle_head_025 ;
   wire [15:0]           HEADER_026     = idle_head_026 ;
   wire [15:0]           HEADER_027     = idle_head_027 ;
   wire [15:0]           HEADER_028     = idle_head_028 ;
   wire [15:0]           HEADER_029     = idle_head_029 ;
   
   wire [15:0]           HEADER_030     = idle_head_030 ;
   wire [15:0]           HEADER_031     = idle_head_031 ;
   wire [15:0]           HEADER_032     = idle_head_032 ;
   wire [15:0]           HEADER_033     = idle_head_033 ;
   wire [15:0]           HEADER_034     = idle_head_034 ;
   wire [15:0]           HEADER_035     = idle_head_035 ;
   wire [15:0]           HEADER_036     = idle_head_036 ;
   wire [15:0]           HEADER_037     = idle_head_037 ;
   wire [15:0]           HEADER_038     = idle_head_038 ;
   wire [15:0]           HEADER_039     = idle_head_039 ;
   
   wire [15:0]           HEADER_040     = idle_head_040 ;
   wire [15:0]           HEADER_041     = idle_head_041 ;
   wire [15:0]           HEADER_042     = idle_head_042 ;
   wire [15:0]           HEADER_043     = idle_head_043 ;
   wire [15:0]           HEADER_044     = idle_head_044 ;
   wire [15:0]           HEADER_045     = idle_head_045 ;
   wire [15:0]           HEADER_046     = idle_head_046 ;
   wire [15:0]           HEADER_047     = idle_head_047 ;
   wire [15:0]           HEADER_048     = idle_head_048 ;
   wire [15:0]           HEADER_049     = idle_head_049 ;
   
   wire [15:0]           HEADER_050     = idle_head_050 ;
   wire [15:0]           HEADER_051     = idle_head_051 ;
   wire [15:0]           HEADER_052     = idle_head_052 ;
   wire [15:0]           HEADER_053     = idle_head_053 ;
   wire [15:0]           HEADER_054     = idle_head_054 ;
   wire [15:0]           HEADER_055     = idle_head_055 ;
   wire [15:0]           HEADER_056     = idle_head_056 ;
   wire [15:0]           HEADER_057     = idle_head_057 ;
   wire [15:0]           HEADER_058     = idle_head_058 ;
   wire [15:0]           HEADER_059     = idle_head_059 ;
   
   wire [15:0]           HEADER_060     = idle_head_060 ;
   wire [15:0]           HEADER_061     = idle_head_061 ;
   wire [15:0]           HEADER_062     = idle_head_062 ;
   wire [15:0]           HEADER_063     = idle_head_063 ;
   wire [15:0]           HEADER_064     = idle_head_064 ;
   wire [15:0]           HEADER_065     = idle_head_065 ;
   wire [15:0]           HEADER_066     = idle_head_066 ;
   wire [15:0]           HEADER_067     = idle_head_067 ;
   wire [15:0]           HEADER_068     = idle_head_068 ;
   wire [15:0]           HEADER_069     = idle_head_069 ;
   
   wire [15:0]           HEADER_070     = idle_head_070 ;
   wire [15:0]           HEADER_071     = idle_head_071 ;
   wire [15:0]           HEADER_072     = idle_head_072 ;
   wire [15:0]           HEADER_073     = idle_head_073 ;
   wire [15:0]           HEADER_074     = idle_head_074 ;
   wire [15:0]           HEADER_075     = idle_head_075 ;
   wire [15:0]           HEADER_076     = idle_head_076 ;
   wire [15:0]           HEADER_077     = idle_head_077 ;
   wire [15:0]           HEADER_078     = idle_head_078 ;
   wire [15:0]           HEADER_079     = idle_head_079 ;
   
   wire [15:0]           HEADER_080     = idle_head_080 ;
   wire [15:0]           HEADER_081     = idle_head_081 ;
   wire [15:0]           HEADER_082     = idle_head_082 ;
   wire [15:0]           HEADER_083     = idle_head_083 ;
   wire [15:0]           HEADER_084     = idle_head_084 ;
   wire [15:0]           HEADER_085     = idle_head_085 ;
   wire [15:0]           HEADER_086     = idle_head_086 ;
   wire [15:0]           HEADER_087     = idle_head_087 ;
   wire [15:0]           HEADER_088     = idle_head_088 ;
   wire [15:0]           HEADER_089     = idle_head_089 ;
   
   wire [15:0]           HEADER_090     = idle_head_090 ;
   wire [15:0]           HEADER_091     = idle_head_091 ;
   wire [15:0]           HEADER_092     = idle_head_092 ;
   wire [15:0]           HEADER_093     = idle_head_093 ;
   wire [15:0]           HEADER_094     = idle_head_094 ;
   wire [15:0]           HEADER_095     = idle_head_095 ;
   wire [15:0]           HEADER_096     = idle_head_096 ;
   wire [15:0]           HEADER_097     = idle_head_097 ;
   wire [15:0]           HEADER_098     = idle_head_098 ;
   wire [15:0]           HEADER_099     = idle_head_099 ;
   
   wire [15:0]           HEADER_100     = idle_head_100 ;
   wire [15:0]           HEADER_101     = idle_head_101 ;
   wire [15:0]           HEADER_102     = idle_head_102 ;
   wire [15:0]           HEADER_103     = idle_head_103 ;
   wire [15:0]           HEADER_104     = idle_head_104 ;
   wire [15:0]           HEADER_105     = idle_head_105 ;
   wire [15:0]           HEADER_106     = idle_head_106 ;
   wire [15:0]           HEADER_107     = idle_head_107 ;
   wire [15:0]           HEADER_108     = idle_head_108 ;
   wire [15:0]           HEADER_109     = idle_head_109 ;
   
   wire [15:0]           HEADER_110     = idle_head_110 ;
   wire [15:0]           HEADER_111     = idle_head_111 ;
   wire [15:0]           HEADER_112     = idle_head_112 ;
   wire [15:0]           HEADER_113     = idle_head_113 ;
   wire [15:0]           HEADER_114     = idle_head_114 ;
   wire [15:0]           HEADER_115     = idle_head_115 ;
   wire [15:0]           HEADER_116     = idle_head_116 ;
   wire [15:0]           HEADER_117     = idle_head_117 ;
   wire [15:0]           HEADER_118     = idle_head_118 ;
   wire [15:0]           HEADER_119     = idle_head_119 ;
                                          
   wire [15:0]           HEADER_120     = idle_head_120 ;
   wire [15:0]           HEADER_121     = idle_head_121 ;
   wire [15:0]           HEADER_122     = idle_head_122 ;
   wire [15:0]           HEADER_123     = idle_head_123 ;
   wire [15:0]           HEADER_124     = idle_head_124 ;
   wire [15:0]           HEADER_125     = idle_head_125 ;
   wire [15:0]           HEADER_126     = idle_head_126 ;
   wire [15:0]           HEADER_127     = idle_head_127 ;

   reg       conv_d;
   reg       conv_dd;
   reg       conv_ddd;
   
   always @(posedge gtx_user_clk_in) begin
      conv_d      <= conv;
      conv_dd       <= conv_d;
      conv_ddd      <= conv_dd;
   end

   wire conv_edge_pulse    = conv_dd ^ conv_ddd;
      
   //--latch header
   
   
   always @(posedge gtx_user_clk_in) begin
      if(aurora_sw_rst || rst_local) begin
     idle_head_005_r <= 'h0;
     idle_head_006_r   <= 'h0;
      end
      else begin 
     idle_head_005_r   <=L_FTP_temp;
     idle_head_006_r   <=R_FTP_temp;
      end
   end
   
   
   assign            idle_rst = rst_local | aurora_sw_rst;
   
   
   assign           idle_process_en_i    =  idle_process_en;

  
   
   
   reg                             idle_process_active;
   
   always @(posedge gtx_user_clk_in) begin
      if(aurora_sw_rst) begin
        idle_process_active   <= 'h0;
      end
      else if (rst_local) begin
        idle_process_active   <= 'h0;
      end
      else if(idle_process_en_i && conv_edge_pulse ) begin
        idle_process_active   <= 'h1;
      end
      else if ((~idle_process_en_i) && conv_edge_pulse ) begin
        idle_process_active   <= 'h0;
      end
   end

   reg gtx_refresh_process_en_active;

  always @(posedge gtx_user_clk_in) begin
    if(aurora_sw_rst) begin
        gtx_refresh_process_en_active  <= 'h0;
    end
    else if( gtx_refresh_process_en) begin
        gtx_refresh_process_en_active  <= 1'h1;
    end
    else if((~gtx_refresh_process_en) && conv_edge_pulse ) begin
        gtx_refresh_process_en_active  <= 1'h0;
    end
  end

  assign refresh_process_en = gtx_refresh_process_en | gtx_refresh_process_en_active;

   
  reg                             idle_process_active_out;
  
  always @(posedge gtx_user_clk_in) begin
    if(aurora_sw_rst) begin
      idle_process_active_out   <= 'h0;
    end
    else begin
      idle_process_active_out   <= idle_process_active;
    end
  end

  reg                             idle_process_active_debug_i;
  reg                             idle_process_active_debug_out;
   
   
  //-----------------------------for debug signal------------------------------------   
   always @(posedge gtx_user_clk_in) begin
      if(aurora_sw_rst) begin
        idle_process_active_debug_i     <= 'h0;    
        idle_process_active_debug_out   <= 'h0;
      end
      else  begin
        idle_process_active_debug_i     <= idle_process_active;
        idle_process_active_debug_out   <= idle_process_active_debug_i;
      end
   end
   
//-----------------------------------------------------------------------------------       

  //-----------------------------------------------------------------------------------        

  reg [11:0]                      idle_counter;

  assign         idle_counter_lim = idle_counter[11];
  
  always @(posedge gtx_user_clk_in) begin
    if(aurora_sw_rst || rst_local) begin
      idle_counter   <= 'h0;
    end
    else if (refresh_process_en) begin
      idle_counter   <= 'h0;
    end  
    else if (idle_process_en_i &&  conv_edge_pulse ) begin 
      idle_counter   <= 'h0;
    end
    else if ((~idle_counter_lim) && idle_process_active) begin 
      idle_counter   <= idle_counter + 'h1;
    end
  end
  
  assign idle_trig_t = idle_counter == 'h00258;

  reg                             idle_trig;

   
   
  always @(posedge gtx_user_clk_in) begin
    if(aurora_sw_rst || rst_local) begin
      idle_trig   <= 'h0;
    end
    else  begin
      idle_trig   <= idle_trig_t;
    end
  end
   
     
  reg                             idle_slice_trans_start;

  always @(posedge gtx_user_clk_in) begin
    if(aurora_sw_rst || rst_local) begin
      idle_slice_trans_start   <= 'h0;
    end
    else if (idle_trig_t) begin
      idle_slice_trans_start   <= 'h0;
    end
    else if (idle_counter == 'h001e0) begin
      idle_slice_trans_start   <= 'h1;
    end
  end

   
  wire   idle_header_ctl_word_en_out;

  assign idle_header_ctl_word_en_out = idle_trig;
      
    /////////////////data ////////////////////////////////////

  wire [11:0]           all_slice_number;
  assign                all_slice_number = slice_cnt;
                        
  wire [63:0]           sync_header_data       = 64'ha5a5a5a5_5a5a5a5a;
  wire [63:0]           h_frame_header_data    = 64'h04331000_00002100;
  wire [63:0]           s_frame_header_data    = {20'h04330,all_slice_number,32'h0000db00};
  wire [63:0]           footer_data            = 64'hFACEEACE_CACEBACE;

  
  reg [63:0]  header_data;
   
   
   
   always @(/*AS*/HEADER_000 or HEADER_001 or HEADER_002 or HEADER_003
      or HEADER_004 or HEADER_005 or HEADER_006 or HEADER_007
      or HEADER_008 or HEADER_009 or HEADER_010 or HEADER_011
      or HEADER_012 or HEADER_013 or HEADER_014 or HEADER_015
      or HEADER_016 or HEADER_017 or HEADER_018 or HEADER_019
      or HEADER_020 or HEADER_021 or HEADER_022 or HEADER_023
      or HEADER_024 or HEADER_025 or HEADER_026 or HEADER_027
      or HEADER_028 or HEADER_029 or HEADER_030 or HEADER_031
      or HEADER_032 or HEADER_033 or HEADER_034 or HEADER_035
      or HEADER_036 or HEADER_037 or HEADER_038 or HEADER_039
      or HEADER_040 or HEADER_041 or HEADER_042 or HEADER_043
      or HEADER_044 or HEADER_045 or HEADER_046 or HEADER_047
      or HEADER_048 or HEADER_049 or HEADER_050 or HEADER_051
      or HEADER_052 or HEADER_053 or HEADER_054 or HEADER_055
      or HEADER_056 or HEADER_057 or HEADER_058 or HEADER_059
      or HEADER_060 or HEADER_061 or HEADER_062 or HEADER_063
      or HEADER_064 or HEADER_065 or HEADER_066 or HEADER_067
      or HEADER_068 or HEADER_069 or HEADER_070 or HEADER_071
      or HEADER_072 or HEADER_073 or HEADER_074 or HEADER_075
      or HEADER_076 or HEADER_077 or HEADER_078 or HEADER_079
      or HEADER_080 or HEADER_081 or HEADER_082 or HEADER_083
      or HEADER_084 or HEADER_085 or HEADER_086 or HEADER_087
      or HEADER_088 or HEADER_089 or HEADER_090 or HEADER_091
      or HEADER_092 or HEADER_093 or HEADER_094 or HEADER_095
      or HEADER_096 or HEADER_097 or HEADER_098 or HEADER_099
      or HEADER_100 or HEADER_101 or HEADER_102 or HEADER_103
      or HEADER_104 or HEADER_105 or HEADER_106 or HEADER_107
      or HEADER_108 or HEADER_109 or HEADER_110 or HEADER_111
      or HEADER_112 or HEADER_113 or HEADER_114 or HEADER_115
      or HEADER_116 or HEADER_117 or HEADER_118 or HEADER_119
      or HEADER_120 or HEADER_121 or HEADER_122 or HEADER_123
      or header_cnt) begin
      case (header_cnt)
        'd0: header_data        = {HEADER_003,HEADER_002,HEADER_001,HEADER_000};
        'd1: header_data        = {HEADER_007,HEADER_006,HEADER_005,HEADER_004};
        'd2: header_data        = {HEADER_011,HEADER_010,HEADER_009,HEADER_008};
        'd3: header_data        = {HEADER_015,HEADER_014,HEADER_013,HEADER_012};
        'd4: header_data        = {HEADER_019,HEADER_018,HEADER_017,HEADER_016};
        'd5: header_data        = {HEADER_023,HEADER_022,HEADER_021,HEADER_020};
        'd6: header_data        = {HEADER_027,HEADER_026,HEADER_025,HEADER_024};
        'd7: header_data        = {HEADER_031,HEADER_030,HEADER_029,HEADER_028};
        'd8: header_data        = {HEADER_035,HEADER_034,HEADER_033,HEADER_032};
        'd9: header_data        = {HEADER_039,HEADER_038,HEADER_037,HEADER_036};
        'd10: header_data       = {HEADER_043,HEADER_042,HEADER_041,HEADER_040};
        'd11: header_data       = {HEADER_047,HEADER_046,HEADER_045,HEADER_044};
        'd12: header_data       = {HEADER_051,HEADER_050,HEADER_049,HEADER_048};
        'd13: header_data       = {HEADER_055,HEADER_054,HEADER_053,HEADER_052};
        'd14: header_data       = {HEADER_059,HEADER_058,HEADER_057,HEADER_056};
        'd15: header_data       = {HEADER_063,HEADER_062,HEADER_061,HEADER_060};
        'd16: header_data       = {HEADER_067,HEADER_066,HEADER_065,HEADER_064};
        'd17: header_data       = {HEADER_071,HEADER_070,HEADER_069,HEADER_068};
        'd18: header_data       = {HEADER_075,HEADER_074,HEADER_073,HEADER_072};
        'd19: header_data       = {HEADER_079,HEADER_078,HEADER_077,HEADER_076};
        'd20: header_data       = {HEADER_083,HEADER_082,HEADER_081,HEADER_080};
        'd21: header_data       = {HEADER_087,HEADER_086,HEADER_085,HEADER_084};
        'd22: header_data       = {HEADER_091,HEADER_090,HEADER_089,HEADER_088};
        'd23: header_data       = {HEADER_095,HEADER_094,HEADER_093,HEADER_092};
        'd24: header_data       = {HEADER_099,HEADER_098,HEADER_097,HEADER_096};
        'd25: header_data       = {HEADER_103,HEADER_102,HEADER_101,HEADER_100};
        'd26: header_data       = {HEADER_107,HEADER_106,HEADER_105,HEADER_104};
        'd27: header_data       = {HEADER_111,HEADER_110,HEADER_109,HEADER_108};
        'd28: header_data       = {HEADER_115,HEADER_114,HEADER_113,HEADER_112};
        'd29: header_data       = {HEADER_119,HEADER_118,HEADER_117,HEADER_116};
        'd30: header_data       = {HEADER_123,HEADER_122,HEADER_121,HEADER_120};
        default :  header_data    = 64'h0;
      endcase // case (header_cnt)
   end // always @ (...
   

   /*
   reg           header_en_d;
   reg           header_cmd_en_d;
   reg           footer_en_d;
   reg           slice_cmd_en_d;
   reg           crc_tx_en_d;
   reg           crc_tx_en_dd;
   
                
   always @(posedge gtx_user_clk_in) begin
      header_en_d   <= header_en;
      header_cmd_en_d   <= header_cmd_en;
      footer_en_d   <= footer_en;
      slice_cmd_en_d  <= slice_cmd_en;
      crc_tx_en_d   <= crc_tx_en;
      crc_tx_en_dd  <= crc_tx_en_d;
   end
    */
  reg  [63:0]                     idle_data_out;
  wire                            idle_data_fifo_wr_en;
                                  
  wire [15:0]                     crc_0_in;
  wire [15:0]                     crc_1_in;
  wire [15:0]                     crc_2_in;
  wire [15:0]                     crc_3_in;
                                  
  wire [15:0]                     crc_0_out;
  wire [15:0]                     crc_1_out;
  wire [15:0]                     crc_2_out;
  wire [15:0]                     crc_3_out;
  
    
  wire [63:0]                     crc_out;
  reg  [15:0]                     data_lfsr_r;

   
   /*
    reg [63:0]         idle_data_out_t;
  
   always @(posedge  gtx_user_clk_in ) begin
      if(~idle_frame_ind) begin
   idle_data_out_t    <= 'h0;
      end
      else if (header_cmd_1_en) begin
   idle_data_out_t    <= h_frame_header_data[63:0];
      end
      else if (slice_cmd_1_en) begin
   idle_data_out_t    <= s_frame_header_data[63:0];
      end
      else if (footer_en) begin
   idle_data_out_t   <= footer_data[63:0];
      end
      else if(header_en)begin    
   idle_data_out_t   <= header_data;
      end 
      else  begin
   idle_data_out_t    <= {data_lfsr_r,data_lfsr_r,data_lfsr_r,data_lfsr_r};
      end
   end
    */

  wire [63:0]          idle_data_out_t;

  assign idle_data_out_t    = {data_lfsr_r,data_lfsr_r,data_lfsr_r,data_lfsr_r};
  
  always @(/*AS*/crc_out or crc_tx_2_en or footer_data or footer_en
    or h_frame_header_data or header_cmd_2_en or header_data
    or header_en or idle_data_out_t or s_frame_header_data
    or slice_cmd_2_en) begin 
    if (crc_tx_2_en )  begin
      idle_data_out  =  crc_out;
    end
    else if (header_cmd_2_en) begin
      idle_data_out     = h_frame_header_data[63:0];
    end
    else if (slice_cmd_2_en) begin
      idle_data_out     = s_frame_header_data[63:0];
    end
    else if (header_en) begin
      idle_data_out     = header_data;
    end
    else if (footer_en) begin
      idle_data_out     = footer_data[63:0];
    end
    else begin 
      idle_data_out     = idle_data_out_t;
    end
  end
   
   
   
   //////////////////output signal generate ///////////////////////////
  
   //--data generate
   wire [15:0]                     data_lfsr_r_t;
   wire                            data_lfst_fb;
                                   
   wire                            idle_data_gen_en;
   
   assign idle_data_gen_en = idle_slice_data_en;
   
                
   //not(data_lfsr_r(3) xor data_lfsr_r(12) xor data_lfsr_r(14) xor data_lfsr_r(15))
   assign           data_lfst_fb = (~((data_lfsr_r[12]) ^ data_lfsr_r[3] ^ data_lfsr_r[1])) ^ data_lfsr_r[0];
   
   assign           data_lfsr_r_t =  {data_lfst_fb,data_lfsr_r[15:1]};
   
                
   always @(posedge gtx_user_clk_in) begin
      if(aurora_sw_rst || rst_local) begin
        data_lfsr_r <= 'hABCD;
      end
      else if (idle_trig) begin
        data_lfsr_r <= 'hABCD;
      end
      else if (idle_data_gen_en) begin 
        data_lfsr_r     <= data_lfsr_r_t;
      end
   end

   //////////////////CRC generation /////////////////////////

   assign crc_0_in = idle_data_out[15:0];
   assign crc_1_in = idle_data_out[31:16];
   assign crc_2_in = idle_data_out[47:32];
   assign crc_3_in = idle_data_out[63:48];
   
   assign crc_out       = {  crc_3_out,crc_2_out,crc_1_out,crc_0_out};
 

   wire   crc_clear = clear_crc;
    
   
     CRC_16_header_data        CRC_0_uut(
                                        // Outputs
                                        .CRC_CODE                (crc_0_out[15:0]),
                                        // Inputs                
                                        .Clk                     (gtx_user_clk_in),
                                        .Reset                   (aurora_sw_rst),
                                        .CRC_Clear               (crc_clear),
                                        .CRC_En                  (crc_en),
                                        .DataIn                  (crc_0_in[15:0]));
   
   CRC_16_header_data        CRC_1_uut(
                                        // Outputs
                                        .CRC_CODE                (crc_1_out[15:0]),
                                        // Inputs                
                                        .Clk                     (gtx_user_clk_in),
                                        .Reset                   (aurora_sw_rst),
                                        .CRC_Clear               (crc_clear),
                                        .CRC_En                  (crc_en),
                                        .DataIn                  (crc_1_in[15:0]));
   
   
   CRC_16_header_data        CRC_2_uut(
                                        // Outputs
                                        .CRC_CODE                (crc_2_out[15:0]),
                                        // Inputs                
                                        .Clk                     (gtx_user_clk_in),
                                        .Reset                   (aurora_sw_rst),
                                        .CRC_Clear               (crc_clear),
                                        .CRC_En                  (crc_en),
                                        .DataIn                  (crc_2_in[15:0]));
   
   
   CRC_16_header_data        CRC_3_uut(
                                        // Outputs
                                        .CRC_CODE                (crc_3_out[15:0]),
                                        // Inputs                
                                        .Clk                     (gtx_user_clk_in),
                                        .Reset                   (aurora_sw_rst),
                                        .CRC_Clear               (crc_clear),
                                        .CRC_En                  (crc_en),
                                        .DataIn                  (crc_3_in[15:0]));

   
   
       
   
endmodule // idle_frame_gen

              