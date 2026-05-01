# DDR4 架构说明

这份文档记录当前工作区里的 DDR4 RTL 架构，重点放在几天不看就容易忘的部分：数据流、XPM FIFO 缓冲、水位仲裁、burst 计算，以及最常复用信号的含义。

## 1. 系统总览

整个设计的数据流分成三层：

1. 用户侧的突发数据从 `clk` 进入 DDR 路径。
2. AXI4 事务在 `ui_clk` 上与 MIG 交互，完成读写搬运。
3. 用户侧的 replay、frame 和 header 逻辑再把 DDR 数据重建成 view 和 slice。

当前 RTL 已经不再使用原来的 MIG `app_*` 直接控制方式，而是统一由 AXI4 发起访问。这样更容易仿真、观察和后续扩展。

### 主要模块

- `user_rw_cmd_gen.sv`
  - AXI4 命令生成。
  - 基于水位的仲裁。
  - burst 大小计算和地址跟踪。
- `user_app_top.sv`
  - XPM FIFO 缓冲和命令生成器的连接。
  - 写侧 overrun 监控。
- `ddr4_controller.sv`
  - 用户 AXI 和 MIG AXI 之间的顶层桥接。
  - 把 DDR 状态反馈给用户侧输出。
- `ddr_wr_2bank_pingpong.sv`
  - 旧版写侧 2 bank ping-pong 缓冲，当前顶层不再实例化。
- `ddr_rd_2bank_pingpong.sv`
  - 旧版读侧 2 bank ping-pong 缓冲，当前顶层不再实例化。
- `ddr_cache_and_frame_gen.sv`、`header_frame_gen.sv`、`reading_header_slice_gen.sv`
  - header、slice 和 view 的重建逻辑。

## 2. 数据流

### 写路径

`data_from_ddr_dd` 和 `data_from_ddr_en` 从 `clk` 进入写侧 XPM 异步 FIFO。

- FIFO 深度为 `16384 beat`，宽度为 `128 bit`。
- 写端在 `clk` 域接收上游 beat，读端在 `ui_clk` 域喂给 AXI 写通道。
- `prog_empty` 阈值为 `256 beat`，用于判断是否足够形成完整 AXI burst。
- 如果上游在 FIFO 满时继续写，`wr_fifo_overrun` 会置位。

写侧 FIFO 对命令生成器暴露的是：

- `dout`：给 AXI 写通道的数据
- `valid`：表示当前有一个 beat 可读
- `rd_en`：AXI 接收后弹出一个 beat
- `empty`、`full`、`prog_empty`、`rd_data_count`：压力状态指示

### 读路径

DDR 读返回的数据先进入读侧 XPM 异步 FIFO，再由用户侧拉取。

- FIFO 写端在 `ui_clk` 域，由 AXI R 通道写入。
- FIFO 读端在 `clk` 域，通过 `user_r_rd_en` 拉取。
- `user_r_valid` 表示读后 FIFO 当前有有效数据，`user_r_empty` 表示读后 FIFO 为空。
- 仲裁使用 `ui_clk` 域的读后 FIFO 写侧水位，避免跨域采样用户侧 empty/valid。

读侧 FIFO 的 `prog_full` 和 data count 会回灌给 `user_rw_cmd_gen.sv`，用于限制新的 AR burst。

### AXI 路径

当前 AXI 命令生成器把 DDR 访问当作标准 AXI4 master 流来处理：

- `AW` 发起写 burst。
- `W` 从写侧 XPM FIFO 逐 beat 发数据。
- `B` 结束写事务。
- `AR` 发起读 burst。
- `R` 把读数据写入读侧 XPM FIFO，用户侧再按需拉取。

因为 AXI 的 burst 边界是明确的，所以仲裁可以按 burst 粒度做，不需要抢占单个 beat。

## 3. FIFO 数值

当前 DDR 前后 FIFO 使用：

- `DATA_WIDTH = 128 bit`
- `FIFO_DEPTH = 16384 beat`

因此：

- 1 beat = 128 bit = 16 byte
- 256 beat = 4096 byte = 4 KiB
- 4096 beat = 65536 byte = 64 KiB
- 8192 beat = 131072 byte = 128 KiB
- 16384 beat = 262144 byte = 256 KiB

所以写侧和读侧都有 256 KiB 的缓冲空间，用统一的 FIFO 水位驱动 AXI burst 仲裁。

### 时间换算示例

如果用户时钟是 300 MHz：

- 1 个 cycle = 3.333 ns
- 8192 个 cycle = 27.307 us
- 2048 个 cycle = 6.827 us

这些不是严格的系统固定时延，但对判断 buffer 停留时间和 idle timeout 很有帮助。

## 4. 水位与仲裁

`user_rw_cmd_gen.sv` 里当前使用的固定阈值是：

- `WR_LEVEL_LOW = 2048`
- `WR_LEVEL_HIGH = 8192`
- `WR_LEVEL_URGENT = 12288`
- `RD_LEVEL_URGENT = 4096`
- `RD_LEVEL_LOW = 8192`
- `RD_LEVEL_HIGH = 12288`

含义可以这样理解：

- `LOW`：FIFO 已经足够大，正常 drain 是有意义的。
- `HIGH`：写压力开始明显变大。
- `URGENT`：写侧应该在仲裁里优先。

当前逻辑不会在一个 AXI burst 中途打断它，只会在 burst 边界做切换。

