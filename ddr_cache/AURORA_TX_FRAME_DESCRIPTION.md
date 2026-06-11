# aurora_tx_frame 模块说明

## 1. 总体功能

`aurora_tx_frame` 是 `ddr_cache` 中 Aurora TX 侧的帧控制核心。它接收 DDR FIFO 数据、idle frame 数据、refresh 请求和 Aurora ready 信号，决定当前发送 normal、idle 或 refresh frame，并产生 Aurora LocalLink 风格的 `tx_*` 输出、FIFO 读使能、idle 数据生成控制、CRC 控制和诊断状态。

这个模块负责帧时序和数据选择，不直接生成 DDR 数据，也不直接生成 idle payload 的具体内容。normal 数据来自 `aurora_frame_fifo_dout`，idle 数据来自 `idle_data_out`，refresh 固定控制字在本模块内部生成。

## 2. 代码层级

![aurora_tx_frame 代码层级](images/aurora_tx_frame_hierarchy.svg)

| 层级 | 逻辑块 | 主要职责 |
| --- | --- | --- |
| 顶层模块 | `aurora_tx_frame` | 组织 normal、idle、refresh 发送并输出 Aurora TX 信号 |
| 宽度相关参数 | width-dependent limits | 根据 `TX_DATA_WIDTH_32` 设置 SOF/EOF/header/slice 计数上限 |
| 同步与复位 | CDC / reset / channel ready | 同步 reset、channel up、refresh 和 1us tick |
| 触发控制 | frame trigger control | 产生 normal/idle frame 请求，控制帧间节奏 |
| 计数器 | counters | 统计 SOF、EOF、header、slice、refresh 和 slice 间隔 |
| 主状态机 | main FSM | 控制 header frame、slice frame 和 refresh frame 状态跳转 |
| FIFO/valid | FIFO read and TX valid | 预读 FIFO，并对齐 `tx_src_rdy_out` |
| 帧字段控制 | frame field controls | 输出 header/slice/footer/CRC/idle 控制信号 |
| 数据选择 | TX output select | 选择 refresh、idle 或 FIFO 数据输出到 `tx_d_out` |
| 诊断 | diagnostic outputs | 检查 frame tag、输出 first view 和 no-EOF watchdog |

## 3. 模块功能介绍

### 3.1 宽度相关参数

模块通过 `TX_DATA_WIDTH_32` 宏切换 32-bit 和 64-bit TX 数据路径。

32-bit 模式下：

- `sof_pre_cnt_lim = 1`
- `sof_cnt_lim = 1`
- `eof_cnt_lim = 1`
- `header_cnt_lim = 61`
- `slice_data_cnt_lim = slice_length_tx[11:1] + 1`

64-bit 模式下：

- `sof_pre_cnt_lim = 0`
- `sof_cnt_lim = 0`
- `eof_cnt_lim = 0`
- `header_cnt_lim = 30`
- `slice_data_cnt_lim = slice_length_tx[11:2]`

这表示同样的数据量在 32-bit 模式下需要更多 beat，而 64-bit 模式下每个 beat 承载更多数据。

### 3.2 CDC、复位和 ready 同步

该模块工作主体在 `gtx_user_clk_in` 时钟域。输入控制信号会先同步或派生：

- `TX_CHANNEL_UP_in` 经过三级寄存后形成 `tx_channel_up_gtx_d3`。
- `tx_dst_rdy = (~tx_dst_rdy_n_in) & tx_channel_up_gtx_d3`，表示 Aurora 可以接收数据。
- `rst_local_t_gtx_clk` 采样后取反形成 `rst_local`。
- `rst_local_t_ddr_clk` 在 `ui_clk` 域延迟后参与 `fifo_reset`。
- `refresh_process_en` 同步到 GTX 域形成 `gtx_refresh_process_en`。
- `clk_40mhz_1us_in` 同步后产生 `pulse_1us_edge`。

