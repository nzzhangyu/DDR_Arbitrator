proc show_values {label} {
    puts "---- $label @ [current_time -s] ----"
    set sigs {
        /tb_ddr4_controller_mock/init_calib_complete
        /tb_ddr4_controller_mock/ui_clk_sync_rst
        /tb_ddr4_controller_mock/app_cmd
        /tb_ddr4_controller_mock/app_en
        /tb_ddr4_controller_mock/app_rdy
        /tb_ddr4_controller_mock/app_wdf_rdy
        /tb_ddr4_controller_mock/app_wdf_wren
        /tb_ddr4_controller_mock/app_wdf_end
        /tb_ddr4_controller_mock/app_rd_data_valid
        /tb_ddr4_controller_mock/native_write_cmd_fire
        /tb_ddr4_controller_mock/native_read_cmd_fire
        /tb_ddr4_controller_mock/dut/user_rw_cmd_gen_u/rw_state
        /tb_ddr4_controller_mock/dut/user_rw_cmd_gen_u/write_beat_cnt
        /tb_ddr4_controller_mock/dut/user_rw_cmd_gen_u/write_burst_len
        /tb_ddr4_controller_mock/dut/user_rw_cmd_gen_u/read_beat_cnt
        /tb_ddr4_controller_mock/dut/user_rw_cmd_gen_u/read_burst_len
        /tb_ddr4_controller_mock/dut/user_rw_cmd_gen_u/wr_fifo_valid
        /tb_ddr4_controller_mock/dut/user_rw_cmd_gen_u/app_cmd_fire
        /tb_ddr4_controller_mock/dut/user_rw_cmd_gen_u/write_data_fire
        /tb_ddr4_controller_mock/dut/user_rw_cmd_gen_u/wr_level_urgent
        /tb_ddr4_controller_mock/dut/user_rw_cmd_gen_u/rd_level_high
        /tb_ddr4_controller_mock/dut/ddr_wr_fifo_level
        /tb_ddr4_controller_mock/dut/ddr_rd_fifo_level
    }
    foreach sig $sigs {
        set obj [get_objects -quiet $sig]
        if {[llength $obj] == 0} {
            puts "$sig = <missing>"
        } else {
            report_values -radix unsigned $obj
        }
    }
}

puts "Probe available objects"
puts [get_objects -quiet /tb_ddr4_controller_mock/app_rdy]
puts [get_objects -quiet /tb_ddr4_controller_mock/dut/user_rw_cmd_gen_u/rw_state]

run 24 us
show_values "before first overrun window"
run 1 us
show_values "near 25us"
run 500 ns
show_values "near 25.5us"
run 500 ns
show_values "near 26us"
quit
