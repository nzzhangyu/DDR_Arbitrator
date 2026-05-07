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
xvlog -sv native\rtl\user_rw_cmd_gen.sv
xvlog -sv native\rtl\user_app_top.sv
xvlog -sv native\rtl\ddr4_controller.sv
```

## Fast Simulation

AXI fast mock regression:

```powershell
xvlog -sv D:\Xilinx\Vivado\2021.1\data\ip\xpm\xpm_cdc\hdl\xpm_cdc.sv D:\Xilinx\Vivado\2021.1\data\ip\xpm\xpm_memory\hdl\xpm_memory.sv D:\Xilinx\Vivado\2021.1\data\ip\xpm\xpm_fifo\hdl\xpm_fifo.sv axi\sim\ddr4_fast_mock.sv axi\rtl\user_rw_cmd_gen.sv axi\rtl\user_app_top.sv axi\sim\tb_ddr4_controller_mock.sv D:\Xilinx\Vivado\2021.1\data\verilog\src\glbl.v
xelab tb_ddr4_controller_mock glbl -debug typical
xsim "work.tb_ddr4_controller_mock#work.glbl" -runall
```

Native fast mock regression:

```powershell
xvlog -sv D:\Xilinx\Vivado\2021.1\data\ip\xpm\xpm_cdc\hdl\xpm_cdc.sv D:\Xilinx\Vivado\2021.1\data\ip\xpm\xpm_memory\hdl\xpm_memory.sv D:\Xilinx\Vivado\2021.1\data\ip\xpm\xpm_fifo\hdl\xpm_fifo.sv native\sim\ddr4_fast_mock.sv native\rtl\user_rw_cmd_gen.sv native\rtl\user_app_top.sv native\sim\tb_ddr4_controller_mock.sv D:\Xilinx\Vivado\2021.1\data\verilog\src\glbl.v
xelab tb_ddr4_controller_mock glbl -debug typical
xsim "work.tb_ddr4_controller_mock#work.glbl" -runall
```

AXI real MIG validation still uses `axi/sim/sim_mig/`. Native real MIG validation requires a new native MIG simulation export from Vivado.