`aurora_sw_rst` 是全局 Aurora TX 侧复位，优先清空状态机、计数器、同步寄存器和诊断逻辑。`rst_local` 则更偏本地发送过程复位，状态机在多个状态下会用它提前回到安全路径。

### 3.3 refresh 同步与 1us 节拍

`refresh_process_en` 来自通信确认逻辑，在本模块中同步到 GTX 域：

```systemverilog
refresh_process_en_gtx_d1 <= refresh_process_en;
refresh_process_en_gtx_d2 <= refresh_process_en_gtx_d1;
refresh_process_en_gtx_d3 <= refresh_process_en_gtx_d2;
```

同步后的 `gtx_refresh_process_en` 与 1us 边沿组合：

```systemverilog
assign refresh_trigger_pulse = gtx_refresh_process_en & pulse_1us_edge;
```

因此 refresh 请求是一个持续窗口，真正的 refresh frame 在 1us tick 上触发。

### 3.4 fault injection

故障注入用于验证诊断链路。`Fault_inject_en` 有效后，`fault_50ms_cnt` 按 1us tick 计数，计到阈值后打开一个短窗口。

在指定 slice 数据位置：

```systemverilog
assign fault_gen_inject_ind = fault_gen_pulse & (slice_data_cnt == 'h18);
```

输出数据会被改写为错误标记：

```systemverilog
tx_d_out = fault_gen_inject_ind ? {12'hFAE, tx_d_out_t[51:0]} : tx_d_out_t;
```

32-bit 模式下类似，只保留低 20 bit 并替换高 12 bit。

### 3.5 frame 触发控制

模块根据模式和输入状态产生 frame 请求。

normal frame 请求：

```systemverilog
assign trans_normal_frame_trig = (~idle_process_en) &
                                 (~aurora_frame_fifo_prog_empty) &
                                 head_gap_done &
                                 tail_gap_done;
```

normal frame 需要满足：

- 当前不是 idle 模式。
- FIFO 数据达到发送阈值。
- head gap 完成。
- tail gap 完成。

idle frame 请求：

```systemverilog
assign trans_idle_frame_trig = idle_process_en & idle_trig;
```

idle frame 由 `idle_frame_gen` 的 `idle_trig` 节奏触发。

frame 类型在 `IDLE` 状态锁存：

```systemverilog
if (trans_idle_frame_trig && (auro_frame_state == IDLE))
    idle_frame_ind <= 1'b1;
else if (trans_normal_frame_trig && (auro_frame_state == IDLE))
    idle_frame_ind <= 1'b0;
```

`idle_frame_ind = 0` 表示 normal frame，`idle_frame_ind = 1` 表示 idle frame。

### 3.6 主状态机

状态机可以分为 normal/idle 路径和 refresh 路径。

normal/idle 共用路径：

```text
IDLE
├── HEAD_SOF_PRE_STA
├── HEAD_SOF_PRE_STA2
├── HEAD_SOF_STA
├── HEAD_DATA_STA
├── HEAD_EOF_STA
├── WAIT_SLICE_STA
├── SLICE_SOF_PRE_STA
├── SLICE_SOF_PRE_STA2
├── SLICE_SOF_STA
├── SLICE_DATA_STA
├── SLICE_EOF_STA
├── WAIT_SLICE_STA 或 SLICE_DONE_STA
└── IDLE
```

refresh 路径：

```text
IDLE
├── REFRESH_WAIT
├── REFRESH_DATA
└── REFRESH_WAIT 或 IDLE
```

### 3.7 header 发送状态

`HEAD_SOF_PRE_STA` 是 header frame 的第一级预读状态。normal 模式下，它会拉起 `fifo_rd_en_t`，提前读 FIFO，但还不把数据视为有效发送数据。

`HEAD_SOF_PRE_STA2` 是第二级对齐状态。它继续读 FIFO，并开始拉起 `data_valid_rd_en`，为 `tx_src_rdy_out` 对齐 FIFO 输出延迟。

`HEAD_SOF_STA` 正式产生 header SOF 和 header command 控制：

