# AGENTS.md

This repository contains two parallel DDR4 interface variants:

- `axi/`: current AXI4 implementation.
- `native/`: native MIG `app_*` implementation.

Both variants keep the same internal structure:

- `rtl/`: design RTL and legacy RTL candidates.
- `sim/`: testbenches, fast mock logic, wrappers, and simulation support for that variant.

## Purpose

Keep RTL and documentation synchronized while preserving the architecture choices in each variant:

- AXI access stays in `axi/`.
- Native MIG `app_*` access stays in `native/`.
- XPM FIFO buffering remains the active DDR bridge path in both variants.
- Dynamic watermarks and arbitration stay in place.
- Read replay / backtracking behavior stays in place.

## Working Rules

- Edit AXI RTL under `axi/rtl/` and AXI simulation support under `axi/sim/`.
- Edit native RTL under `native/rtl/` and native simulation support under `native/sim/`.
- Keep functional changes and comment / documentation changes separate when possible.
- Do not mix AXI and native modules in the same Vivado compile set unless module names are library-isolated.
- Prefer SystemVerilog style for new edits: `logic`, `always_ff`, `always_comb`, enums, and short explanatory comments.
- Do not delete currently used interface signals just because they look redundant.

## File Map

- `axi/rtl/user_rw_cmd_gen.sv`: AXI4 command generation, arbitration, burst sizing, address tracking, and error flags.
- `axi/rtl/user_app_top.sv`: AXI XPM FIFO staging, command-generator wiring, and write-side overrun tracking.
- `axi/rtl/ddr4_controller.sv`: top-level DDR4 wrapper, MIG AXI wiring, and user-side bridge wiring.
- `native/rtl/user_rw_cmd_gen.sv`: native `app_*` command generation with the same arbitration, burst grouping, address tracking, and error flags.
- `native/rtl/user_app_top.sv`: native XPM FIFO staging, command-generator wiring, and write-side overrun tracking.
- `native/rtl/ddr4_controller.sv`: top-level DDR4 wrapper, MIG native app wiring, and user-side bridge wiring.
- `DDR4_ARCHITECTURE.md`: readable architecture overview and signal cheat sheet.

## Cross-Device Sync Notes

- If a device only needs the RTL sources, sync `axi/rtl/`, `native/rtl/`, and markdown docs.
- If a device needs validation, sync the corresponding `sim/` tree too.
- Keep generated simulation artifacts out of sync unless they are needed for debugging:
  - `xsim.dir/`
  - `xvlog.log`
  - `xvlog.pb`
  - `xelab.log`
  - `xelab.pb`

## Verification

Typical syntax checks:

```powershell
xvlog -sv axi\rtl\user_rw_cmd_gen.sv
xvlog -sv axi\rtl\user_app_top.sv
xvlog -sv axi\rtl\ddr4_controller.sv
xvlog -sv native\rtl\user_rw_cmd_gen.sv
xvlog -sv native\rtl\user_app_top.sv
xvlog -sv native\rtl\ddr4_controller.sv
```
