# DDR Read/Write Blocking Estimate

本文记录当前工程基于 MIG IP 配置的 DDR 读写最坏阻塞时间估算，用于解释写 FIFO
`WR_LEVEL_URGENT` 和读 FIFO `RD_LEVEL_URGENT` 的安全余量。

## 1. MIG 配置与工作条件

当前 MIG IP Basic 页面中的关键配置如下：

- MIG IP：`DDR4 SDRAM (MIG) 2.2`
- Component Name：`ddr4_1200m`
- Memory Part：`MT40A2G8VA-062E`
- 颗粒类型：Micron 16Gb x8 DDR4 SDRAM
- 物理数据宽度：`16 bit`
- Burst Length：`BL8`
- Memory Device Interface Speed：`833ps`
- DDR CK 频率：`1 / 833ps ~= 1200MHz`
- DDR 等效数据率：`2400MT/s`
- 当前工作点：DDR4-2400
- PHY:Controller clock ratio：`4:1`
- MIG `ui_clk` 估算：`1200MHz / 4 = 300MHz`
- Reference Input Clock：`4998ps ~= 200.08MHz`
- CAS Latency：`CL = 17`
- CAS Write Latency：`CWL = 12`
- Data Mask and DBI：`DM NO DBI`
- ECC：未启用
- Memory Address Map：`ROW COLUMN BANK`

注意：颗粒手册文件名中出现的是 `MT40A2G8SA-062E`，MIG 器件库中选择的是
`MT40A2G8VA-062E`。二者在本次估算中按同类 16Gb x8 `-062E` DDR4 颗粒处理；
最终工程仍应以原理图、BOM 和 Vivado MIG 选型为准。

由于物理 DQ 宽度为 `16 bit`，且 DDR4 burst 为 `BL8`，MIG native app 端一个数据 beat 为：

```text
16 bit * 8 = 128 bit = 16 Byte
```

这与本工程 FIFO 数据宽度一致。

本工程 FIFO 时钟关系：

- 写侧 FIFO 写接口：系统时钟 `clk = 200MHz`
- 写侧 FIFO 写接口位宽：`128 bit = 16 Byte`
- 写侧 FIFO 写入速率：`200MHz * 16 Byte = 3.2GB/s`
- 写侧 FIFO 读接口：MIG 用户时钟 `ui_clk ~= 300MHz`
- 读侧 FIFO 写接口：MIG 用户时钟 `ui_clk ~= 300MHz`
- 读侧 FIFO 读接口：GTY 用户时钟 `257.8125MHz`
- 读侧 FIFO 读接口位宽：`64 bit = 0.5 * 128-bit beat`
- 下游读出速率按 GTY 2-lane 8b/10b 连续读取估算：`128.90625 128-bit beat/us`
- 一个 FIFO beat：`16 Byte`
- 一个系统侧 beat 时间：`1 / 200MHz = 5ns`

也就是说，本文用于计算 overflow/underflow 余量的 `200MHz`、`128 bit`
是系统侧 FIFO 接口速率；MIG 侧 `ui_clk` 为约 `300MHz`，负责在 DDR 访问被允许时从写 FIFO
读出数据或向读 FIFO 写入数据。

## 2. 当前工作点的关键 DDR4 时间参数

以下参数按 MIG 当前 DDR4-2400 配置估算，而不是按颗粒最高 DDR4-3200 估算。

| 参数 | 含义 | 当前估算值 |
| --- | --- | --- |
| `tCK` | DDR CK 周期 | `0.833ns` |
| `CL` | CAS read latency | `17 CK ~= 14.16ns` |
| `CWL` | CAS write latency | `12 CK ~= 10.00ns` |
| `tRCD` | ACT 到 READ/WRITE | 约 `17 CK ~= 14.16ns` |
| `tRP` | PRECHARGE 时间 | 约 `17 CK ~= 14.16ns` |
| `tRAS` | ACT 到 PRE 最小行打开时间 | `32ns`, 约 `39 CK` |
| `tRC` | 同 Bank ACT 到 ACT/REF | `tRAS + tRP ~= 46.16ns`, 约 `56 CK` |
| `tCCD_S` | 不同 Bank Group 连续 CAS 间隔 | `4 CK ~= 3.33ns` |
| `tCCD_L` | 同 Bank Group 连续 CAS 间隔 | `max(4CK, 5ns)`, 估算约 `5ns` |
| `tWTR_S` | 写转读，不同 Bank Group | `max(2CK, 2.5ns)`, 保守约 `4 CK ~= 3.33ns` |
| `tWTR_L` | 写转读，同 Bank Group | `max(4CK, 7.5ns)`, 保守约 `10 CK ~= 8.33ns` |
| `tRTP` | READ 到 PRECHARGE | `max(4CK, 7.5ns)`, 保守约 `10 CK ~= 8.33ns` |
| `tWR` | Write recovery | `15ns`, 约 `19 CK` |
| `tRFC1` | 1x refresh 阻塞时间，16Gb | `350ns` |
| `tRFC2` | 2x fine refresh 阻塞时间，16Gb | `260ns` |
| `tRFC4` | 4x fine refresh 阻塞时间，16Gb | `160ns` |
| `tREFI` | 平均刷新间隔，TC <= 85C | `7.8us` |
| `tREFI` | 平均刷新间隔，85C < TC <= 95C | `3.9us` |
| `tREFI` | 平均刷新间隔，95C < TC <= 105C | `1.95us` |