`user_rw_cmd_gen.sv` 里的仲裁现在分成两层：

- grant 选择层：`arb_pre_grant` 和 `arb_fair_grant` 只判断下一步服务 `WRITE`、`READ` 还是暂不发起事务。
- AXI 执行状态机：根据 grant 进入 `AW/W/B` 或 `AR/R`，真正的地址推进、burst 计数和写缓存 pop 都在这里完成。

这样读代码时可以先看 grant 层理解优先级，再看状态机理解 AXI 握手时序。

### Burst 大小

当前写 burst 上限是 `256 beat`。

这意味着：

- 最大写 burst 载荷是 4 KiB。
- burst 长度足够短，仲裁还能保持灵活。
- burst 长度也足够长，可以摊薄 AXI 开销。

读侧目前使用 grant 限制和读后 FIFO 空间检查，保证 burst 不会把下游 FIFO 顶爆。

## 5. Slice、View 和 Header

设计里有三个容易混淆的概念：

- `slice`：上游数据流里的帧单位。
- `view`：多个 slice 组成的更大逻辑单位。
- `header`：读侧用来识别和重建这些单位的元数据。

DDR 这一层本身是按 beat 处理的。slice 和 view 的边界，不是由 DDR 存储单元决定的，而是由外面的 header / frame 逻辑来处理。

所以 DDR 前后 FIFO 故意做成 beat-oriented，而不是 slice-oriented。这样不会因为强行按 slice 划分而浪费带宽。

## 6. 信号速查

| 信号 | 含义 |
| --- | --- |
| `data_from_ddr_en` | `clk` 域上的上游写 beat 有效 |
| `data_from_ddr_dd` | 上游写数据 |
| `wr_fifo_valid` | 写侧 FIFO 当前有一个有效 beat 可供 AXI 使用 |
| `wr_fifo_empty` | 写侧 FIFO 没有可供 AXI 写路径使用的数据 |
| `wr_fifo_prog_empty` | 当前写数据还不足以形成一个舒服的 burst |
| `wr_fifo_rd_data_count` | 写侧 FIFO 在 `ui_clk` 域可读 beat 数 |
| `wr_fifo_rd_en` | 从写侧 FIFO 弹出一个 beat |
| `wr_has_full_burst` | 内部信号，表示写侧可见数据已经达到完整 `256 beat` burst |
| `wr_tail_age_cnt` / `wr_tail_age_reached` | 内部信号，用来避免小于 `256 beat` 的尾包长期停在写侧缓存中 |
| `clear_wr_wait_age` | 内部信号，写事务进入 `RW_WRITE_AW` 后清除写等待计数 |
| `wr_fifo_overrun` | 上游写压力溢出告警 |
| `ddr_rd_empty` | 当前没有可供用户侧读路径读取的 DDR 数据 |
| `ddr_overrun` | DDR 侧溢出 / 指针回绕类故障指示 |
| `ddr_warning` | 接近溢出的预警信号 |
| `make_data_p_edge_ddr_clk` | 同步到 `ui_clk` 后的 start 脉冲 |
| `rp_back_en` | replay / 回退请求 |
| `rp_back_view_addr` | replay 时跳回的 view 地址 |
| `rd_fifo_prog_full` | 读后 FIFO 接近满 |
| `rd_fifo_almost_empty` | 读后 FIFO 在 `ui_clk` 域水位较低 |
| `user_r_rd_en` | 用户侧从读后 FIFO 拉取一个 beat |
| `user_r_valid` | 读后 FIFO 当前输出数据有效 |
| `user_r_empty` | 读后 FIFO 当前为空 |

## 7. 验证模式

当前验证环境分成两种模式：

- 快速模式：`ddr4_mig_adapter.sv` 默认实例化 `ddr4_fast_mock.sv`，用于日常 slice/view 回归。这个模式不跑 MIG 校准，适合快速确认 AXI 写读闭环、FIFO 水位仲裁、数据顺序和 overrun/warning 标志。
- 真实 MIG 模式：定义 `USE_REAL_MIG` 后，`ddr4_mig_adapter.sv` 实例化 `ddr4_1200m` 仿真网表，并由 `tb_ddr4_controller_mig_real.sv` 连接官方 DDR4 memory model。这个模式用于观察真实 MIG calibration、AXI ready/valid backpressure 和 DDR4 物理模型连接。

两个 testbench 都按用户侧的 view/slice 数据结构生成输入：

- 1 个 view 有 `128 slice`。
- 1 个 slice 有 `2` 个 header beat 加 `180` 个 payload beat。
- 默认快速回归跑 `+views=2`，真实 MIG smoke 跑 `+views=1`。
- 长压力测试可以使用 `+scoreboard=hash`，避免保存全部 expected beat。

真实 MIG 模式明显慢于 fast mock；日常改仲裁和 FIFO 行为时优先跑 fast mock，只有需要验证 MIG 时序、校准和 backpressure 时再跑真实模型。

## 8. 建议的阅读顺序

如果想快速重新搭起整个架构，建议按这个顺序看：

1. `DDR4_ARCHITECTURE.md`
2. `ddr4_controller.sv`
3. `user_app_top.sv`
4. `user_rw_cmd_gen.sv`
5. `ddr_cache_and_frame_gen.sv`
6. `rd_cache_ctrl.sv`

这个顺序和真实的数据路径是一致的：先看顶层桥接，再看缓冲，再看仲裁。
