# DDR4 RTL Workspace

This workspace contains the current DDR4 RTL sources and the notes that explain how the data path is organized.

## Start Here

- [DDR4_ARCHITECTURE.md](./DDR4_ARCHITECTURE.md)
- [AGENTS.md](./AGENTS.md)

The architecture note explains the current AXI4-based DDR path, the write and read XPM FIFOs, the arbitration thresholds, and the signal meanings that are easiest to forget.

## Main Files

- `user_rw_cmd_gen.sv`: AXI4 command generation and arbitration logic.
- `user_app_top.sv`: XPM FIFO staging and command-generator integration.
- `ddr4_controller.sv`: top-level DDR4 wrapper and MIG wiring.
- `ddr4_mig_adapter.sv`: simulation adapter that selects either the fast AXI DDR mock or the real Xilinx MIG model.
- `ddr4_fast_mock.sv`: lightweight AXI DDR model for daily regression.
- `tb_ddr4_controller_mock.sv`: slice/view functional testbench using the fast mock path.
- `tb_ddr4_controller_mig_real.sv`: slice/view testbench using the real MIG simulation netlist and DDR4 memory model.
- `ddr_wr_2bank_pingpong.sv`: legacy write-side 2-bank ping-pong RAM, no longer instantiated by the DDR bridge.
- `ddr_rd_2bank_pingpong.sv`: legacy read-side 2-bank ping-pong RAM, no longer instantiated by the DDR bridge.
- `ddr_cache_and_frame_gen.sv`: cache and frame-generation support.
- `header_frame_gen.sv`: header / frame generation logic.
- `header_parameter.sv`: header-related constants and parameters.
- `rd_cache_ctrl.sv`: read-cache control logic.
- `reading_header_slice_gen.sv`: header/slice handling for reads.

## Sync Notes

- Sync the `.sv` RTL files and markdown docs.
- Sync `sim_mig/` when another machine needs real MIG simulation.
- Avoid syncing generated simulation artifacts unless you are debugging them.
- After pulling changes on another device, re-run syntax checks on the touched RTL files.

## Quick Check

```powershell
xvlog -sv C:\FPGA\DDR_arb\DDR_Arbitrator\user_rw_cmd_gen.sv
xvlog -sv C:\FPGA\DDR_arb\DDR_Arbitrator\user_app_top.sv
xvlog -sv C:\FPGA\DDR_arb\DDR_Arbitrator\ddr4_controller.sv
```

## Simulation Modes

Fast daily regression uses `ddr4_mig_adapter.sv` in its default mode, which connects `ddr4_fast_mock.sv` behind the unchanged `ddr4_controller.sv` interface.

```powershell
xvlog -sv D:\Xilinx\Vivado\2021.1\data\ip\xpm\xpm_cdc\hdl\xpm_cdc.sv D:\Xilinx\Vivado\2021.1\data\ip\xpm\xpm_memory\hdl\xpm_memory.sv D:\Xilinx\Vivado\2021.1\data\ip\xpm\xpm_fifo\hdl\xpm_fifo.sv ddr4_fast_mock.sv ddr4_mig_adapter.sv user_rw_cmd_gen.sv user_app_top.sv ddr4_controller.sv tb_ddr4_controller_mock.sv D:\Xilinx\Vivado\2021.1\data\verilog\src\glbl.v
xelab tb_ddr4_controller_mock glbl -debug typical
xsim "work.tb_ddr4_controller_mock#work.glbl" -runall
```

Real MIG validation defines `USE_REAL_MIG` and compiles the copied Xilinx files in `sim_mig/`. This mode is much slower because it runs the MIG calibration logic and the DDR4 memory model.

```powershell
xvlog -d USE_REAL_MIG -d XILINX_SIMULATOR -i sim_mig -sv D:\Xilinx\Vivado\2021.1\data\ip\xpm\xpm_cdc\hdl\xpm_cdc.sv D:\Xilinx\Vivado\2021.1\data\ip\xpm\xpm_memory\hdl\xpm_memory.sv D:\Xilinx\Vivado\2021.1\data\ip\xpm\xpm_fifo\hdl\xpm_fifo.sv sim_mig\blk_mem_gen_v8_4.v sim_mig\ddr4_1200m_sim_netlist.v sim_mig\arch_package.sv sim_mig\interface.sv sim_mig\proj_package.sv sim_mig\ddr4_model.sv ddr4_fast_mock.sv ddr4_mig_adapter.sv user_rw_cmd_gen.sv user_app_top.sv ddr4_controller.sv tb_ddr4_controller_mig_real.sv sim_mig\glbl.v
xelab tb_ddr4_controller_mig_real glbl -debug typical -L unisims_ver -L unimacro_ver -L secureip -L xpm
xsim "work.tb_ddr4_controller_mig_real#work.glbl" -runall
```

Both testbenches support `+views=N`. For long stress runs, use `+scoreboard=hash` to avoid storing every expected beat in a queue.
