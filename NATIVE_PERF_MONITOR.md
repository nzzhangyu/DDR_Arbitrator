# Native DDR Performance Monitor

`native/rtl/native_perf_monitor.sv` runs entirely in the MIG `ui_clk` domain.
It uses a 139200-cycle rolling window, which is 464 us at 300 MHz and is
approximately two 232 us VIEW periods. The terminal cycle is included in the
snapshot. Live counters then clear and `perf_snapshot_seq` increments.

All event and residency counters are 48-bit raw values. The monitor records:

- Accepted 128-bit writes, accepted read commands, and returned 128-bit reads.
- Write/read request pressure and cycles without service.
- Exclusive residency of idle, arbitration, write, read-command, and read-data states.
- Request-qualified MIG ready stalls, return waits, FIFO-space blocks, urgent blocks,
  read-window stops, replay blocks, and read-FIFO overflow risk.
- FIFO window minimum/maximum levels, full/empty duration, and urgent duration/edges.
- Arbitration grants, completed bursts, prematurely stopped read groups, and maximum/end
  read outstanding depth.

FIFO levels and payload counts use 128-bit DDR-beat units. The 64-bit user output
count is twice the read-data beat count after all returned data has drained.

ILA should probe the `perf_*` snapshot aliases below `debug_monitor_u/perf_monitor_u`.
The existing 32-bit current/maximum streak counters remain useful as triggers for a
single long stall. `perf_snapshot_valid` becomes sticky after the first complete
window; use `perf_snapshot_seq` to detect a new sample. `perf_counter_overflow`
indicates that at least one 48-bit live counter wrapped in the captured window.

Offline formulas at a 300 MHz `ui_clk` are:

```text
window_seconds = perf_window_cycles / 300000000
write_Bps       = perf_wr_fire_count * 16 / window_seconds
read_Bps        = perf_rd_data_fire_count * 16 / window_seconds
command_use     = perf_cmd_fire_count / perf_window_cycles
payload_use     = perf_payload_count / perf_window_cycles
```

The state-residency integrity check for every complete snapshot is:

```text
idle + arb + write_state + read_cmd_state + read_data_state = window_cycles
```
