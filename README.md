# DDR4 RTL Workspace

This workspace contains the RTL sources for a DDR4 data path that has been migrated from native MIG `app_*` control to AXI4-based access.

## What changed

- DDR4 access is now managed through AXI4 transactions.
- Existing FIFO / cache buffering remains in the design.
- Dynamic watermarking and arbitration remain in the design.
- Replay / backtracking behavior remains in the design.

## Main Files

- `user_rw_cmd_gen.txt`: AXI4 command generation and arbitration logic.
- `user_app_top.txt`: FIFO staging and command-generator integration.
- `ddr4_controller.txt`: top-level DDR4 wrapper and MIG wiring.
- `ddr_cache_and_frame_gen.txt`: cache and frame-generation support.
- `header_frame_gen.txt`: header / frame generation logic.
- `header_parameter.txt`: header-related constants and parameters.
- `rd_cache_ctrl.txt`: read-cache control logic.
- `reading_header_slice_gen.txt`: header/slice handling for reads.

## Notes for Syncing Between Devices

- Sync the `.txt` RTL files and markdown docs.
- Avoid syncing generated simulation artifacts unless you are debugging them.
- After pulling changes on another device, re-run syntax checks on the touched RTL files.

## Quick Check

```powershell
xvlog -sv C:\Users\Administrator\Desktop\ceshi\user_rw_cmd_gen.txt
xvlog -sv C:\Users\Administrator\Desktop\ceshi\user_app_top.txt
xvlog -sv C:\Users\Administrator\Desktop\ceshi\ddr4_controller.txt
```