```systemverilog
header_cmd_1_en
header_cmd_2_en
tx_sof_out
```

`HEAD_DATA_STA` 发送 header payload，并累加 `header_cnt`。normal 模式下数据来自 FIFO，idle 模式下 `header_en` 让 `idle_frame_gen` 输出 idle header payload。

`HEAD_EOF_STA` 发送 header frame 的 CRC/EOF，并在完成后进入 `WAIT_SLICE_STA`。

### 3.8 slice 发送状态

`WAIT_SLICE_STA` 等待 slice 发送条件。normal 模式下要求 FIFO 非 `prog_empty`，idle 模式下要求 `idle_process_en` 有效，同时还要满足 `slice_interview_cnt_rch`。

`SLICE_SOF_PRE_STA` 和 `SLICE_SOF_PRE_STA2` 对应 slice frame 的预读和 valid 对齐。normal 模式下会真正读 FIFO；idle 模式下 `fifo_rd_en` 被 `idle_frame_ind` 屏蔽，不会消耗 DDR FIFO。

`SLICE_SOF_STA` 产生 slice SOF 和 slice command 控制：

```systemverilog
slice_cmd_1_en
slice_cmd_2_en
tx_sof_out
```

`SLICE_DATA_STA` 发送 slice payload，并累加 `slice_data_cnt`。normal 模式要求 FIFO 非空且 Aurora ready；idle 模式只依赖 Aurora ready，并通过 `idle_slice_data_en` 推进 idle payload。

`SLICE_EOF_STA` 发送 slice CRC/EOF，并判断是否还有下一段 slice。如果 `slice_cnt_rch` 有效则进入 `SLICE_DONE_STA`，否则回到 `WAIT_SLICE_STA`。

`SLICE_DONE_STA` 表示一个 view 或 idle frame group 已完成，并输出：

```systemverilog
view_tx_done = (auro_frame_state == SLICE_DONE_STA) && (~rst_local);
```

### 3.9 refresh 状态

`REFRESH_WAIT` 在 refresh 请求窗口内等待 `refresh_trigger_pulse`。如果 refresh 请求撤销，则回到 `IDLE`；如果 1us tick 到来，则进入 `REFRESH_DATA`。

`REFRESH_DATA` 发送 refresh 固定控制字，并根据 `ref_data_cnt_rch` 回到 `REFRESH_WAIT`。refresh 不读 FIFO，也不使用 `idle_data_out`。

### 3.10 计数器

模块内部用多组计数器控制帧长度和状态跳转：

- `sof_pre_cnt`：预读状态计数。
- `sof_cnt`：SOF/command beat 计数。
- `eof_cnt`：EOF/CRC beat 计数。
- `header_cnt`：header payload beat 计数。
- `slice_data_cnt`：slice payload beat 计数。
- `slice_cnt`：当前 slice 序号。
- `ref_data_cnt`：refresh data beat 计数。
- `slice_interview_cnt`：slice 间隔计数。
- `head_gap_cnt` / `tail_gap_cnt`：normal frame 触发间隙控制。

normal slice 长度由 `slice_length_odd/even` 按 `slice_cnt[0]` 选择，idle slice 长度固定为 `12'h360`。normal slice 数来自 `slice_sel`，idle slice 数固定为 `8'h20`。

### 3.11 FIFO 读控制和数据有效对齐

原始读使能 `fifo_rd_en_t` 在 header/slice 的预读、SOF、DATA、EOF 等状态有效。但真正输出给 FIFO 的读使能为：

```systemverilog
assign fifo_rd_en = (~idle_frame_ind) & fifo_rd_en_t;
```

因此：

- normal frame 会读 `aurora_frame_fifo`。
- idle frame 不读 FIFO。

`data_valid_rd_en` 从 `HEAD_SOF_PRE_STA2` / `SLICE_SOF_PRE_STA2` 开始有效，用于补偿 FIFO 读延迟。它打一拍后形成 `fifo_rd_en_dly`，最终得到：

