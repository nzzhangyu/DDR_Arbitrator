# DDR4 RTL Workspace

This workspace contains the current DDR4 RTL sources and the notes that explain how the data path is organized.

## Start Here

- [DDR4_ARCHITECTURE.md](./DDR4_ARCHITECTURE.md)
- [AGENTS.md](./AGENTS.md)

The architecture note explains the current AXI4-based DDR path, the write and read XPM FIFOs, the arbitration thresholds, and the signal meanings that are easiest to forget.

## Main Files

- `rtl/user_rw_cmd_gen.sv`: AXI4 command generation and arbitration logic.
- `rtl/user_app_top.sv`: XPM FIFO staging and command-generator integration.
- `rtl/ddr4_controller.sv`: top-level DDR4 wrapper and MIG wiring.
- `sim/ddr4_fast_mock.sv`: lightweight AXI DDR model for daily regression.
- `sim/ddr4_1200m_fast_wrapper.sv`: simulation-only `ddr4_1200m` replacement that connects the fast mock.
- `sim/ddr4_mig_adapter.sv`: legacy simulation adapter, no longer used by the main regression commands.
- `sim/tb_ddr4_controller_mock.sv`: slice/view functional testbench that connects `user_app_top` directly to the fast mock.
- `sim/tb_ddr4_controller_mig_real.sv`: slice/view testbench using the real MIG simulation netlist and DDR4 memory model.
- `rtl/ddr_wr_2bank_pingpong.sv`: legacy write-side 2-bank ping-pong RAM, no longer instantiated by the DDR bridge.
- `rtl/ddr_rd_2bank_pingpong.sv`: legacy read-side 2-bank ping-pong RAM, no longer instantiated by the DDR bridge.
- `rtl/ddr_cache_and_frame_gen.sv`: cache and frame-generation support.
- `rtl/header_frame_gen.sv`: header / frame generation logic.
- `rtl/header_parameter.sv`: header-related constants and parameters.
- `rtl/rd_cache_ctrl.sv`: read-cache control logic.
- `rtl/reading_header_slice_gen.sv`: header/slice handling for reads.

## Sync Notes

- Sync `rtl/`, `sim/`, and the markdown docs.
- `rtl/` contains design RTL and legacy RTL candidates.
- `sim/` contains testbenches, fast mock logic, the fast `ddr4_1200m` wrapper, legacy adapter, and copied MIG simulation files.
- Avoid syncing generated simulation artifacts unless you are debugging them.
- After pulling changes on another device, re-run syntax checks on the touched RTL files.

## Quick Check

```powershell
xvlog -sv rtl\user_rw_cmd_gen.sv
xvlog -sv rtl\user_app_top.sv
xvlog -sv rtl\ddr4_controller.sv
```

## Simulation Modes

Fast daily regression does not use the MIG IP or the `ddr4_1200m` wrapper. `sim/tb_ddr4_controller_mock.sv` connects `rtl/user_app_top.sv` directly to `sim/ddr4_fast_mock.sv`, so this mode only checks the AXI bridge, FIFO watermarks, arbitration, replay/backtracking, and data ordering around the fast model.

```powershell
xvlog -sv D:\Xilinx\Vivado\2021.1\data\ip\xpm\xpm_cdc\hdl\xpm_cdc.sv D:\Xilinx\Vivado\2021.1\data\ip\xpm\xpm_memory\hdl\xpm_memory.sv D:\Xilinx\Vivado\2021.1\data\ip\xpm\xpm_fifo\hdl\xpm_fifo.sv sim\ddr4_fast_mock.sv rtl\user_rw_cmd_gen.sv rtl\user_app_top.sv sim\tb_ddr4_controller_mock.sv D:\Xilinx\Vivado\2021.1\data\verilog\src\glbl.v
xelab tb_ddr4_controller_mock glbl -debug typical
xsim "work.tb_ddr4_controller_mock#work.glbl" -runall
```

Real MIG validation compiles `rtl/ddr4_controller.sv` and the copied Xilinx `ddr4_1200m` netlist in `sim/sim_mig/`. Do not compile `sim/ddr4_1200m_fast_wrapper.sv` in this mode, because it defines the same `ddr4_1200m` module name. The real memory model path is configured as 16 Gb x8 DDR4 components, with two x8 models forming the 16-bit DQ bus. This mode is much slower because it runs the MIG calibration logic and the DDR4 memory model.

```powershell
xvlog -d XILINX_SIMULATOR -i sim\sim_mig -sv D:\Xilinx\Vivado\2021.1\data\ip\xpm\xpm_cdc\hdl\xpm_cdc.sv D:\Xilinx\Vivado\2021.1\data\ip\xpm\xpm_memory\hdl\xpm_memory.sv D:\Xilinx\Vivado\2021.1\data\ip\xpm\xpm_fifo\hdl\xpm_fifo.sv sim\sim_mig\blk_mem_gen_v8_4.v sim\sim_mig\ddr4_1200m_sim_netlist.v sim\sim_mig\arch_package.sv sim\sim_mig\interface.sv sim\sim_mig\proj_package.sv sim\sim_mig\ddr4_model.sv rtl\user_rw_cmd_gen.sv rtl\user_app_top.sv rtl\ddr4_controller.sv sim\tb_ddr4_controller_mig_real.sv sim\sim_mig\glbl.v
xelab tb_ddr4_controller_mig_real glbl -debug typical -L unisims_ver -L unimacro_ver -L secureip -L xpm
xsim "work.tb_ddr4_controller_mig_real#work.glbl" -runall
```

Both testbenches support `+views=N`. For long stress runs, use `+scoreboard=hash` to avoid storing every expected beat in a queue.
