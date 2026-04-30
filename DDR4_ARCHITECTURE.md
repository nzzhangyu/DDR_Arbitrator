# DDR4 架构说明

这份文档记录当前工作区里的 DDR4 RTL 架构，重点放在几天不看就容易忘的部分：数据流、ping-pong 缓冲、水位仲裁、burst 计算，以及最常复用信号的含义。

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
  - 用户侧缓冲和命令生成器的连接。
  - 写侧 overrun 监控。
- `ddr4_controller.sv`
  - 用户 AXI 和 MIG AXI 之间的顶层桥接。
  - 把 DDR 状态反馈给用户侧输出。
- `ddr_wr_2bank_pingpong.sv`
  - 写侧 2 bank ping-pong 缓冲。
- `ddr_rd_2bank_pingpong.sv`
  - 读侧 2 bank ping-pong 缓冲，目前还是独立模块。
- `ddr_cache_and_frame_gen.sv`、`header_frame_gen.sv`、`reading_header_slice_gen.sv`
  - header、slice 和 view 的重建逻辑。

## 2. 数据流

### 写路径

`data_from_ddr_dd` 和 `data_from_ddr_en` 从 `clk` 进入写侧 ping-pong。

- 活动 bank 会一直收数据，直到达到 `8192 beat`。
- 如果 bank 写满，或者收到 flush / idle timeout，bank 就会提交给读侧。
- 如果另一个 bank 还空闲，写侧会立刻切过去继续收数据。

写侧 ping-pong 对外暴露的是：

- `dout`：给 AXI 写通道的数据
- `valid`：表示当前有一个 beat 可读
- `rd_en`：AXI 接收后弹出一个 beat
- `empty`、`full`、`prog_empty`、`rd_data_count`：压力状态指示

### 读路径

读侧 ping-pong 目前是独立模块，还没有接回顶层桥接。

- DDR 读返回的数据从 `wr_data/wr_valid` 进入模块。
- 完成提交的 bank 按顺序释放。
- 内部带一个小 skid buffer，用来隐藏 XPM RAM 的读延迟，并保持 `rd_valid` 稳定。

这个读侧模块后续可以在读数据流从当前 cache 路径拆出来时接入。

### AXI 路径

当前 AXI 命令生成器把 DDR 访问当作标准 AXI4 master 流来处理：

- `AW` 发起写 burst。
- `W` 从写侧 ping-pong 逐 beat 发数据。
- `B` 结束写事务。
- `AR` 发起读 burst。
- `R` 把读数据返回给用户侧。

因为 AXI 的 burst 边界是明确的，所以仲裁可以按 burst 粒度做，不需要抢占单个 beat。

## 3. Ping-Pong 数值

当前 ping-pong 模块使用：

- `DATA_WIDTH = 128 bit`
- `BANK_DEPTH = 8192 beat`
- `BANK_NUM = 2`

因此：

- 1 beat = 128 bit = 16 byte
- 256 beat = 4096 byte = 4 KiB
- 8192 beat = 131072 byte = 128 KiB
- 2 bank = 16384 beat = 262144 byte = 256 KiB

所以写侧有足够的空间吸收上游突发，同时也能让 AXI 以中等长度 burst 持续搬运。

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

读侧目前则使用 grant 限制和 cache 空间检查，保证 burst 不会把下游空间顶爆。

## 5. Slice、View 和 Header

设计里有三个容易混淆的概念：

- `slice`：上游数据流里的帧单位。
- `view`：多个 slice 组成的更大逻辑单位。
- `header`：读侧用来识别和重建这些单位的元数据。

DDR 这一层本身是按 beat 处理的。slice 和 view 的边界，不是由 DDR 存储单元决定的，而是由外面的 header / frame 逻辑来处理。

所以 ping-pong 模块故意做成 beat-oriented，而不是 slice-oriented。这样不会因为强行按 slice 划分而浪费带宽。

## 6. 信号速查

| 信号 | 含义 |
| --- | --- |
| `data_from_ddr_en` | `clk` 域上的上游写 beat 有效 |
| `data_from_ddr_dd` | 上游写数据 |
| `ddr_wr_fifo_valid` | 写侧 ping-pong 当前有一个有效 beat 可供 AXI 使用 |
| `ddr_wr_fifo_empty` | 没有可见给 AXI 写路径的提交数据 |
| `ddr_wr_fifo_prog_empty` | 当前写数据还不足以形成一个舒服的 burst |
| `ddr_wr_fifo_level` | 近似表示当前可见 / 已提交的写 beat 数 |
| `ddr_wr_fifo_rd_en` | 从写侧 ping-pong 弹出一个 beat |
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
| `cache_fifo_prog_full` | 下游 cache 接近满 |
| `cache_fifo_almost_empty` | 下游 cache 接近空 |

## 7. 建议的阅读顺序

如果想快速重新搭起整个架构，建议按这个顺序看：

1. `DDR4_ARCHITECTURE.md`
2. `ddr4_controller.sv`
3. `user_app_top.sv`
4. `user_rw_cmd_gen.sv`
5. `ddr_wr_2bank_pingpong.sv`
6. `ddr_rd_2bank_pingpong.sv`

这个顺序和真实的数据路径是一致的：先看顶层桥接，再看缓冲，再看仲裁。