```systemverilog
assign tx_src_rdy_out = fifo_rd_en_dly & tx_dst_rdy;
```

所以 PRE 状态的作用不是保存数据到本模块寄存器，而是提前推动 FIFO 输出，让 `aurora_frame_fifo_dout` 与 `tx_src_rdy_out` 对齐。

### 3.12 header、slice、footer 和 CRC 控制

该模块向 `idle_frame_gen` 和 CRC 逻辑输出帧内位置控制信号：

- `header_cmd_1_en/header_cmd_2_en`：header command 位置。
- `header_en`：header payload 区域。
- `slice_cmd_1_en/slice_cmd_2_en`：slice command 位置。
- `idle_slice_data_en`：idle slice payload 区域。
- `footer_en/footer_1_en`：footer 附近位置。
- `clear_crc`：SOF 阶段清 CRC。
- `crc_en`：payload 阶段使能 CRC 累加。
- `crc_tx_1_en/crc_tx_2_en`：EOF 阶段输出 CRC。

32-bit 和 64-bit 模式下 CRC 累加节奏不同：32-bit 模式只在部分 beat 上累加，64-bit 模式在 header/slice data 状态下逐 beat 累加。

### 3.13 TX 输出选择

Aurora 输出控制信号为低有效：

```systemverilog
tx_sof_n_out     = ~(tx_sof_out | tx_sof_refresh);
tx_eof_n_out     = ~(tx_eof_out | tx_eof_refresh);
tx_src_rdy_n_out = ~(tx_src_rdy_out | tx_src_rdy_refresh);
tx_rem_out       = 0;
```

64-bit 模式下数据选择为：

```systemverilog
tx_d_out_t = tx_sof_refresh ? refresh_sof_word :
             tx_eof_refresh ? refresh_eof_word :
             idle_frame_ind ? idle_data_out :
             aurora_frame_fifo_dout;
```

选择优先级为：

1. refresh SOF/EOF 固定控制字
2. idle frame 的 `idle_data_out`
3. normal frame 的 `aurora_frame_fifo_dout`

最后，如果 fault injection 命中，会把输出数据高位改写为错误标记。

### 3.14 诊断和 debug 输出

模块检查 header/slice SOF 位置的 frame tag：

- slice/data frame tag 应为 `20'h4330`。
- header frame tag 应为 `20'h4331`。

不匹配时输出单周期诊断脉冲：

- `Diag_aurora_data_err_out`
- `Diag_aurora_header_err_out`

`aurora_first_view` 在 header payload 的指定 bit 上生成 first view 标记。`Diag_auroradata_en_rise_flag_out` 是 no-EOF watchdog，如果长时间没有 `tx_eof_out`，会输出诊断脉冲。

`auro_frame_state_test` 每拍输出当前状态机状态，供外部调试观察。

## 4. 主要数据流

### 4.1 normal 发送

```text
aurora_frame_fifo_dout
    -> tx_d_out_t
    -> fault injection mux
    -> tx_d_out
```

normal frame 触发后，状态机发送 1 个 header frame 和多个 slice frame。发送期间 `fifo_rd_en` 有效，DDR FIFO 数据被读出并送到 `tx_d_out`。

### 4.2 idle 发送

```text
idle_data_out
    -> tx_d_out_t
    -> fault injection mux
    -> tx_d_out
```

idle frame 触发后，状态机仍然走 header/slice 路径，但 `fifo_rd_en` 被 `idle_frame_ind` 屏蔽，不消耗 DDR FIFO。`idle_frame_gen` 根据本模块输出的 header/slice/footer/CRC 控制信号生成 `idle_data_out`。

### 4.3 refresh 发送

```text
refresh fixed word
    -> tx_d_out_t
    -> tx_d_out
```

refresh 请求优先于 normal/idle 发送路径。状态机进入 `REFRESH_WAIT` 后，在 1us tick 上进入 `REFRESH_DATA`，发送固定控制字。

