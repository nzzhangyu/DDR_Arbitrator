# DDR4 RTL Workspace

This workspace now keeps two DDR4 interface variants side by side:

- `axi/`: the current stable AXI4-based DDR path.
- `native/`: a parallel native MIG `app_*` path with the same file names and the same `rtl/` / `sim/` layout.

Do not compile both variants in the same Vivado file set unless module names are isolated by libraries. The two trees intentionally reuse names such as `ddr4_controller`, `user_app_top`, `user_rw_cmd_gen`, and `ddr4_fast_mock`.

## Directory Layout

- `axi/rtl/`: existing AXI4 RTL, including the active XPM FIFO bridge and legacy RTL candidates.
- `axi/sim/`: existing AXI testbenches, AXI fast mock, AXI `ddr4_1200m` fast wrapper, legacy adapter, and copied AXI MIG simulation files.
- `native/rtl/`: native MIG application-interface RTL. The user-facing DDR controller ports stay aligned with the AXI version, while the MIG boundary uses `app_*`.
- `native/sim/`: native fast mock and native functional testbench. A real native MIG netlist is not checked in yet; generate it separately from Vivado.

## Main Files

- `axi/rtl/user_rw_cmd_gen.sv`: AXI4 command generation and arbitration logic.
- `axi/rtl/user_app_top.sv`: AXI XPM FIFO staging and command-generator integration.
- `axi/rtl/ddr4_controller.sv`: top-level AXI MIG wrapper.
- `native/rtl/user_rw_cmd_gen.sv`: native `app_*` command generation with the same watermarks, burst grouping, address tracking, replay, and warning behavior.
- `native/rtl/user_app_top.sv`: native XPM FIFO staging and native command-generator integration.
- `native/rtl/ddr4_controller.sv`: top-level native MIG wrapper.
- `DDR4_ARCHITECTURE.md`: architecture notes and signal cheat sheet.
- `AGENTS.md`: working rules for future edits.

## MIG Notes

The checked-in real MIG simulation netlist under `axi/sim/sim_mig/ddr4_1200m_sim_netlist.v` is the AXI-interface version. It should only be used with `axi/rtl/ddr4_controller.sv`.

The native tree expects a separately generated native/application-interface MIG IP with compatible DDR4 physical settings. The native wrapper connects these app signals:

- `c0_ddr4_app_addr`
- `c0_ddr4_app_cmd`
- `c0_ddr4_app_en`
- `c0_ddr4_app_rdy`
- `c0_ddr4_app_wdf_data`
- `c0_ddr4_app_wdf_mask`
- `c0_ddr4_app_wdf_wren`
- `c0_ddr4_app_wdf_end`
- `c0_ddr4_app_wdf_rdy`
- `c0_ddr4_app_rd_data`
- `c0_ddr4_app_rd_data_valid`
- `c0_ddr4_app_rd_data_end`

## Quick Syntax Checks

AXI:

```powershell
xvlog -sv axi\rtl\user_rw_cmd_gen.sv
xvlog -sv axi\rtl\user_app_top.sv
xvlog -sv axi\rtl\ddr4_controller.sv
```

Native:

```powershell
xvlog -sv native\rtl\ddr_ring_addr_mgr.sv
xvlog -sv native\rtl\rw_pressure_ctrl.sv
xvlog -sv native\rtl\rw_arbiter.sv
xvlog -sv native\rtl\native_dbg_streak_counter.sv
xvlog -sv native\rtl\rw_cmd_debug_monitor.sv
xvlog -sv native\rtl\user_rw_cmd_gen.sv
xvlog -sv native\rtl\user_app_top.sv
xvlog -sv native\rtl\ddr4_controller.sv
```

`native\rtl\ddr_overrun_monitor.sv` is retained as a legacy standalone monitor; active native overrun/warning logic is now inside `ddr_ring_addr_mgr.sv`.

## Fast Simulation

AXI fast mock regression:

```powershell
xvlog -sv D:\Xilinx\Vivado\2021.1\data\ip\xpm\xpm_cdc\hdl\xpm_cdc.sv D:\Xilinx\Vivado\2021.1\data\ip\xpm\xpm_memory\hdl\xpm_memory.sv D:\Xilinx\Vivado\2021.1\data\ip\xpm\xpm_fifo\hdl\xpm_fifo.sv axi\sim\ddr4_fast_mock.sv axi\rtl\user_rw_cmd_gen.sv axi\rtl\user_app_top.sv axi\sim\tb_ddr4_controller_mock.sv D:\Xilinx\Vivado\2021.1\data\verilog\src\glbl.v
xelab tb_ddr4_controller_mock glbl -debug typical
xsim "work.tb_ddr4_controller_mock#work.glbl" -runall
```