读写切换公式：

```text
Read-to-Write = CL - CWL + RBL/2 + 1CK + tWPRE
Write-to-Read same BG = CWL + WBL/2 + tWTR_L
Write-to-Read diff BG = CWL + WBL/2 + tWTR_S
```

按 `CL = 17`、`CWL = 12`、`RBL = WBL = 8`、`tWPRE ~= 1CK`：

```text
Read-to-Write ~= 17 - 12 + 4 + 1 + 1 = 11CK ~= 9.16ns

Write-to-Read same BG ~= 12 + 4 + 10 = 26CK ~= 21.66ns
Write-to-Read diff BG ~= 12 + 4 + 4  = 20CK ~= 16.66ns
```

## 3. 本工程相关水位

写 FIFO 和读 FIFO 的有效计数按 128-bit beat 估算：

```systemverilog
WR_FIFO_DEPTH   = 4096;
RD_FIFO_DEPTH   ~= 14'd4095;
WR_LEVEL_URGENT = 14'd2560;
RD_LEVEL_URGENT = 14'd1024;
RD_LEVEL_LOW    = 14'd1024;
RD_LEVEL_HIGH   = 14'd3072;
```

写 FIFO 到达 urgent 水位后，剩余空间为：

```text
4096 - 2560 = 1536 beat
1536 beat * 16 Byte = 24576 Byte = 24KiB
```

按写侧 FIFO 写接口 `200MHz` 计算，这些剩余空间可继续吸收：

```text
1536 beat * 5ns = 7.68us
```

读 FIFO 到达 urgent 水位时，仍有数据缓存：

```text
1024 beat * 16 Byte = 16384 Byte = 16KiB
1024 beat / 128.90625 beat/us ~= 7.94us
```

因此，在系统侧 `200MHz x 16Byte` 的持续写入/读取速率下，写 urgent 后的剩余空间约对应
`7.68us` 的时间余量。读侧按 GTY 2-lane 8b/10b 输出等效 `128.90625 beat/us`
消耗估算，读 urgent 时的已有缓存约对应 `7.94us` 的时间余量。

## 4. 最坏 DDR 不服务写时间估算

这里的“不服务写时间”定义为：

```text
从 wr_urgent_req 拉高
到 DDR/MIG 用户口开始真正消耗写 FIFO
```

即到 `wr_fifo_rd_en` 第一次有效，或写通路开始稳定接收写数据。

### 4.1 DDR 颗粒侧原因

这部分来自 DDR4 本身的时序限制，主要包括已经在途的读 burst、读写方向切换、refresh、row miss。

| 原因 | 估算 |
| --- | --- |
| 当前不可中断读 burst 剩余时间 | 256 beat 按 `tCCD_S` 估算约 `853ns`，按 `tCCD_L` 估算约 `1280ns` |
| Read-to-Write turnaround | `CL - CWL + RBL/2 + 1CK + tWPRE ~= 11CK ~= 9.16ns` |
| Refresh 阻塞 | 16Gb DDR4 1x refresh 下 `tRFC1 = 350ns` |
| 写目标 row miss | `tRP + tRCD ~= 28.32ns` |

不遇到 refresh 的普通保守路径：

```text
853ns + 9.16ns + 28.32ns ~= 890ns
```

同 Bank Group、遇到 refresh、row miss 的更保守路径：

```text
1280ns + 9.16ns + 350ns + 28.32ns = 1667.48ns ~= 1.7us
```

