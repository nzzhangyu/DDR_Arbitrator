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
- `native/rtl/rw_pressure_ctrl.sv`
  - native pressure/watermark control split out from `user_rw_cmd_gen.sv`.
- `native/rtl/ddr_ring_addr_mgr.sv`
  - native circular beat-address pointers and overrun/warning status split out from `user_rw_cmd_gen.sv`.
- `native/rtl/ddr_overrun_monitor.sv`
  - legacy standalone circular-buffer overrun/warning monitor; active native path uses `ddr_ring_addr_mgr.sv`.
- `native/rtl/rw_arbiter.sv`
  - native request builder and 2:1 arbitration split out from `user_rw_cmd_gen.sv`.
- `native/rtl/rw_cmd_debug_monitor.sv`
  - native debug streak counters split out from `user_rw_cmd_gen.sv`.
- `native/rtl/user_app_top.sv`
  - XPM FIFO 缓冲和 native 命令生成器连接。
- `native/rtl/ddr4_controller.sv`
  - 用户桥和 native 版 `ddr4_1200m` MIG 顶层连接。
- `native/sim/ddr4_fast_mock.sv`
  - native `app_*` 快速内存模型。
- `native/sim/tb_ddr4_controller_mock.sv`
  - native 版本快速功能 testbench。

## 3. FIFO 与水位

两套实现都使用 XPM FIFO 跨时钟缓存：

- 写侧 FIFO：`clk` 写入，`ui_clk` 读出，数据宽度为 `128 bit`。
- AXI 读侧 FIFO：`ui_clk` 写入，`clk` 读出，输入和输出均为 `128 bit`。
- Native 读侧 FIFO：`ui_clk` 写入 `128 bit`，`clk` 读出 `64 bit`；每个 DDR beat 按高 64 位、低 64 位顺序输出。
- Native 读侧 FIFO 容量为 8192 个 128-bit 写 beat，即 16384 个 64-bit 读 word。
- Native 读侧水位、`prog_full` 和预取空间判断仍按 128-bit 写 beat 计数。

主要水位阈值保持一致：

- `WR_LEVEL_URGENT = 2560`
- `RD_LEVEL_URGENT = 1024`
- `RD_LEVEL_HIGH = 3072`

`WR_LEVEL_URGENT` 在写 FIFO 紧急时禁止普通读并强制优先写。普通写需要
写 FIFO 有完整 `WR_BURST_NUM` 或尾部 aging 到期后参与仲裁。读侧水位用于紧急补读和高水位停止预取。
当前 RTL 的读服务窗口固定：
AXI 版本为 256 beat，native 版本为 512 beat。
调度器采用单一 Grant 判断，普通场景写优先；读侧只有 urgent 或等待老化到期时才高于普通写。

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

内部地址按 128-bit beat 计数。两套实现默认都在接口边界转换成对应 MIG 端口地址：

- AXI helper：`beat_addr << 4`
- native helper：`beat_addr << 3`

AXI 地址是 byte address，因此一个 128-bit beat 需要左移 4 位。Native MIG `app_addr`
按 x16 memory interface word 计数；一个 128-bit beat 覆盖 8 个 x16 word，因此左移 3 位。
如果重新生成的 native MIG IP 端口使用不同地址位宽或低位规则，只需要调整
`native/rtl/user_rw_cmd_gen.sv` 里的地址 helper 和 `APP_ADDR_WIDTH` 参数。

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