Native fast mock regression:

```powershell
xvlog -sv -i native\sim D:\Xilinx\Vivado\2021.1\data\ip\xpm\xpm_cdc\hdl\xpm_cdc.sv D:\Xilinx\Vivado\2021.1\data\ip\xpm\xpm_memory\hdl\xpm_memory.sv D:\Xilinx\Vivado\2021.1\data\ip\xpm\xpm_fifo\hdl\xpm_fifo.sv native\sim\cross_clk_pulse.sv native\sim\ddr4_fast_mock_periodic_stall.sv native\sim\ddr4_fast_mock_stall_model.sv native\sim\ddr4_fast_mock_read_pending_model.sv native\sim\ddr4_fast_mock.sv native\sim\ddr4_controller_tb_stream_source.sv native\sim\ddr4_controller_tb_monitor.sv native\rtl\rd_cache_ctrl.sv native\rtl\ddr_ring_addr_mgr.sv native\rtl\rw_pressure_ctrl.sv native\rtl\rw_arbiter.sv native\rtl\native_dbg_streak_counter.sv native\rtl\rw_cmd_debug_monitor.sv native\rtl\user_rw_cmd_gen.sv native\rtl\user_app_top.sv native\sim\tb_ddr4_controller_mock.sv D:\Xilinx\Vivado\2021.1\data\verilog\src\glbl.v
xelab tb_ddr4_controller_mock glbl -debug typical
xsim "work.tb_ddr4_controller_mock#work.glbl" -runall
```

The native TB has two compile-time test items in
`native/sim/tb_ddr4_controller_mock.sv`:

- `TEST_KIND = TEST_NORMAL` is the default normal loopback simulation. It keeps
  mock stalls disabled and checks sent/received data consistency.
- `TEST_KIND = TEST_STRESS` enables moderate fast-mock backpressure and
  worst-case monitor limits for overflow, underflow, and long stall windows.

To run the pressure item, change:

```systemverilog
localparam int TEST_KIND = TEST_STRESS;
```

then compile and run the same native fast mock command above.

For waveform-friendly incrementing 8-bit repeated data, set
`STREAM_INCREMENT_MODE = 1'b1` in `native/sim/tb_ddr4_controller_mock.sv`, then run:

```powershell
xsim "work.tb_ddr4_controller_mock#work.glbl" -testplusarg views=1 -runall
```

Native real MIG regression:

Export the native `ddr4_1200m` MIG simulation files into `native\sim\sim_mig\` first.
Define `MIG` either in `native\sim\ddr4_tb_config.svh` or with `xvlog -d MIG`.
Do not compile `native\sim\ddr4_1200m_fast_wrapper.sv` in this file set.

```powershell
xvlog -sv -d MIG -i native\sim -i native\sim\sim_mig D:\Xilinx\Vivado\2021.1\data\ip\xpm\xpm_cdc\hdl\xpm_cdc.sv D:\Xilinx\Vivado\2021.1\data\ip\xpm\xpm_memory\hdl\xpm_memory.sv D:\Xilinx\Vivado\2021.1\data\ip\xpm\xpm_fifo\hdl\xpm_fifo.sv native\sim\sim_mig\arch_package.sv native\sim\sim_mig\proj_package.sv native\sim\sim_mig\interface.sv native\sim\sim_mig\ddr4_model.sv native\sim\sim_mig\ddr4_1200m_sim_netlist.v native\sim\cross_clk_pulse.sv native\sim\ddr4_controller_tb_stream_source.sv native\sim\ddr4_controller_tb_monitor.sv native\rtl\rd_cache_ctrl.sv native\rtl\ddr_ring_addr_mgr.sv native\rtl\rw_pressure_ctrl.sv native\rtl\rw_arbiter.sv native\rtl\native_dbg_streak_counter.sv native\rtl\rw_cmd_debug_monitor.sv native\rtl\user_rw_cmd_gen.sv native\rtl\user_app_top.sv native\sim\tb_ddr4_controller_mock.sv native\sim\sim_mig\glbl.v
xelab tb_ddr4_controller_mock glbl -debug typical
xsim "work.tb_ddr4_controller_mock#work.glbl" -testplusarg views=1 -testplusarg scoreboard=hash -runall
```

AXI real MIG validation still uses `axi/sim/sim_mig/`. Native real MIG validation requires a new native MIG simulation export from Vivado.
