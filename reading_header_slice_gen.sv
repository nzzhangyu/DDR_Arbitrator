`timescale 1ns/1ps
module reading_header_slice_gen(/*AUTOARG*/
   // Outputs
   header_data_out, header_data_out_en, DOM_header_latch_pulse_en,
   reading_number, TablePos, REF_XDetA, REF_XDetB, wr_qdr_reading_num,
   wr_number_err, make_data_on, view_Reading_Done,
   sampling_data_on_out, conv_edge_out, last_view_wr_done,
   time_2000us_en_out, view_header_overrun, rx_fifo_empty,
   FirstViewFlag_reg_out, LastViewFlag_reg_out, header_tp,
   wr_view_counter, header_state,
   // Inputs
   clk, RESET, clk_1us, MAKE_DATA, conv, slice_sel, RP_back_en,
   Data_Compress, compress_mode, discard_chl_r, compress_chl_r,
   discard_chl_l, compress_chl_l, DMS_Type, DDC_Range, DAS_Mode,
   Scan_Mode, DMB_TEMP, DMS_Fan_Speed, Ltmp_FAN_TACH, Rtmp_FAN_TACH,
   Ltmp_sensor_out, Rtmp_sensor_out, heater_enable, TEST_MODE,
   Resend_mechanism, TEST_DATA_MODE, BIAS_SUB_MODE, vhd_flag,
   timestamp2, DMS_Error, int_time, Rot_Angle, REF_XDet_W0,
   REF_XDet_W1, refc_state, Left_das_state, Right_das_state,
   dasi_sum_err, ZDFS_curr_fd, INV_Temp_reg7, HW_LINES, DET_TEMP_REG0,
   DET_TEMP_REG1, dasc_temp_L, dasc_temp_R, DMS_GRID_TEMP,
   DMS_GRID_STATUS, BED_Hor_Pos, APlane_Width, CTA_abort_sta,
   APlane_Pos, wedge_cnt, fov_cnt, ECG, HV_DC_Rail, HV_Grid_V1,
   HV_Grid_V2, HV_Fila_Cur, HV_MA, HV_KV, DOM_MA, ExpTimeStamp_low,
   ExpTimeStamp_high, Reserved_46, Reserved_47, ThyristorIemp,
   Tube_T2, Tube_T3, Tube_T4, Tube_T5, Tube_T6, Tube_T7, Tube_T8,
   Tube_T9, boundary_preset, conv_time_set, dms_err_New,
   Reading_Header_Rdy_Cmd, slice_sort_data_out,
   slice_sort_data_out_en, Fault_inject_en, slice_length_odd,
   slice_length_even, ldp_channel_num, channel_num, ldp_state_header,
   rdp_state_header,add_offset_flg,Slice_HD_Flg
   );

   //parameter                       SLICE_DATA_NUM = 704; 
   input                           clk;
   input                           RESET;
   input                           clk_1us;
   //input                           new_reading_in_qdr_flag_in  ;
   input                           MAKE_DATA  ;
   //input                           tx_channel_up_sysclk_in;
   input                           conv ;  
   input [8:0]                     slice_sel  ;
   input                           RP_back_en  ; //resend enable

   // compress 
   input                           Data_Compress ; //compress_en;
   input [1:0]                     compress_mode;
   input [9:0]             discard_chl_r;
   input [9:0]             compress_chl_r;
   input [9:0]             discard_chl_l;
   input [9:0]             compress_chl_l;

   //input             compress_en;

   input [7:0]                     DMS_Type;
   input [7:0]                     DDC_Range ;
   input [7:0]                     DAS_Mode;
   input [7:0]                     Scan_Mode;
                                   
   input [15:0]                    DMB_TEMP;
   input [15:0]                    DMS_Fan_Speed;
   input [47:0]                    Ltmp_FAN_TACH ;   
   input [47:0]                    Rtmp_FAN_TACH ;    
   input [47:0]                    Ltmp_sensor_out ;   
   input [47:0]                    Rtmp_sensor_out ;
                                   
   input                           heater_enable;
   input                           TEST_MODE ;
   input                           Resend_mechanism ;
   input [1:0]                     TEST_DATA_MODE;
   //input [7:0]               Test_mode_out ;
   input                           BIAS_SUB_MODE;
   input                           vhd_flag;
   input                           Slice_HD_Flg;
   input                           add_offset_flg;
                                   
   input [31:0]                    timestamp2;
   input [15:0]                    DMS_Error;
   input [15:0]                    int_time;
   input [15:0]                    Rot_Angle;
   input [15:0]                    REF_XDet_W0;
   input [15:0]                    REF_XDet_W1;
   input [15:0]                    refc_state;
   input [31:0]                    Left_das_state;
   input [31:0]                    Right_das_state;   
   input [28:0]                    dasi_sum_err;
                                   
   input [15:0]                    ZDFS_curr_fd;
   input [15:0]                    INV_Temp_reg7;
                                   
   input [15:0]                    HW_LINES;
   input [15:0]                    DET_TEMP_REG0;
   input [15:0]                    DET_TEMP_REG1;
   input [31:0]                    dasc_temp_L;
   input [31:0]                    dasc_temp_R;
                                   
   input [7:0]                     DMS_GRID_TEMP;
   input [7:0]                     DMS_GRID_STATUS;
                                   
   input [15:0]                    BED_Hor_Pos;
   input [15:0]                    APlane_Width ; //  --word 52 For H66 Prime
   input                           CTA_abort_sta; //  --word 12 bit8
   input [15:0]                    APlane_Pos ;   //  --word 54 For H66 Prime
                                   
   input [15:0]                    wedge_cnt;   //--word 73 For H66 Prime
   input [15:0]                    fov_cnt;   //--word 74 For H66 Prime
                                   
   input [15:0]                    ECG ;   //--word 55 For H66 Prime
     
   //--- For HV channels     
   input [15:0]                    HV_DC_Rail ; //        : in  std_logic_vector(15 downto 0);   --word 40 For H66 Prime
   input [15:0]                    HV_Grid_V1 ; //        : in  std_logic_vector(15 downto 0);   --word 43 For H66 Prime
   input [15:0]                    HV_Grid_V2 ; //        : in  std_logic_vector(15 downto 0);   --word 44 For H66 Prime
   input [15:0]                    HV_Fila_Cur ; //        : in  std_logic_vector(15 downto 0);   --word 49 For H66 Prime
   input [15:0]                    HV_MA ; //        : in  std_logic_vector(15 downto 0);   --word 50 For H66 Prime
   input [15:0]                    HV_KV ; //        : in  std_logic_vector(15 downto 0);   --word 51 For H66 Prime
   input [15:0]                    DOM_MA ; //        : in  std_logic_vector(15 downto 0);   --word 56 For H66 Prime 
   input [15:0]                    ExpTimeStamp_low ; //        : in  std_logic_vector(15 downto 0);   --word 41 For H66 Prime            
   input [15:0]                    ExpTimeStamp_high ; //        : in  std_logic_vector(15 downto 0);   --word 42 For H66 Prime          
   input [15:0]                    Reserved_46 ; //        : in  std_logic_vector(15 downto 0);   --word 46 For H66 Prime/H66/H64
   input [15:0]                    Reserved_47 ; //        : in  std_logic_vector(15 downto 0);   --word 47 For H66 Prime/H66/H64
   input [15:0]                     ThyristorIemp ; //         : in  std_logic_vector(15 downto 0);   --word 48 For H66 Prime
   input [15:0]                    Tube_T2 ; //        : in  std_logic_vector(15 downto 0);   --word 65 For H66 Prime
   input [15:0]                    Tube_T3 ; //        : in  std_logic_vector(15 downto 0);   --word 66 For H66 Prime  
   input [15:0]                    Tube_T4 ; //        : in  std_logic_vector(15 downto 0);   --word 67 For H66 Prime
   input [15:0]                    Tube_T5 ; //        : in  std_logic_vector(15 downto 0);   --word 68 For H66 Prime
   input [15:0]                    Tube_T6 ; //        : in  std_logic_vector(15 downto 0);   --word 69 For H66 Prime
   input [15:0]                    Tube_T7 ; //        : in  std_logic_vector(15 downto 0);   --word 70 For H66 Prime  
   input [15:0]                    Tube_T8 ; //        : in  std_logic_vector(15 downto 0);   --word 71 For H66 Prime
   input [15:0]                    Tube_T9 ; //        : in  std_logic_vector(15 downto 0);   --word 72 For H66 Prime   
                                   
   input [15:0]                    boundary_preset ; //         : in  std_logic_vector(15 downto 0);
   input [15:0]                    conv_time_set ;
   input [95:0]                    dms_err_New;
   
   input                           Reading_Header_Rdy_Cmd ; //      : in  std_logic;
  
   input [127:0]           slice_sort_data_out;
   input                   slice_sort_data_out_en;
   
   //input [127:0] all_SLICE_DATA128bit_in; 
   //input   all_SLICE_DATA128bit_en_in;
   //input   DATA_FROM_DDR_en ;
   //output [127:0] DATA_FROM_DDR_dd ;
   
   output [127:0]          header_data_out;
   output                  header_data_out_en;
   
   
   output                           DOM_header_latch_pulse_en ; 
   output [31:0]                    reading_number ; //           : out std_logic_vector(31 downto 0);
   output [15:0]                    TablePos ; //           : out std_logic_vector(15 downto 0);
   output [15:0]                    REF_XDetA ; //           : out std_logic_vector(15 downto 0);
   output [15:0]                    REF_XDetB ; //           : out std_logic_vector(15 downto 0);
   
   output [31:0]                   wr_qdr_reading_num ; //   : out std_logic_vector(15 downto 0);
   output                          wr_number_err;
   output                          make_data_on ; //   : out std_logic;
   output                          view_Reading_Done ; //   : out std_logic;
   output                          sampling_data_on_out ; //       : out std_logic;
   output                          conv_edge_out ; //   : out std_logic;
   //input                           last_view_retran_end_in  ; //     :in STD_LOGIC;
   output                          last_view_wr_done;
   
   //output  lastview_wr_Sampling_done_out ; // :out STD_LOGIC; 
   output                          time_2000us_en_out ; // :out STD_LOGIC;   
   output                          view_header_overrun ; // :out STD_LOGIC;
   output                          rx_fifo_empty;
   
   //output                          view_header_warning ; // :out STD_LOGIC;   
   output                          FirstViewFlag_reg_out ; // :out STD_LOGIC;   
   output                          LastViewFlag_reg_out ; // :out STD_LOGIC;   
   output [31:0]                   header_tp ; // : out std_logic
   
   //output [31:0] Wrqdr_slice_counter_in;
   output [31:0]           wr_view_counter;
   
   input                   Fault_inject_en;

   input [11:0]            slice_length_odd;
   input [11:0]            slice_length_even;

   input [10:0]            ldp_channel_num;
   input [10:0]            channel_num;

   input [7:0]             ldp_state_header;
   input [7:0]             rdp_state_header;
   
   output [3:0]            header_state;
   
   wire      fault_s_crc_inject    = Fault_inject_en;
   
   
   ///*AUTOREGINPUT */

   ///*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire [15:0]                     HEADER_000;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_001;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_002;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_003;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_004;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_005;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_006;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_007;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_008;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_009;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_010;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_011;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_012;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_013;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_014;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_015;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_016;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_017;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_018;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_019;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_020;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_021;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_022;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_023;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_024;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_025;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_026;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_027;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_028;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_029;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_030;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_031;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_032;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_033;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_034;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_035;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_036;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_037;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_038;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_039;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_040;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_041;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_042;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_043;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_044;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_045;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_046;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_047;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_048;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_049;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_050;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_051;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_052;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_053;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_054;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_055;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_056;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_057;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_058;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_059;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_060;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_061;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_062;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_063;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_064;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_065;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_066;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_067;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_068;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_069;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_070;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_071;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_072;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_073;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_074;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_075;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_076;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_077;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_078;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_079;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_080;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_081;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_082;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_083;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_084;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_085;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_086;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_087;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_088;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_089;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_090;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_091;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_092;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_093;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_094;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_095;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_096;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_097;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_098;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_099;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_100;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_101;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_102;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_103;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_104;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_105;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_106;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_107;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_108;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_109;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_110;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_111;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_112;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_113;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_114;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_115;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_116;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_117;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_118;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_119;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_120;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_121;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_122;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_123;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_124;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_125;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_126;     // From header_parameter of header_parameter.v
   wire [15:0]                     HEADER_127;     // From header_parameter of header_parameter.v
   wire                            LastViewFlag_reg_out;   // From header_parameter of header_parameter.v
   wire [15:0]                     crc_0_in;       // From header_frame_gen of header_frame_gen.v
   wire [15:0]                     crc_1_in;       // From header_frame_gen of header_frame_gen.v
   wire [15:0]                     crc_2_in;       // From header_frame_gen of header_frame_gen.v
   wire [15:0]                     crc_3_in;       // From header_frame_gen of header_frame_gen.v
   wire                            crc_clear;      // From header_frame_gen of header_frame_gen.v
   wire                            crc_en;         // From header_frame_gen of header_frame_gen.v
   wire                            make_data_p_edge;   // From header_parameter of header_parameter.v
   wire                            rx_fifo_rd_en;      // From header_frame_gen of header_frame_gen.v
   // End of automatics
   wire [15:0]                     crc_0_out;      // From header_frame_gen of header_frame_gen.v
   wire [15:0]                     crc_1_out;      // From header_frame_gen of header_frame_gen.v
   wire [15:0]                     crc_2_out;      // From header_frame_gen of header_frame_gen.v
   wire [15:0]                     crc_3_out;      // From header_frame_gen of header_frame_gen.v
   wire [127:0]                     rx_fifo_dout;
  
   wire                            read_header_rst;

   assign       read_header_rst = make_data_p_edge | RESET;
   
   
   
   
   header_frame_gen                                                                        
     header_frame_gen(.RESET                          (read_header_rst),
                      ///*AUTOINST*/
                      // Outputs
                      .rx_fifo_rd_en                  (rx_fifo_rd_en),
                      .header_data_out                (header_data_out),
                      .header_data_out_en             (header_data_out_en),
                      .crc_clear                      (crc_clear),
                      .crc_en                         (crc_en),
                      .crc_0_in                       (crc_0_in[15:0]),
                      .crc_1_in                       (crc_1_in[15:0]),
                      .crc_2_in                       (crc_2_in[15:0]),
                      .crc_3_in                       (crc_3_in[15:0]),
                      .view_Reading_Done              (view_Reading_Done),
                      .header_tp                      (header_tp),
                      .header_state                   (header_state),
                      .wr_view_counter                (wr_view_counter[31:0]),
                      // Inputs                       
                      .clk                            (clk),
                      .rx_fifo_dout                   (rx_fifo_dout[127:0]),
                      .rx_fifo_empty                  (rx_fifo_empty),
                      .crc_0_out                      (crc_0_out[15:0]),
                      .crc_1_out                      (crc_1_out[15:0]),
                      .crc_2_out                      (crc_2_out[15:0]),
                      .crc_3_out                      (crc_3_out[15:0]),
                      .slice_sel                      (slice_sel[8:0]),
                      .make_data_p_edge               (make_data_p_edge),
                      .fault_s_crc_inject             (fault_s_crc_inject),
                      .slice_length_odd               (slice_length_odd),
                      .slice_length_even              (slice_length_even),
                      .HEADER_000                     (HEADER_000[15:0]),
                      .HEADER_001                     (HEADER_001[15:0]),
                      .HEADER_002                     (HEADER_002[15:0]),
                      .HEADER_003                     (HEADER_003[15:0]),
                      .HEADER_004                     (HEADER_004[15:0]),
                      .HEADER_005                     (HEADER_005[15:0]),
                      .HEADER_006                     (HEADER_006[15:0]),
                      .HEADER_007                     (HEADER_007[15:0]),
                      .HEADER_008                     (HEADER_008[15:0]),
                      .HEADER_009                     (HEADER_009[15:0]),
                      .HEADER_010                     (HEADER_010[15:0]),
                      .HEADER_011                     (HEADER_011[15:0]),
                      .HEADER_012                     (HEADER_012[15:0]),
                      .HEADER_013                     (HEADER_013[15:0]),
                      .HEADER_014                     (HEADER_014[15:0]),
                      .HEADER_015                     (HEADER_015[15:0]),
                      .HEADER_016                     (HEADER_016[15:0]),
                      .HEADER_017                     (HEADER_017[15:0]),
                      .HEADER_018                     (HEADER_018[15:0]),
                      .HEADER_019                     (HEADER_019[15:0]),
                      .HEADER_020                     (HEADER_020[15:0]),
                      .HEADER_021                     (HEADER_021[15:0]),
                      .HEADER_022                     (HEADER_022[15:0]),
                      .HEADER_023                     (HEADER_023[15:0]),
                      .HEADER_024                     (HEADER_024[15:0]),
                      .HEADER_025                     (HEADER_025[15:0]),
                      .HEADER_026                     (HEADER_026[15:0]),
                      .HEADER_027                     (HEADER_027[15:0]),
                      .HEADER_028                     (HEADER_028[15:0]),
                      .HEADER_029                     (HEADER_029[15:0]),
                      .HEADER_030                     (HEADER_030[15:0]),
                      .HEADER_031                     (HEADER_031[15:0]),
                      .HEADER_032                     (HEADER_032[15:0]),
                      .HEADER_033                     (HEADER_033[15:0]),
                      .HEADER_034                     (HEADER_034[15:0]),
                      .HEADER_035                     (HEADER_035[15:0]),
                      .HEADER_036                     (HEADER_036[15:0]),
                      .HEADER_037                     (HEADER_037[15:0]),
                      .HEADER_038                     (HEADER_038[15:0]),
                      .HEADER_039                     (HEADER_039[15:0]),
                      .HEADER_040                     (HEADER_040[15:0]),
                      .HEADER_041                     (HEADER_041[15:0]),
                      .HEADER_042                     (HEADER_042[15:0]),
                      .HEADER_043                     (HEADER_043[15:0]),
                      .HEADER_044                     (HEADER_044[15:0]),
                      .HEADER_045                     (HEADER_045[15:0]),
                      .HEADER_046                     (HEADER_046[15:0]),
                      .HEADER_047                     (HEADER_047[15:0]),
                      .HEADER_048                     (HEADER_048[15:0]),
                      .HEADER_049                     (HEADER_049[15:0]),
                      .HEADER_050                     (HEADER_050[15:0]),
                      .HEADER_051                     (HEADER_051[15:0]),
                      .HEADER_052                     (HEADER_052[15:0]),
                      .HEADER_053                     (HEADER_053[15:0]),
                      .HEADER_054                     (HEADER_054[15:0]),
                      .HEADER_055                     (HEADER_055[15:0]),
                      .HEADER_056                     (HEADER_056[15:0]),
                      .HEADER_057                     (HEADER_057[15:0]),
                      .HEADER_058                     (HEADER_058[15:0]),
                      .HEADER_059                     (HEADER_059[15:0]),
                      .HEADER_060                     (HEADER_060[15:0]),
                      .HEADER_061                     (HEADER_061[15:0]),
                      .HEADER_062                     (HEADER_062[15:0]),
                      .HEADER_063                     (HEADER_063[15:0]),
                      .HEADER_064                     (HEADER_064[15:0]),
                      .HEADER_065                     (HEADER_065[15:0]),
                      .HEADER_066                     (HEADER_066[15:0]),
                      .HEADER_067                     (HEADER_067[15:0]),
                      .HEADER_068                     (HEADER_068[15:0]),
                      .HEADER_069                     (HEADER_069[15:0]),
                      .HEADER_070                     (HEADER_070[15:0]),
                      .HEADER_071                     (HEADER_071[15:0]),
                      .HEADER_072                     (HEADER_072[15:0]),
                      .HEADER_073                     (HEADER_073[15:0]),
                      .HEADER_074                     (HEADER_074[15:0]),
                      .HEADER_075                     (HEADER_075[15:0]),
                      .HEADER_076                     (HEADER_076[15:0]),
                      .HEADER_077                     (HEADER_077[15:0]),
                      .HEADER_078                     (HEADER_078[15:0]),
                      .HEADER_079                     (HEADER_079[15:0]),
                      .HEADER_080                     (HEADER_080[15:0]),
                      .HEADER_081                     (HEADER_081[15:0]),
                      .HEADER_082                     (HEADER_082[15:0]),
                      .HEADER_083                     (HEADER_083[15:0]),
                      .HEADER_084                     (HEADER_084[15:0]),
                      .HEADER_085                     (HEADER_085[15:0]),
                      .HEADER_086                     (HEADER_086[15:0]),
                      .HEADER_087                     (HEADER_087[15:0]),
                      .HEADER_088                     (HEADER_088[15:0]),
                      .HEADER_089                     (HEADER_089[15:0]),
                      .HEADER_090                     (HEADER_090[15:0]),
                      .HEADER_091                     (HEADER_091[15:0]),
                      .HEADER_092                     (HEADER_092[15:0]),
                      .HEADER_093                     (HEADER_093[15:0]),
                      .HEADER_094                     (HEADER_094[15:0]),
                      .HEADER_095                     (HEADER_095[15:0]),
                      .HEADER_096                     (HEADER_096[15:0]),
                      .HEADER_097                     (HEADER_097[15:0]),
                      .HEADER_098                     (HEADER_098[15:0]),
                      .HEADER_099                     (HEADER_099[15:0]),
                      .HEADER_100                     (HEADER_100[15:0]),
                      .HEADER_101                     (HEADER_101[15:0]),
                      .HEADER_102                     (HEADER_102[15:0]),
                      .HEADER_103                     (HEADER_103[15:0]),
                      .HEADER_104                     (HEADER_104[15:0]),
                      .HEADER_105                     (HEADER_105[15:0]),
                      .HEADER_106                     (HEADER_106[15:0]),
                      .HEADER_107                     (HEADER_107[15:0]),
                      .HEADER_108                     (HEADER_108[15:0]),
                      .HEADER_109                     (HEADER_109[15:0]),
                      .HEADER_110                     (HEADER_110[15:0]),
                      .HEADER_111                     (HEADER_111[15:0]),
                      .HEADER_112                     (HEADER_112[15:0]),
                      .HEADER_113                     (HEADER_113[15:0]),
                      .HEADER_114                     (HEADER_114[15:0]),
                      .HEADER_115                     (HEADER_115[15:0]),
                      .HEADER_116                     (HEADER_116[15:0]),
                      .HEADER_117                     (HEADER_117[15:0]),
                      .HEADER_118                     (HEADER_118[15:0]),
                      .HEADER_119                     (HEADER_119[15:0]),
                      .HEADER_120                     (HEADER_120[15:0]),
                      .HEADER_121                     (HEADER_121[15:0]),
                      .HEADER_122                     (HEADER_122[15:0]),
                      .HEADER_123                     (HEADER_123[15:0]),
                      .HEADER_124                     (HEADER_124[15:0]),
                      .HEADER_125                     (HEADER_125[15:0]),
                      .HEADER_126                     (HEADER_126[15:0]),
                      .HEADER_127                     (HEADER_127[15:0]));

   
        
                 
                    
   
   
    header_parameter   
                         
                    header_parameter (/*AUTOINST*/
                      // Outputs
                      .sampling_data_on_out(sampling_data_on_out),
                      .LastViewFlag_reg_out(LastViewFlag_reg_out),
                      .make_data_on (make_data_on),
                      .TablePos     (TablePos[15:0]),
                      .REF_XDetA    (REF_XDetA[15:0]),
                      .REF_XDetB    (REF_XDetB[15:0]),
                      .conv_edge_out    (conv_edge_out),
                      .reading_number   (reading_number[31:0]),
                      .FirstViewFlag_reg_out(FirstViewFlag_reg_out),
                      .DOM_header_latch_pulse_en(DOM_header_latch_pulse_en),
                      .wr_qdr_reading_num(wr_qdr_reading_num[31:0]),
                      .wr_number_err    (wr_number_err),
                      .time_2000us_en_out(time_2000us_en_out),
                      .last_view_wr_done(last_view_wr_done),
                      .make_data_p_edge (make_data_p_edge),
                      .HEADER_000   (HEADER_000[15:0]),
                      .HEADER_001   (HEADER_001[15:0]),
                      .HEADER_002   (HEADER_002[15:0]),
                      .HEADER_003   (HEADER_003[15:0]),
                      .HEADER_004   (HEADER_004[15:0]),
                      .HEADER_005   (HEADER_005[15:0]),
                      .HEADER_006   (HEADER_006[15:0]),
                      .HEADER_007   (HEADER_007[15:0]),
                      .HEADER_008   (HEADER_008[15:0]),
                      .HEADER_009   (HEADER_009[15:0]),
                      .HEADER_010   (HEADER_010[15:0]),
                      .HEADER_011   (HEADER_011[15:0]),
                      .HEADER_012   (HEADER_012[15:0]),
                      .HEADER_013   (HEADER_013[15:0]),
                      .HEADER_014   (HEADER_014[15:0]),
                      .HEADER_015   (HEADER_015[15:0]),
                      .HEADER_016   (HEADER_016[15:0]),
                      .HEADER_017   (HEADER_017[15:0]),
                      .HEADER_018   (HEADER_018[15:0]),
                      .HEADER_019   (HEADER_019[15:0]),
                      .HEADER_020   (HEADER_020[15:0]),
                      .HEADER_021   (HEADER_021[15:0]),
                      .HEADER_022   (HEADER_022[15:0]),
                      .HEADER_023   (HEADER_023[15:0]),
                      .HEADER_024   (HEADER_024[15:0]),
                      .HEADER_025   (HEADER_025[15:0]),
                      .HEADER_026   (HEADER_026[15:0]),
                      .HEADER_027   (HEADER_027[15:0]),
                      .HEADER_028   (HEADER_028[15:0]),
                      .HEADER_029   (HEADER_029[15:0]),
                      .HEADER_030   (HEADER_030[15:0]),
                      .HEADER_031   (HEADER_031[15:0]),
                      .HEADER_032   (HEADER_032[15:0]),
                      .HEADER_033   (HEADER_033[15:0]),
                      .HEADER_034   (HEADER_034[15:0]),
                      .HEADER_035   (HEADER_035[15:0]),
                      .HEADER_036   (HEADER_036[15:0]),
                      .HEADER_037   (HEADER_037[15:0]),
                      .HEADER_038   (HEADER_038[15:0]),
                      .HEADER_039   (HEADER_039[15:0]),
                      .HEADER_040   (HEADER_040[15:0]),
                      .HEADER_041   (HEADER_041[15:0]),
                      .HEADER_042   (HEADER_042[15:0]),
                      .HEADER_043   (HEADER_043[15:0]),
                      .HEADER_044   (HEADER_044[15:0]),
                      .HEADER_045   (HEADER_045[15:0]),
                      .HEADER_046   (HEADER_046[15:0]),
                      .HEADER_047   (HEADER_047[15:0]),
                      .HEADER_048   (HEADER_048[15:0]),
                      .HEADER_049   (HEADER_049[15:0]),
                      .HEADER_050   (HEADER_050[15:0]),
                      .HEADER_051   (HEADER_051[15:0]),
                      .HEADER_052   (HEADER_052[15:0]),
                      .HEADER_053   (HEADER_053[15:0]),
                      .HEADER_054   (HEADER_054[15:0]),
                      .HEADER_055   (HEADER_055[15:0]),
                      .HEADER_056   (HEADER_056[15:0]),
                      .HEADER_057   (HEADER_057[15:0]),
                      .HEADER_058   (HEADER_058[15:0]),
                      .HEADER_059   (HEADER_059[15:0]),
                      .HEADER_060   (HEADER_060[15:0]),
                      .HEADER_061   (HEADER_061[15:0]),
                      .HEADER_062   (HEADER_062[15:0]),
                      .HEADER_063   (HEADER_063[15:0]),
                      .HEADER_064   (HEADER_064[15:0]),
                      .HEADER_065   (HEADER_065[15:0]),
                      .HEADER_066   (HEADER_066[15:0]),
                      .HEADER_067   (HEADER_067[15:0]),
                      .HEADER_068   (HEADER_068[15:0]),
                      .HEADER_069   (HEADER_069[15:0]),
                      .HEADER_070   (HEADER_070[15:0]),
                      .HEADER_071   (HEADER_071[15:0]),
                      .HEADER_072   (HEADER_072[15:0]),
                      .HEADER_073   (HEADER_073[15:0]),
                      .HEADER_074   (HEADER_074[15:0]),
                      .HEADER_075   (HEADER_075[15:0]),
                      .HEADER_076   (HEADER_076[15:0]),
                      .HEADER_077   (HEADER_077[15:0]),
                      .HEADER_078   (HEADER_078[15:0]),
                      .HEADER_079   (HEADER_079[15:0]),
                      .HEADER_080   (HEADER_080[15:0]),
                      .HEADER_081   (HEADER_081[15:0]),
                      .HEADER_082   (HEADER_082[15:0]),
                      .HEADER_083   (HEADER_083[15:0]),
                      .HEADER_084   (HEADER_084[15:0]),
                      .HEADER_085   (HEADER_085[15:0]),
                      .HEADER_086   (HEADER_086[15:0]),
                      .HEADER_087   (HEADER_087[15:0]),
                      .HEADER_088   (HEADER_088[15:0]),
                      .HEADER_089   (HEADER_089[15:0]),
                      .HEADER_090   (HEADER_090[15:0]),
                      .HEADER_091   (HEADER_091[15:0]),
                      .HEADER_092   (HEADER_092[15:0]),
                      .HEADER_093   (HEADER_093[15:0]),
                      .HEADER_094   (HEADER_094[15:0]),
                      .HEADER_095   (HEADER_095[15:0]),
                      .HEADER_096   (HEADER_096[15:0]),
                      .HEADER_097   (HEADER_097[15:0]),
                      .HEADER_098   (HEADER_098[15:0]),
                      .HEADER_099   (HEADER_099[15:0]),
                      .HEADER_100   (HEADER_100[15:0]),
                      .HEADER_101   (HEADER_101[15:0]),
                      .HEADER_102   (HEADER_102[15:0]),
                      .HEADER_103   (HEADER_103[15:0]),
                      .HEADER_104   (HEADER_104[15:0]),
                      .HEADER_105   (HEADER_105[15:0]),
                      .HEADER_106   (HEADER_106[15:0]),
                      .HEADER_107   (HEADER_107[15:0]),
                      .HEADER_108   (HEADER_108[15:0]),
                      .HEADER_109   (HEADER_109[15:0]),
                      .HEADER_110   (HEADER_110[15:0]),
                      .HEADER_111   (HEADER_111[15:0]),
                      .HEADER_112   (HEADER_112[15:0]),
                      .HEADER_113   (HEADER_113[15:0]),
                      .HEADER_114   (HEADER_114[15:0]),
                      .HEADER_115   (HEADER_115[15:0]),
                      .HEADER_116   (HEADER_116[15:0]),
                      .HEADER_117   (HEADER_117[15:0]),
                      .HEADER_118   (HEADER_118[15:0]),
                      .HEADER_119   (HEADER_119[15:0]),
                      .HEADER_120   (HEADER_120[15:0]),
                      .HEADER_121   (HEADER_121[15:0]),
                      .HEADER_122   (HEADER_122[15:0]),
                      .HEADER_123   (HEADER_123[15:0]),
                      .HEADER_124   (HEADER_124[15:0]),
                      .HEADER_125   (HEADER_125[15:0]),
                      .HEADER_126   (HEADER_126[15:0]),
                      .HEADER_127   (HEADER_127[15:0]),
                      // Inputs
                      .clk      (clk),
                      .RESET        (RESET),
                      .clk_1us      (clk_1us),
                      .MAKE_DATA    (MAKE_DATA),
                      .conv     (conv),
                      .slice_sel    (slice_sel[8:0]),
                      .RP_back_en   (RP_back_en),
                      .Data_Compress    (Data_Compress),
                      .compress_mode    (compress_mode[1:0]),
                      .discard_chl_r    (discard_chl_r[9:0]),
                      .compress_chl_r   (compress_chl_r[9:0]),
                      .discard_chl_l    (discard_chl_l[9:0]),
                      .compress_chl_l   (compress_chl_l[9:0]),
                      .DMS_Type     (DMS_Type[7:0]),
                      .DDC_Range    (DDC_Range[7:0]),
                      .DAS_Mode     (DAS_Mode[7:0]),
                      .Scan_Mode    (Scan_Mode[7:0]),
                      .DMB_TEMP     (DMB_TEMP[15:0]),
                      .DMS_Fan_Speed    (DMS_Fan_Speed[15:0]),
                      .Ltmp_FAN_TACH    (Ltmp_FAN_TACH[47:0]),
                      .Rtmp_FAN_TACH    (Rtmp_FAN_TACH[47:0]),
                      .Ltmp_sensor_out  (Ltmp_sensor_out[47:0]),
                      .Rtmp_sensor_out  (Rtmp_sensor_out[47:0]),
                      .heater_enable    (heater_enable),
                      .TEST_MODE    (TEST_MODE),
                      .Resend_mechanism (Resend_mechanism),
                      .TEST_DATA_MODE   (TEST_DATA_MODE[1:0]),
                      .BIAS_SUB_MODE    (BIAS_SUB_MODE),
                      .vhd_flag         (vhd_flag      ),
                      .Slice_HD_Flg     (Slice_HD_Flg  ), 
                      .add_offset_flg   (add_offset_flg),
                      .timestamp2   (timestamp2[31:0]),
                      .DMS_Error    (DMS_Error[15:0]),
                      .int_time     (int_time[15:0]),
                      .Rot_Angle    (Rot_Angle[15:0]),
                      .REF_XDet_W0  (REF_XDet_W0[15:0]),
                      .REF_XDet_W1  (REF_XDet_W1[15:0]),
                      .refc_state   (refc_state[15:0]),
                      .Left_das_state   (Left_das_state[31:0]),
                      .Right_das_state  (Right_das_state[31:0]),
                      .dasi_sum_err (dasi_sum_err[28:0]),
                      .ZDFS_curr_fd (ZDFS_curr_fd[15:0]),
                      .INV_Temp_reg7    (INV_Temp_reg7[15:0]),
                      .HW_LINES     (HW_LINES[15:0]),
                      .DET_TEMP_REG0    (DET_TEMP_REG0[15:0]),
                      .DET_TEMP_REG1    (DET_TEMP_REG1[15:0]),
                      .dasc_temp_L  (dasc_temp_L[31:0]),
                      .dasc_temp_R  (dasc_temp_R[31:0]),
                      .DMS_GRID_TEMP    (DMS_GRID_TEMP[7:0]),
                      .DMS_GRID_STATUS  (DMS_GRID_STATUS[7:0]),
                      .BED_Hor_Pos  (BED_Hor_Pos[15:0]),
                      .APlane_Width (APlane_Width[15:0]),
                      .CTA_abort_sta    (CTA_abort_sta),
                      .APlane_Pos   (APlane_Pos[15:0]),
                      .wedge_cnt    (wedge_cnt[15:0]),
                      .fov_cnt      (fov_cnt[15:0]),
                      .ECG      (ECG[15:0]),
                      .HV_DC_Rail   (HV_DC_Rail[15:0]),
                      .HV_Grid_V1   (HV_Grid_V1[15:0]),
                      .HV_Grid_V2   (HV_Grid_V2[15:0]),
                      .HV_Fila_Cur  (HV_Fila_Cur[15:0]),
                      .HV_MA        (HV_MA[15:0]),
                      .HV_KV        (HV_KV[15:0]),
                      .DOM_MA       (DOM_MA[15:0]),
                      .ExpTimeStamp_low (ExpTimeStamp_low[15:0]),
                      .ExpTimeStamp_high(ExpTimeStamp_high[15:0]),
                      .Reserved_46  (Reserved_46[15:0]),
                      .Reserved_47  (Reserved_47[15:0]),
                      .ThyristorIemp    (ThyristorIemp[15:0]),
                      .Tube_T2      (Tube_T2[15:0]),
                      .Tube_T3      (Tube_T3[15:0]),
                      .Tube_T4      (Tube_T4[15:0]),
                      .Tube_T5      (Tube_T5[15:0]),
                      .Tube_T6      (Tube_T6[15:0]),
                      .Tube_T7      (Tube_T7[15:0]),
                      .Tube_T8      (Tube_T8[15:0]),
                      .Tube_T9      (Tube_T9[15:0]),
                      .conv_time_set    (conv_time_set[15:0]),
                      .dms_err_New  (dms_err_New[95:0]),
                      .boundary_preset  (boundary_preset[15:0]),
                      .ldp_channel_num  (ldp_channel_num[10:0]),
                      .channel_num  (channel_num[10:0]),
                      .ldp_state_header (ldp_state_header[7:0]),
                      .rdp_state_header (rdp_state_header[7:0]),
                      .Reading_Header_Rdy_Cmd(Reading_Header_Rdy_Cmd),
                      .view_Reading_Done(view_Reading_Done));


   CRC_16_header_data        CRC_0_uut(
                                      // Outputs
                                      .CRC_CODE                       (crc_0_out[15:0]),
                                      // Inputs                       
                                      .Clk                            (clk),
                                      .Reset                          (read_header_rst),
                                      .CRC_Clear                      (crc_clear),
                                      .CRC_En                         (crc_en),
                                      .DataIn                         (crc_0_in[15:0]));
   
   CRC_16_header_data        CRC_1_uut(
                                      // Outputs
                                      .CRC_CODE                       (crc_1_out[15:0]),
                                      // Inputs                       
                                      .Clk                            (clk),
                                      .Reset                          (read_header_rst),
                                      .CRC_Clear                      (crc_clear),
                                      .CRC_En                         (crc_en),
                                      .DataIn                         (crc_1_in[15:0]));
   
   
   CRC_16_header_data        CRC_2_uut(
                                      // Outputs
                                      .CRC_CODE                       (crc_2_out[15:0]),
                                      // Inputs                       
                                      .Clk                            (clk),
                                      .Reset                          (read_header_rst),
                                      .CRC_Clear                      (crc_clear),
                                      .CRC_En                         (crc_en),
                                      .DataIn                         (crc_2_in[15:0]));
   
   
   CRC_16_header_data        CRC_3_uut(
                                      // Outputs
                                      .CRC_CODE                       (crc_3_out[15:0]),
                                      // Inputs                       
                                      .Clk                            (clk),
                                      .Reset                          (read_header_rst),
                                      .CRC_Clear                      (crc_clear),
                                      .CRC_En                         (crc_en),
                                      .DataIn                         (crc_3_in[15:0]));
   

    
  
   header_rx_fifo   header_rx_fifo(
                                     // Outputs
                                     .dout                            (rx_fifo_dout),
                                     .full                            (full),
                                     .empty                           (rx_fifo_empty),
                                     // Inputs                        
                                     .rst                             (read_header_rst),
                                     .wr_clk                          (clk), 
                                     .rd_clk                          (clk), //may be change ddr user clock 
                                     .din                             (slice_sort_data_out),
                                     //.din                             (slice_sort_data_out),
                                     .wr_en                           (slice_sort_data_out_en),
                                     .rd_en                           (rx_fifo_rd_en));


   //monitor FIFO underflow and overflow 
   reg      view_header_overrun; // overflow    
   //reg        view_header_warning; // underflow   
   
   always @(posedge clk) begin
      if(RESET) begin
        view_header_overrun   <= 'h0;
      end
      else if(make_data_p_edge) begin
        view_header_overrun   <= 'h0;
      end
      else if (full && slice_sort_data_out_en) begin
        view_header_overrun   <= 'h1;
      end
   end
   
   
endmodule // reading_header_slice_gen