### 4.2 MIG IP / 用户口原因

MIG IP 会把 DDR 颗粒侧的时序限制、PHY 管线、命令调度和用户口 ready 信号统一反映到 AXI/native 接口上。
因此即使 DDR 颗粒侧理论延迟约 `1.7us`，用户逻辑看到的“不服务写”还可能额外包含：

```text
AXI AW/W ready 或 native app_rdy/app_wdf_rdy 等待
MIG 内部命令队列和读写方向切换调度
AXI 写响应等待或 native FSM 回到仲裁状态的延迟
当前工程仲裁 FSM 不能打断已发出的 burst / service group
```

考虑这些 MIG/IP 与用户口因素后，不含 replay 的写侧保守估算取：

```text
T_write_block_worst_no_replay ~= 2us
```

### 4.3 重传 / replay 原因

当前工程中 `rp_back_en` 会回退读指针：

```systemverilog
else if (rp_back_en) begin
    user_ad_rd_i <= {1'b0, rp_back_view_addr};
end
```

同时新命令会被 replay 阻塞：

```systemverilog
assign block_for_replay = rp_back_en || (|rp_back_en_dly_cnt);
```

`rp_back_en_dly_cnt` 为 8 bit，从 `1` 计数直到自然回到 `0`，单次 replay 会带来约：

```text
255 ui_clk cycle / 300MHz ~= 0.85us
```

replay 结束后，读指针回退会使 `ddr_rd_avail_count = user_ad_wr_i - user_ad_rd_i` 变大。
如果此时读 FIFO 处于 low/urgent 状态，仲裁器可能优先补读重传数据，写侧还要再等待一次读服务：

```text
256 beat / 300MHz ~= 0.85us
```

加上读命令握手、读延迟和读写切换，单次 replay 对写侧最坏不服务时间的额外影响可按约 `1.5us ~ 2us` 估算。
因此考虑 replay 后，写侧更保守估算取：

```text
T_write_block_worst_with_replay ~= 3.5us ~ 4us
```

该值适用于偶发单次 replay。若 `rp_back_en` 高频连续触发，最坏写不服务时间应以仿真或 ILA 中
`wr_no_service_max`、`rp_back_en`、`block_for_replay` 的实测值重新校准。

## 5. 最坏 DDR 不返回读数据时间估算

这里的“不返回读数据时间”定义为：

```text
从读 FIFO 进入 urgent/low 水位并允许发起 DDR 读
到 DDR/MIG 用户口开始返回读数据
```

即 AXI 版本中到 `m_axi_rvalid && m_axi_rready` 第一次有效，或 native 版本中到
`app_rd_data_valid` 第一次有效。

### 5.1 DDR 颗粒侧原因

| 原因 | 估算 |
| --- | --- |
| 当前不可中断写 burst 剩余时间 | 256 beat 按 `tCCD_S` 估算约 `853ns`，按 `tCCD_L` 估算约 `1280ns` |
| Write-to-Read turnaround | 同 Bank Group 约 `26CK ~= 21.66ns`，不同 Bank Group 约 `20CK ~= 16.66ns` |
| Refresh 阻塞 | 16Gb DDR4 1x refresh 下 `tRFC1 = 350ns` |
| 读目标 row miss | `tRP + tRCD ~= 28.32ns` |
| READ 命令到首数据 | `CL = 17CK ~= 14.16ns`，用户口还会包含 PHY/MIG 管线延迟 |

不遇到 refresh 的普通保守路径：

```text
853ns + 16.66ns + 28.32ns + 14.16ns ~= 912ns
```

同 Bank Group、遇到 refresh、row miss 的更保守路径：

```text
1280ns + 21.66ns + 350ns + 28.32ns + 14.16ns = 1694.14ns ~= 1.7us
```

### 5.2 MIG IP / 用户口原因

读侧用户口看到的不返回数据还包括：

```text
AXI AR ready 或 native app_rdy 等待读命令接收
MIG 内部读命令排队和 Bank 调度
读命令被接受后到 AXI rvalid / native app_rd_data_valid 的 PHY 和控制器管线
读 FIFO full/prog_full 导致的本工程侧限流
```

因此不含 replay 的读侧保守估算取：

```text
T_read_return_worst_no_replay ~= 2us
```

### 5.3 重传 / replay 原因

replay 对“读不返回数据”的影响有两面：