## 5. 状态机路径

下图把状态机路径与实际形成的 header frame、slice frame、refresh frame 对应起来。上排是状态机状态，下排是该状态在帧结构中的作用。

![状态机与帧结构对应关系](images/aurora_tx_frame_fsm_frame_map.svg)

`HEAD_SOF_PRE_STA` 和 `SLICE_SOF_PRE_STA` 负责预读 FIFO；`HEAD_SOF_PRE_STA2` 和 `SLICE_SOF_PRE_STA2` 负责对齐 FIFO 输出和 `tx_src_rdy_out`。idle 模式下这些状态仍然保留时序，但不会真正读 FIFO。

## 6. 输出帧结构

normal 和 idle 共用 header/slice 帧结构，区别是数据来源：

![aurora_tx_frame 形成的帧结构](images/aurora_tx_frame_frame_structure.svg)

header frame 和 slice frame 在 `aurora_tx_frame` 内部由 PRE、SOF、DATA、EOF 四类阶段组成：

![header slice frame 组成](images/aurora_tx_frame_head_slice_structure.svg)

| 模式 | header/slice 数据来源 | 是否读 FIFO |
| --- | --- | --- |
| normal | `aurora_frame_fifo_dout` | 是 |
| idle | `idle_data_out` | 否 |
| refresh | 内部固定控制字 | 否 |

相关帧结构图见：

- [header frame 结构](images/header_frame_structure.svg)
- [slice frame 结构](images/slice_frame_structure.svg)
- [idle frame 结构](images/idle_frame_structure.svg)
- [idle_data_out 选择关系](images/idle_data_out_select.svg)

## 7. 时钟和复位

主要时钟域：

- `gtx_user_clk_in`：主状态机、计数器、输出选择、诊断逻辑。
- `ui_clk`：仅用于 DDR reset 延迟采样，与 FIFO reset 相关。

主要复位：

- `aurora_sw_rst`：Aurora TX 侧全局高有效复位，清状态机和大部分寄存器。
- `rst_local`：由 `rst_local_t_gtx_clk` 派生的本地发送复位，影响状态跳转和 `view_tx_done`。
- `ddr_user_rst` / `rst_local_t_ddr_clk`：参与 FIFO reset 和 DDR 侧复位路径。

## 8. 关键输出信号

| 信号 | 作用 |
| --- | --- |
| `tx_sof_n_out` | Aurora 低有效 SOF |
| `tx_eof_n_out` | Aurora 低有效 EOF |
| `tx_src_rdy_n_out` | Aurora 低有效 source ready |
| `tx_d_out` | Aurora TX 数据 |
| `fifo_rd_en` | normal frame 读 DDR FIFO 使能 |
| `view_tx_done` | 一个 normal/idle view 发送完成 |
| `idle_frame_ind` | 当前 frame 数据来源是否为 idle |
| `header_en` | header payload 区域 |
| `slice_cmd_*_en` | slice command 位置 |
| `idle_slice_data_en` | idle slice payload 区域 |
| `clear_crc` / `crc_en` | CRC 清零和累加控制 |
| `crc_tx_*_en` | CRC 输出位置 |
| `gtx_refresh_process_en` | refresh 请求同步到 GTX 域后的窗口 |
| `Diag_aurora_*` | Aurora TX 诊断脉冲 |
| `auro_frame_state_test` | 当前状态机状态观察 |

## 9. 理解要点

- `aurora_tx_frame` 负责帧时序，不负责生成 idle payload 内容。
- normal 和 idle 共用同一套 header/slice 状态机。
- normal 时 `tx_d_out` 来自 FIFO，idle 时来自 `idle_data_out`。
- idle 时状态机仍经过 PRE/SOF/DATA/EOF 状态，但 `fifo_rd_en` 被屏蔽。
- refresh 是独立状态路径，优先于 normal/idle 触发。
- PRE 状态用于提前读 FIFO 并对齐 FIFO 输出延迟，不在本模块内保存数据。
