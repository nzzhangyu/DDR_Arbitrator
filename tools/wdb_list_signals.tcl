set wdb_path {D:/FPGA/DDR_native/DDR_native.sim/sim_1/behav/xsim/tb_ddr4_controller_mock_behav.wdb}
puts "Opening WDB: $wdb_path"
open_wave_database -noautoloadwcfg $wdb_path

puts "Top app/native signals:"
foreach pat {
    /tb_ddr4_controller_mock/app_rdy
    /tb_ddr4_controller_mock/app_en
    /tb_ddr4_controller_mock/app_cmd
    /tb_ddr4_controller_mock/app_addr
    /tb_ddr4_controller_mock/app_wdf_rdy
    /tb_ddr4_controller_mock/app_wdf_wren
    /tb_ddr4_controller_mock/app_wdf_end
    /tb_ddr4_controller_mock/app_rd_data_valid
    /tb_ddr4_controller_mock/init_calib_complete
    /tb_ddr4_controller_mock/ui_clk_sync_rst
    /tb_ddr4_controller_mock/dut/rw_state
    /tb_ddr4_controller_mock/dut/write_data_fire
    /tb_ddr4_controller_mock/dut/app_cmd_fire
    /tb_ddr4_controller_mock/dut/ddr_wr_fifo_level
    /tb_ddr4_controller_mock/dut/ddr_rd_fifo_level
} {
    set objs [get_objects -quiet $pat]
    puts "$pat -> $objs"
}

puts "Objects containing app_rdy under MIG:"
set mig_objs [get_objects -r -quiet -regexp {.*/mig_u/.*app.*rdy.*}]
puts [join [lrange $mig_objs 0 100] "\n"]

puts "Objects containing refresh/app/rdy under MIG top:"
set misc_objs [get_objects -r -quiet -regexp {.*/mig_u/.*(ref|refresh|rdy|app_en|cmd).*}]
puts [join [lrange $misc_objs 0 200] "\n"]

quit
