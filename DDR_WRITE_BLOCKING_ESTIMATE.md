# DDR Write-Service Blocking Estimate

本文记录当前工程对“最坏 DDR 不服务写时间”的估算过程，用于解释写 FIFO 水位
`WR_LEVEL_URGENT` 的安全余量。

## 1. 器件与工作条件

本次估算依据的 DDR4 颗粒手册为：

- 器件型号：Micron `MT40A2G8SA-062E`
- 器件类型：16Gb x8 DDR4 SDRAM
- 速度等级：`-062E`
- 目标速率：DDR4-3200
- DDR 时钟周期：`tCK = 0.625ns`
- 目标时序：`CL-nRCD-nRP = 22-22-22`

本工程用户侧写入条件：

- 用户侧数据时钟：`200MHz`
- 用户侧数据位宽：`16 Byte`
- 上游写入速率：`200MHz * 16 Byte = 3.2GB/s`
- 一个 FIFO beat：`16 Byte`
- 一个用户侧 beat 时间：`1 / 200MHz = 5ns`

## 2. 关键 DDR4 时间参数

以下参数按 `MT40A2G8SA-062E`、DDR4-3200 条件整理。

| 参数 | 含义 | 数值 |
| --- | --- | --- |
| `tCK` | DDR 时钟周期 | `0.625ns` |
| `CL` | CAS read latency | `22 CK` |
| `CWL` | CAS write latency | `16 CK` 或 `20 CK` |
| `tAA` | READ 命令到首数据 | `13.75ns` min, `19.006ns` max |
| `tRCD` | ACT 到 READ/WRITE | `13.75ns = 22 CK` |
| `tRP` | PRECHARGE 时间 | `13.75ns = 22 CK` |
| `tRAS` | ACT 到 PRE 最小行打开时间 | `32ns`, 约 `52 CK` |
| `tRC` | 同 Bank ACT 到 ACT/REF | `tRAS + tRP = 45.75ns`, 约 `74 CK` |
| `tRRD_S` | 不同 Bank Group ACT 间隔，x8 1KB page | `max(4CK, 2.5ns) = 4 CK` |
| `tRRD_L` | 同 Bank Group ACT 间隔，x8 1KB page | `max(4CK, 4.9ns) = 8 CK` |
| `tFAW` | Four Activate Window，x8 1KB page | `max(20CK, 21ns) = 34 CK` |
| `tCCD_S` | 不同 Bank Group 连续 CAS 间隔 | `4 CK = 2.5ns` |
| `tCCD_L` | 同 Bank Group 连续 CAS 间隔 | `8 CK = 5ns` |
| `tWTR_S` | 写转读，不同 Bank Group | `max(2CK, 2.5ns) = 4 CK` |
| `tWTR_L` | 写转读，同 Bank Group | `max(4CK, 7.5ns) = 12 CK` |
| `tRTP` | READ 到 PRECHARGE | `max(4CK, 7.5ns) = 12 CK` |
| `tWR` | Write recovery | `15ns = 24 CK` |
| `tRFC1` | 1x refresh 阻塞时间，16Gb | `350ns = 560 CK` |
| `tRFC2` | 2x fine refresh 阻塞时间，16Gb | `260ns = 416 CK` |
| `tRFC4` | 4x fine refresh 阻塞时间，16Gb | `160ns = 256 CK` |
| `tREFI` | 平均刷新间隔，TC <= 85C | `7.8us` |
| `tREFI` | 平均刷新间隔，85C < TC <= 95C | `3.9us` |
| `tREFI` | 平均刷新间隔，95C < TC <= 105C | `1.95us` |

DDR4 手册通常不把 `tRTW` 作为单独 AC timing 参数列出，而是给出读转写公式：

```text
Read-to-Write = CL - CWL + RBL/2 + 1CK + tWPRE
```

若取 `CL = 22`、`CWL = 16`、`RBL = 8`、`tWPRE ~= 1CK`：

```text
tRTW ~= 22 - 16 + 4 + 1 + 1 = 12 CK = 7.5ns
```

若取 `CWL = 20`：

```text
tRTW ~= 8 CK = 5ns
```

## 3. 本工程相关水位

写 FIFO 的有效计数按 128-bit beat 估算：

```systemverilog
FIFO_DEPTH_EFF  ~= 14'd16383;
WR_LEVEL_URGENT = 14'd12288;
```

写 FIFO 到达 urgent 水位后，剩余空间为：

```text
16383 - 12288 = 4095 beat
4095 beat * 16 Byte = 65520 Byte ~= 64KiB
```

