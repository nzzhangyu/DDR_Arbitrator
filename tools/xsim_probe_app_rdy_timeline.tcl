proc v {sig {radix unsigned}} {
    set obj [get_objects -quiet $sig]
    if {[llength $obj] == 0} {
        return "<missing>"
    }
    return [get_value -radix $radix $obj]
}

proc line {label} {
    puts [format "%-10s t=%-10s calib=%s rst=%s cmd=%s en=%s rdy=%s wdf_rdy=%s wdf_wren=%s wdf_end=%s wr_fire=%s rd_fire=%s wr_level=%s rd_level=%s" \
        $label [current_time -s] \
        [v /tb_ddr4_controller_mock/init_calib_complete] \
        [v /tb_ddr4_controller_mock/ui_clk_sync_rst] \
        [v /tb_ddr4_controller_mock/app_cmd] \
        [v /tb_ddr4_controller_mock/app_en] \
        [v /tb_ddr4_controller_mock/app_rdy] \
        [v /tb_ddr4_controller_mock/app_wdf_rdy] \
        [v /tb_ddr4_controller_mock/app_wdf_wren] \
        [v /tb_ddr4_controller_mock/app_wdf_end] \
        [v /tb_ddr4_controller_mock/native_write_cmd_fire] \
        [v /tb_ddr4_controller_mock/native_read_cmd_fire] \
        [v /tb_ddr4_controller_mock/dut/ddr_wr_fifo_level] \
        [v /tb_ddr4_controller_mock/dut/ddr_rd_fifo_level]]
}

puts "Objects matching rw_state:"
puts [join [get_objects -r -quiet -regexp {.*rw_state.*}] "\n"]
puts "Objects matching write_data_fire:"
puts [join [get_objects -r -quiet -regexp {.*write_data_fire.*}] "\n"]
puts "Objects matching app_rdy in MIG:"
puts [join [lrange [get_objects -r -quiet -regexp {.*mig_u.*app.*rdy.*}] 0 80] "\n"]

line "t0"
run 3 us
line "3us"
run 1 us
line "4us"
run 1 us
line "5us"
run 1 us
line "6us"
run 2 us
line "8us"
run 2 us
line "10us"
run 5 us
line "15us"
run 5 us
line "20us"
run 2 us
line "22us"
run 1 us
line "23us"
run 1 us
line "24us"
run 1 us
line "25us"
quit
