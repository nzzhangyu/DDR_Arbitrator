# AGENTS.md

This directory contains the DDR4 RTL sources and the notes that explain how the design is organized.

## Purpose

Keep the RTL and the documentation synchronized while preserving the current architecture:

- DDR4 access uses AXI4, not native MIG `app_*`
- FIFO / ping-pong buffering stays in place
- dynamic watermarks and arbitration stay in place
- read replay / backtracking behavior stays in place

## Working Rules

- Edit the `.sv` RTL files directly in this directory.
- Keep functional changes and comment / documentation changes separate when possible.
- Do not reintroduce native MIG `app_*` logic unless the user explicitly requests it.
- Prefer SystemVerilog style for new edits: `logic`, `always_ff`, `always_comb`, enums, and short explanatory comments.
- Do not delete currently used AXI interface signals just because they look redundant.

## File Map

- `user_rw_cmd_gen.sv`: AXI4 command generation, arbitration, burst sizing, address tracking, and error flags.
- `user_app_top.sv`: ping-pong staging, command-generator wiring, and write-side overrun tracking.
- `ddr4_controller.sv`: top-level DDR4 wrapper, MIG AXI wiring, and user-side bridge wiring.
- `ddr_wr_2bank_pingpong.sv`: write-side 2-bank ping-pong RAM.
- `ddr_rd_2bank_pingpong.sv`: read-side 2-bank ping-pong RAM.
- `ddr_cache_and_frame_gen.sv`: cache and frame-generation related logic.
- `header_frame_gen.sv`: header/frame generation logic.
- `header_parameter.sv`: header and parameter definitions.
- `rd_cache_ctrl.sv`: read-cache control logic.
- `reading_header_slice_gen.sv`: read-side header/slice handling.
- `DDR4_ARCHITECTURE.md`: readable architecture overview and signal cheat sheet.

## Cross-Device Sync Notes

- Keep generated simulation artifacts out of sync unless they are needed for debugging:
  - `xsim.dir/`
  - `xvlog.log`
  - `xvlog.pb`
- If a device only needs the RTL sources, sync the `.sv` files and markdown docs.
- If a device needs validation, re-run `xvlog -sv` on the affected RTL files after syncing.

## Verification

Typical syntax checks:

```powershell
xvlog -sv D:\FPGA\DDR\user_rw_cmd_gen.sv
xvlog -sv D:\FPGA\DDR\user_app_top.sv
xvlog -sv D:\FPGA\DDR\ddr4_controller.sv
```
