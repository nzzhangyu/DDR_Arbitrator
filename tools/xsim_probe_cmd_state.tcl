proc gv {sig {radix unsigned}} {
    set obj [get_objects -quiet $sig]
    if {[llength $obj] == 0} { return "<missing>" }
    return [get_value -radix $radix $obj]
}

proc dump {label} {
    puts "---- $label @ [current_time -s] ----"
    foreach sig {
        /tb_ddr4_controller_mock/app_cmd
        /tb_ddr4_controller_mock/app_en
        /tb_ddr4_controller_mock/app_rdy
        /tb_ddr4_controller_mock/app_wdf_rdy
        /tb_ddr4_controller_mock/app_wdf_wren
        /tb_ddr4_controller_mock/app_wdf_end
        /tb_ddr4_controller_mock/dut/user_rw_cmd_gen_uut/rw_state
        /tb_ddr4_controller_mock/dut/user_rw_cmd_gen_uut/write_beat_cnt
        /tb_ddr4_controller_mock/dut/user_rw_cmd_gen_uut/write_burst_len
        /tb_ddr4_controller_mock/dut/user_rw_cmd_gen_uut/wr_fifo_valid
        /tb_ddr4_controller_mock/dut/user_rw_cmd_gen_uut/app_cmd_fire
        /tb_ddr4_controller_mock/dut/user_rw_cmd_gen_uut/write_data_fire
        /tb_ddr4_controller_mock/dut/user_rw_cmd_gen_uut/wr_level_urgent
        /tb_ddr4_controller_mock/dut/user_rw_cmd_gen_uut/ddr_wr_req
        /tb_ddr4_controller_mock/dut/ddr_wr_fifo_level
    } {
        puts "$sig = [gv $sig]"
    }
}

run 6 us
dump "6us"
run 500 ns
dump "6.5us"
run 500 ns
dump "7us"
run 1 us
dump "8us"
quit