按用户侧 200MHz 计算，这些剩余空间可继续吸收：

```text
4095 beat * 5ns = 20.475us
```

因此，进入 `WR_LEVEL_URGENT` 后，即使 DDR 暂时完全不服务写，写 FIFO 仍有约
`20.5us` 的输入缓冲时间。

## 4. 最坏 DDR 不服务写时间估算

这里的“不服务写时间”定义为：

```text
从 wr_urgent_req 拉高
到 DDR/MIG 用户口开始真正消耗写 FIFO
```

即到 `wr_fifo_rd_en` 第一次有效，或写通路开始稳定接收写数据。

保守路径包含：

```text
当前不可中断读 burst 剩余时间
+ 读转写 bus turnaround
+ 可能的 refresh 阻塞
+ 写目标 row miss 的 PRE/ACT 延迟
+ MIG/AXI 用户口握手和 FSM 余量
```

### 4.1 当前读 burst 剩余时间

AXI 版本中当前最大读 grant：

```systemverilog
RD_GRANT_MAX     = 9'd256;
RD_GRANT_WR_HIGH = 9'd128;
```

如果写 urgent 刚好发生在一个已经发出的 256-beat 读 burst 之后，写侧不能立即打断
已在途读事务。

按不同 Bank Group 连续访问估算：

```text
256 beat * tCCD_S = 256 * 2.5ns = 640ns
```

按同 Bank Group 连续访问估算：

```text
256 beat * tCCD_L = 256 * 5ns = 1280ns
```

因此读 burst 尾部阻塞约为：

```text
640ns ~ 1280ns
```

### 4.2 读转写延迟

由手册公式估算：

```text
tRTW ~= 5ns ~ 7.5ns
```

### 4.3 Refresh 阻塞

16Gb DDR4 在 1x refresh 下：

```text
tRFC1 = 350ns
```

如果写 urgent 刚好赶上 refresh，可保守加上 `350ns`。

### 4.4 写目标 row miss

若写目标 Bank 需要先关旧行再开新行：

```text
tRP + tRCD = 13.75ns + 13.75ns = 27.5ns
```

实际 MIG 可能提前做 precharge/activate，因此这部分不一定完整暴露在用户口；
但保守估算可以计入。

### 4.5 合计

普通较保守但不遇到 refresh：

```text
640ns + 7.5ns + 27.5ns ~= 675ns
```

更保守路径，同 Bank Group 读 burst、遇到 refresh、row miss：

```text
1280ns + 7.5ns + 350ns + 27.5ns = 1665ns ~= 1.7us
```

考虑 MIG/AXI ready 抖动、仲裁 FSM 和额外安全裕量，可取：

```text
T_write_block_worst ~= 2us
```

## 5. 与上游写入速率的关系

在 `T_write_block_worst = 2us` 假设下，写 urgent 后的剩余空间对应的临界输入速率为：

```text
精确按 4095 beat:
65520 Byte / 2us = 32,760,000,000 Byte/s = 32.76GB/s

近似按 64KiB:
65536 Byte / 2us = 32,768,000,000 Byte/s = 32.768GB/s
```

这表示：如果写 FIFO 已经到 `WR_LEVEL_URGENT`，并且 DDR 接下来整整 `2us`
完全不消耗写 FIFO，那么上游平均写入速率超过约 `32.76GB/s`，才会在这段阻塞窗口内填满
约 64KiB 剩余空间并触发 overflow。

当前实际写入速率：

```text
200MHz * 16 Byte = 3.2GB/s
```

在 `2us` 内写入数据量为：

```text
3.2GB/s * 2us = 6400 Byte ~= 6.25KiB
```

该值远小于 urgent 后约 `64KiB` 的剩余空间。

## 6. 结论

在当前估算条件下：

```text
最坏 DDR 不服务写时间：保守取 2us
写 FIFO urgent 后剩余空间：约 64KiB
用户侧写入速率：3.2GB/s
2us 内用户侧写入量：约 6.25KiB
```

因此，当前 `WR_LEVEL_URGENT = 12288` 给写端留下的空间是宽裕的。按 2us 最坏阻塞估算，
它约有 10 倍以上余量：

```text
64KiB / 6.25KiB ~= 10.2
```

需要注意：这个结论依赖 `2us` 最坏阻塞假设。如果 MIG 用户口出现远超 2us 的 backpressure、
replay/backtracking 长时间阻塞、或者系统级仲裁异常，仍需要通过仿真或 ILA 实测重新校准
`T_write_block_worst`。
