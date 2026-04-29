# AGENTS.md

This directory contains RTL source files for the DDR4 path and related cache / frame-generation logic.

## Purpose

The goal of this project is to keep the RTL sources synchronized across devices while preserving the current architecture:

- DDR4 access uses AXI4, not native MIG `app_*`
- FIFO / cache buffering stays in place
- dynamic watermarks and arbitration stay in place
- read replay / backtracking behavior stays in place

## Working Rules

- Edit the `.txt` RTL files directly in this directory.
- Keep functional changes and formatting / comment changes separate when possible.
- Do not reintroduce native MIG `app_*` logic unless the user explicitly requests it.
- Prefer SystemVerilog style for new edits: `logic`, `always_ff`, `always_comb`, enums, and short explanatory comments.
- Do not delete currently used AXI interface signals just because they look redundant.

## File Map

- `user_rw_cmd_gen.txt`: AXI4 command generation, arbitration, burst sizing, address tracking, and error flags.
- `user_app_top.txt`: FIFO staging, command-generator wiring, and write-side overrun tracking.
- `ddr4_controller.txt`: top-level DDR4 wrapper, MIG AXI wiring, and user-side bridge wiring.
- `ddr_cache_and_frame_gen.txt`: cache and frame-generation related logic.
- `header_frame_gen.txt`: header/frame generation logic.
- `header_parameter.txt`: header and parameter definitions.
- `rd_cache_ctrl.txt`: read-cache control logic.
- `reading_header_slice_gen.txt`: read-side header/slice handling.

## Cross-Device Sync Notes

- Keep generated simulation artifacts out of sync unless they are needed for debugging:
  - `xsim.dir/`
  - `xvlog.log`
  - `xvlog.pb`
- If a device only needs the RTL sources, sync the `.txt` files and markdown docs.
- If a device needs validation, re-run `xvlog -sv` on the affected RTL files after syncing.

## Verification

Typical syntax checks:

```powershell
xvlog -sv C:\Users\Administrator\Desktop\ceshi\user_rw_cmd_gen.txt
xvlog -sv C:\Users\Administrator\Desktop\ceshi\user_app_top.txt
xvlog -sv C:\Users\Administrator\Desktop\ceshi\ddr4_controller.txt
```

