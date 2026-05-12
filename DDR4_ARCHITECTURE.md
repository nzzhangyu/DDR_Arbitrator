# DDR4 架构说明

这份文档记录当前工作区的 DDR4 RTL 架构。仓库现在同时保存两套并行实现：

- `axi/`：当前稳定的 AXI4 MIG 接口版本。
- `native/`：额外提供的 native MIG `app_*` 接口版本。

两个目录下都保持 `rtl/` 和 `sim/` 结构，并且文件名相同。区分接口版本时看目录，不看文件名后缀。

## 1. 系统总览

两套实现的用户侧数据流保持一致：

1. 用户侧突发数据从 `clk` 写入 DDR 写侧 FIFO。
2. DDR 访问逻辑在 `ui_clk` 上根据 FIFO 水位做读写仲裁。
3. DDR 读回数据进入读侧 FIFO，再由用户侧通过 `user_r_rd_en` 拉取。
4. replay / backtracking 通过 `rp_back_en` 和 `rp_back_view_addr` 回退读指针。

差异只在 MIG 边界：

- `axi/rtl/user_rw_cmd_gen.sv` 输出 AXI4 `AW/W/B/AR/R`。
- `native/rtl/user_rw_cmd_gen.sv` 输出 MIG native `app_*`。

## 2. 目录与模块

### AXI 版本

- `axi/rtl/user_rw_cmd_gen.sv`
  - AXI4 命令生成。
  - 基于水位的仲裁。
  - burst 大小计算和地址跟踪。
- `axi/rtl/user_app_top.sv`
  - XPM FIFO 缓冲和 AXI 命令生成器连接。
- `axi/rtl/ddr4_controller.sv`
  - 用户桥和 AXI 版 `ddr4_1200m` MIG 顶层连接。
- `axi/sim/ddr4_fast_mock.sv`
  - AXI 快速内存模型。
- `axi/sim/sim_mig/ddr4_1200m_sim_netlist.v`
  - 当前已提交的 AXI 版真实 MIG 仿真网表。

### Native 版本

- `native/rtl/user_rw_cmd_gen.sv`
  - native `app_*` 命令生成。
  - 复用与 AXI 版本一致的水位、仲裁、地址计数、replay 和告警逻辑。
- `native/rtl/user_app_top.sv`
  - XPM FIFO 缓冲和 native 命令生成器连接。
- `native/rtl/ddr4_controller.sv`
  - 用户桥和 native 版 `ddr4_1200m` MIG 顶层连接。
- `native/sim/ddr4_fast_mock.sv`
  - native `app_*` 快速内存模型。
- `native/sim/tb_ddr4_controller_mock.sv`
  - native 版本快速功能 testbench。

## 3. FIFO 与水位

两套实现都使用相同 FIFO 策略：

- 写侧 FIFO：`clk` 写入，`ui_clk` 读出。
- 读侧 FIFO：`ui_clk` 写入，`clk` 读出。
- 数据宽度：`128 bit`。
- FIFO 深度：`16384 beat`。

主要水位阈值保持一致：

- `WR_LEVEL_HIGH = 8192`
- `WR_LEVEL_URGENT = 12288`
- `RD_LEVEL_URGENT = 4096`
- `RD_LEVEL_LOW = 8192`
- `RD_LEVEL_HIGH = 12288`

`WR_LEVEL_HIGH` 在写 FIFO 压力高时缩短读服务，让写侧更快回到仲裁；
`WR_LEVEL_URGENT` 在写 FIFO 紧急时禁止普通读并强制优先写。读侧水位
继续用于低水位及时预取和高水位停止预取。

## 4. AXI 与 Native 边界

AXI 版本按 AXI burst 工作：

- `AW` 发起写地址。
- `W` 连续发送写数据。
- `B` 结束写事务。
- `AR` 发起读地址。
- `R` 接收读数据。

Native 版本按 MIG app request 工作：

- 写命令：`app_cmd = 3'b000`，`app_en && app_rdy` 接收一个写命令。
- 写数据：`app_wdf_wren && app_wdf_rdy` 接收一个 128-bit 写数据 beat。
- 读命令：`app_cmd = 3'b001`，`app_en && app_rdy` 接收一个读命令。
- 读数据：`app_rd_data_valid` 返回一个 128-bit 读数据 beat。
- `app_wdf_mask = 16'h0000` 表示写入所有字节。

Native 版本仍按内部 `write_burst_len` / `read_burst_len` 做成组服务，但每个 beat 在 MIG native 口上对应一次 app command。这样保留原有仲裁粒度，同时避免把 AXI burst 概念泄漏到 native MIG 端口。

## 5. 地址模型

内部地址按 128-bit beat 计数。两套实现默认都在接口边界转换成 byte address：

- AXI helper：`beat_addr << 4`
- native helper：`beat_addr << 4`

如果重新生成的 native MIG IP 端口使用不同地址位宽或低位规则，只需要调整 `native/rtl/user_rw_cmd_gen.sv` 里的地址 helper 和 `APP_ADDR_WIDTH` 参数。

## 6. 验证模式

AXI fast mock 回归使用：

- `axi/sim/ddr4_fast_mock.sv`
- `axi/rtl/user_rw_cmd_gen.sv`
- `axi/rtl/user_app_top.sv`
- `axi/sim/tb_ddr4_controller_mock.sv`

Native fast mock 回归使用：

- `native/sim/ddr4_fast_mock.sv`
- `native/rtl/user_rw_cmd_gen.sv`
- `native/rtl/user_app_top.sv`
- `native/sim/tb_ddr4_controller_mock.sv`

AXI real MIG 验证继续使用 `axi/sim/sim_mig/` 中的 AXI 网表。Native real MIG 验证需要从 Vivado 另行导出 native/application-interface MIG 仿真文件。

## 7. 阅读顺序

建议按版本分别阅读：

1. `axi/rtl/ddr4_controller.sv` 或 `native/rtl/ddr4_controller.sv`
2. `axi/rtl/user_app_top.sv` 或 `native/rtl/user_app_top.sv`
3. `axi/rtl/user_rw_cmd_gen.sv` 或 `native/rtl/user_rw_cmd_gen.sv`
4. 需要理解 header / frame / cache 时，再看同版本目录下的其他 RTL 文件。