```text
1. rp_back_en 期间，新命令被 block_for_replay 暂停，读命令也不会立即发出；
2. replay 结束后，读指针回退，读侧可读范围变大，系统可能需要优先补回历史数据。
```

单次 replay 的硬阻塞仍约为：

```text
255 ui_clk cycle / 300MHz ~= 0.85us
```

因此若读 FIFO 正在等待补数据，replay 会把读命令发起时间往后推迟约 `0.85us`，并叠加正常读返回时间。
保守可按：

```text
T_read_return_worst_with_replay ~= 3us
```

如果 replay 高频触发，应使用 `rd_no_service_max` 和 `rd_data_wait_max` 区分：

```text
rd_no_service_max：系统视角读侧没有获得数据的连续时间
rd_data_wait_max：读命令已被 MIG 接受后，等待 app_rd_data_valid / rvalid 的连续时间
```

## 6. 与系统侧 3.2GB/s 速率的关系

当前系统侧写 FIFO 写入速率：

```text
200MHz * 16 Byte = 3.2GB/s
```

在 `T_write_block_worst_no_replay = 2us` 假设下，写 urgent 后的剩余空间对应的临界输入速率为：

```text
按 1536 beat:
24576 Byte / 2us = 12,288,000,000 Byte/s = 12.288GB/s
```

这表示：如果写 FIFO 已经到 `WR_LEVEL_URGENT`，并且 DDR 接下来整整 `2us`
完全不消耗写 FIFO，那么上游平均写入速率超过约 `12.288GB/s`，才会在这段阻塞窗口内填满
约 24KiB 剩余空间并触发 overflow。

在 `2us` 内系统侧写入数据量为：

```text
3.2GB/s * 2us = 6400 Byte ~= 6.25KiB
```

若考虑单次 replay，把写侧最坏不服务时间保守放大到 `4us`：

```text
3.2GB/s * 4us = 12800 Byte = 12.5KiB
12800 Byte / 16 Byte = 800 beat
```

该值仍小于写 urgent 后的剩余空间：

```text
1536 beat - 800 beat = 736 beat
736 beat * 16 Byte = 11776 Byte = 11.5KiB
```

读侧同理，若 GTY 读 FIFO 接口以 `128.90625 beat/us` 持续消费：

```text
2us 消耗：257.8125 beat
3us 消耗：386.71875 beat
```

这些值都小于 `RD_LEVEL_URGENT = 1024 beat`。
读 FIFO high 到 full 的余量为：

```text
4096 - 3072 = 1024 beat
DDR 写入读 FIFO：300 beat/us
GTY 读出读 FIFO：128.90625 beat/us
净增长：171.09375 beat/us
1024 / 171.09375 ~= 5.98us
```

## 7. 结论

在当前 MIG DDR4-2400 配置和系统侧 200MHz x 16Byte 条件下：

```text
不含 replay 的最坏 DDR 不服务写时间：保守取 2us
考虑偶发单次 replay 的最坏 DDR 不服务写时间：保守取 3.5us ~ 4us
不含 replay 的最坏 DDR 不返回读数据时间：保守取 2us
考虑偶发单次 replay 的最坏 DDR 不返回读数据时间：保守取 3us
写 FIFO urgent 后剩余空间：约 24KiB
读 FIFO urgent 时已有缓存：1024 beat = 16KiB，约 7.94us GTY 续航
读 FIFO high 到 full 剩余空间：1024 beat，约 5.98us 净增长余量
系统侧持续写入速率：3.2GB/s
GTY 等效持续读取速率：128.90625 beat/us
2us 内系统侧写入数据量：约 6.25KiB
4us 内系统侧写入数据量：约 12.5KiB
```

因此，当前写侧 `WR_LEVEL_URGENT = 2560` 和读侧 `RD_LEVEL_URGENT = 1024`
都留有安全空间。按不含 replay 的 2us 最坏阻塞估算，写侧约有 3 倍以上余量：

```text
24KiB / 6.25KiB ~= 3.84
```

按考虑偶发 replay 的 4us 写侧阻塞估算，写侧仍约有：

```text
24KiB / 12.5KiB ~= 1.92
```

需要注意：上述 replay 估算针对偶发单次重传。如果 `rp_back_en` 连续频繁触发，或 MIG 用户口出现远超
上述估算的 backpressure、refresh 策略变化、系统级仲裁异常，应通过仿真或 ILA 实测重新校准：

```text
wr_no_service_max
rd_no_service_max
rd_data_wait_max
rp_back_en
block_for_replay
```
