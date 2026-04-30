# DDR4 RTL Workspace

This workspace contains the current DDR4 RTL sources and the notes that explain how the data path is organized.

## Start Here

- [DDR4_ARCHITECTURE.md](./DDR4_ARCHITECTURE.md)
- [AGENTS.md](./AGENTS.md)

The architecture note explains the current AXI4-based DDR path, the write and read ping-pong buffers, the arbitration thresholds, and the signal meanings that are easiest to forget.

## Main Files

- `user_rw_cmd_gen.sv`: AXI4 command generation and arbitration logic.
- `user_app_top.sv`: ping-pong staging and command-generator integration.
- `ddr4_controller.sv`: top-level DDR4 wrapper and MIG wiring.
- `ddr_wr_2bank_pingpong.sv`: write-side 2-bank ping-pong RAM.
- `ddr_rd_2bank_pingpong.sv`: read-side 2-bank ping-pong RAM.
- `ddr_cache_and_frame_gen.sv`: cache and frame-generation support.
- `header_frame_gen.sv`: header / frame generation logic.
- `header_parameter.sv`: header-related constants and parameters.
- `rd_cache_ctrl.sv`: read-cache control logic.
- `reading_header_slice_gen.sv`: header/slice handling for reads.

## Sync Notes

- Sync the `.sv` RTL files and markdown docs.
- Avoid syncing generated simulation artifacts unless you are debugging them.
- After pulling changes on another device, re-run syntax checks on the touched RTL files.

## Quick Check

```powershell
xvlog -sv D:\FPGA\DDR\user_rw_cmd_gen.sv
xvlog -sv D:\FPGA\DDR\user_app_top.sv
xvlog -sv D:\FPGA\DDR\ddr4_controller.sv
```

For fast simulation, instantiate `ddr4_fast_mock.sv` directly in the testbench and connect it to the AXI master signals that normally drive the MIG AXI slave.
