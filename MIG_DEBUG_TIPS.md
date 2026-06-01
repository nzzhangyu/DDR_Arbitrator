# MIG IP Debug Tips

本文总结 MIG DDR4 IP 核常见调试经验，重点用于从错误现象反推问题层级。适用于本仓库的两种 DDR4 接口实现：

- `axi/`: AXI4 MIG 接口。
- `native/`: native MIG `app_*` 接口。

调试时建议先确认 MIG 初始化和基础握手，再逐步扩大测试复杂度。不要一开始就满速跑复杂读写混合流量，否则多个问题会叠在一起，很难定位。

## 1. 总体排查顺序

推荐从外到内排查：

```text
1. init_calib_complete 是否拉高
2. ui_clk_sync_rst 是否释放
3. 单地址、单 beat 写读是否正确
4. 连续地址、单 beat 写读是否正确
5. 连续地址、burst 写读是否正确
6. 读写混合是否正确
7. backpressure 下是否正确
8. 满速压力测试是否正确
```

如果 `init_calib_complete` 一直不高，优先检查 MIG 配置、DDR4 管脚约束、时钟、复位和板级连接。此时不要先怀疑用户读写状态机。

如果 `init_calib_complete` 已经拉高，但读写错误，再重点检查接口握手、地址、突发长度、数据位宽、FIFO 水位和仲裁逻辑。

## 2. 快速判断表

```text
所有地址都错
=> 时钟、复位、接口协议、数据位宽、mask、写事务没真正完成

固定 bit 错
=> DQ/DQS 约束、板级连线、byte lane、数据拼接顺序

固定地址范围错
=> 地址单位、地址位宽、突发边界、bank/row/column 映射

偶发错
=> 时序收敛、CDC、FIFO 边界、valid/ready 保持、握手丢拍

写完立即读错
=> 写响应没等、读写顺序没保证、缓存/回放逻辑、FIFO 未排空

压力下才错
=> backpressure、水位阈值、仲裁饥饿、burst 切换、pending transaction
```

## 3. 所有地址都错

### 典型表现

```text
写 0x00000000，读回不是 0
写 0xFFFFFFFF，读回不是 FFFFFFFF
写 0xA5A55A5A，所有地址读回都不对
每个地址都错，而且没有明显规律
```

### 常见原因

- MIG 没有真正初始化完成。
- 用户逻辑复位没有正确释放。
- 写命令、写数据或读命令没有完成握手。
- AXI `awlen/wlast` 或 native `app_wdf_end` 不匹配。
- 用户侧数据位宽和 MIG 侧数据位宽拼接错误。
- byte enable / mask 使用错误。
- 写数据根本没有进入 MIG，读回的是旧数据或无效数据。

### AXI 接口重点检查

完整写事务至少包括：

```text
AW handshake
所有 W beat handshake
最后一个 W beat 带 WLAST
B response 返回并被 BREADY 接收
```

重点抓：

```verilog
s_axi_awvalid
s_axi_awready
s_axi_awaddr
s_axi_awlen

s_axi_wvalid
s_axi_wready
s_axi_wdata
s_axi_wstrb
s_axi_wlast

s_axi_bvalid
s_axi_bready
s_axi_bresp

s_axi_arvalid
s_axi_arready
s_axi_araddr
s_axi_arlen

s_axi_rvalid
s_axi_rready
s_axi_rdata
s_axi_rlast
s_axi_rresp
```

### Native `app_*` 接口重点检查

native 接口要分别确认命令通道和写数据通道都被 MIG 接收：

```text
app_en && app_rdy
=> 命令被接收

app_wdf_wren && app_wdf_rdy
=> 写数据被接收

app_rd_data_valid
=> 读数据有效
```

重点抓：

```verilog
app_en
app_rdy
app_cmd
app_addr

app_wdf_wren
app_wdf_rdy
app_wdf_data
app_wdf_mask
app_wdf_end

app_rd_data_valid
app_rd_data
app_rd_data_end
```

### 建议排查步骤

```text
1. 确认 init_calib_complete = 1
2. 确认 ui_clk_sync_rst 已释放
3. ILA 抓一次完整写事务和完整读事务
4. 检查写命令、写数据、写响应是否都完成
5. 检查读命令、读数据、读结束是否都完成
6. 检查数据位宽拼接、byte enable 和 mask
```

## 4. 固定 bit 错

### 典型表现

```text
写 0xFFFFFFFF，读回 0xFFFFFFFE
写 0x00000000，读回 0x00000001
某一位总是反
某一位总是 0 或总是 1
某一个 byte lane 总是错
```

### 常见原因

- DQ 管脚约束错误。
- DQS 和 DQ 分组错误。
- byte lane 映射错误。
- 板级连线和 XDC 不一致。
- RTL 数据拼接顺序错误。
- 查看波形或 ILA 时 endian 理解错误。

### 判断方法

```text
单个 bit 永久卡 0 或卡 1
=> 更像 DQ 连接、约束、IO、焊接或映射问题

一个 byte lane 全错
=> 更像 byte lane、DQS、DM/DBI、数据打包顺序问题

bit 顺序反了或互换
=> 更像 RTL 拼接顺序或管脚映射顺序问题
```

### 推荐测试 pattern

使用 walking 1 / walking 0 测试：

```text
0000_0001
0000_0002
0000_0004
0000_0008
...
FFFF_FFFE
FFFF_FFFD
FFFF_FFFB
FFFF_FFF7
...
```

如果写 `bit[3] = 1`，却总是在 `bit[5]` 读到 1，说明 bit 映射可能交换了。

如果某个 8 bit 范围整体错，优先检查对应 byte lane 的 DQS、DM/DBI、XDC 和数据拼接。

## 5. 固定地址范围错

### 典型表现

```text
低地址正常，高地址异常
每隔固定大小出现错误
每跨 4KB 边界出现错误
某一段连续地址全错
某些 bank/row 范围异常
```

### 常见原因

- byte address 和 word address 混用。
- 地址递增单位错误。
- AXI burst 跨越 4KB boundary。
- native `app_addr` 对齐位处理错误。
- 地址高位被截断。
- row/bank/column 位映射理解错误。
- burst 起始地址没有按数据宽度对齐。

### 地址单位

AXI `awaddr/araddr` 是 byte address。

例如 MIG 用户侧数据宽度是 256 bit，也就是 32 byte。如果每个 beat 之后地址应该前进一个数据 beat，则地址递增单位应该是：

```text
256 bit / 8 = 32 byte
```

如果内部逻辑按 word index 计数，却直接送给 AXI byte address，就会出现地址错位。

### AXI 4KB boundary

AXI burst 不能跨越 4KB 边界。比如从：

```text
0x0000_0FF0
```

开始一个 256 byte burst，会跨过：

```text
0x0000_1000
```

这类事务不应该直接发出。需要限制 burst 长度，或者在边界前拆分事务。

### 建议排查步骤

```text
1. 抓 awaddr/araddr 或 app_addr
2. 检查每次地址递增是否等于数据字节数乘以 burst beat 数
3. 检查 burst 起点和终点是否跨 4KB
4. 检查地址高位是否被截断
5. 分别测试低地址、高地址、跨边界地址
6. 检查读写地址计数器是否使用同一种单位
```

## 6. 偶发错

### 典型表现

```text
跑 100 次，有 1 次错
低速正常，高速错
仿真正常，上板偶发错
空闲时正常，连续读写时偶发错
某次读回数据来自上一笔或下一笔
```

### 常见原因

- 时序没有收敛。
- 跨时钟域 CDC 不可靠。
- FIFO full/empty 边界处理错误。
- valid/ready 握手时 payload 没有保持稳定。
- 状态机在 backpressure 下提前跳转。
- 读数据返回顺序处理不严谨。
- 复位释放不同步。

### 握手保持原则

AXI 规则要求：

```text
valid 拉高后，在 ready 到来前，payload 必须保持稳定。
```

也就是说，`awvalid` 拉高后，只要 `awready` 还没拉高，`awaddr/awlen/awsize` 就不能变化。

native 接口同理：

```text
app_en 等待 app_rdy 时，app_cmd/app_addr 必须保持稳定。
app_wdf_wren 等待 app_wdf_rdy 时，app_wdf_data/app_wdf_end/app_wdf_mask 必须保持稳定。
```

### CDC 检查

如果有其他时钟域信号进入 `ui_clk` 域，不能直接用单周期 pulse 传递。建议使用：

- 异步 FIFO。
- toggle 同步。
- ready/valid 跨域握手。
- 双触发同步，仅用于单 bit 慢速电平信号。

### 建议排查步骤

```text
1. 查看 Vivado timing report，确认 WNS/TNS 没有违例
2. 检查所有跨时钟信号是否经过可靠 CDC
3. ILA 触发 overflow、underflow、error flag
4. 在仿真中随机拉低 ready，模拟 backpressure
5. 检查 valid 等待 ready 时 payload 是否保持稳定
6. 对 FIFO almost_full/almost_empty 边界做压力测试
```

## 7. 写完立即读错

### 典型表现

```text
写地址 A
马上读地址 A
读回旧数据或错误数据
延迟一会儿再读就正确
连续写完再读，前几笔错
```

### 常见原因

- 没有等写事务真正完成。
- AXI `B` 响应还没有返回。
- native 写命令和写数据还没有都被 MIG 接收。
- 写 FIFO 中还有数据没有送入 MIG。
- 仲裁刚从写切到读，但写侧还有 pending transaction。
- read replay / backtracking 逻辑拿到旧地址或旧数据。
- 读写顺序没有被状态机保证。

### AXI 写完成判断

不要只看到 `awready` 就认为写完成。AXI 写完成至少需要：

```text
1. AW handshake 完成
2. 所有 W beat handshake 完成
3. 最后一个 W beat 带 WLAST
4. BVALID/BREADY handshake 完成
5. BRESP 没有错误
```

### Native 写完成判断

native 接口里至少要确认：

```text
1. 写命令通过 app_en && app_rdy 被接收
2. 写数据通过 app_wdf_wren && app_wdf_rdy 被接收
3. app_wdf_end 与该写事务最后一个 beat 对齐
4. 写侧 FIFO 或内部 pending 计数已经清空到安全状态
```

### 最小验证方法

```text
1. 写单地址
2. 等写响应或写完成标志
3. 空等若干 ui_clk
4. 再读同一地址
5. 比较读回数据
```

如果加等待后正确，通常说明 DDR 本体问题不大，问题更可能在事务完成判断、读写顺序、FIFO 排空或仲裁切换。

## 8. 压力下才错

### 典型表现

```text
单次读写正常
低频请求正常
FIFO 快满时错
连续 burst 时错
读写频繁切换时错
长时间运行后错
```

### 常见原因

- backpressure 处理不完整。
- FIFO 水位判断晚了一拍。
- almost_full / almost_empty 阈值太激进。
- burst 长度和 FIFO 可用空间不匹配。
- 当前 burst 没结束就切换读写方向。
- ready 拉低时地址或计数器提前递增。
- 读写仲裁导致某一路长期饥饿。
- pending transaction 计数不准确。

### 本仓库重点关注

本仓库 AXI 和 native 两个版本都保留：

- XPM FIFO buffering。
- Dynamic watermarks。
- Arbitration。
- Read replay / backtracking。

压力测试时重点抓：

```text
写 FIFO 水位
读 FIFO 水位
almost_full / almost_empty
overflow / underflow
当前仲裁方向
burst beat 计数
读写地址计数器
pending write / pending read
read replay / backtracking 状态
```

### 仲裁切换检查点

```text
切到写方向前，写 FIFO 数据是否足够组成一个 burst？
切到读方向前，读 FIFO 空间是否足够接收一个 burst？
当前 burst 是否完整结束后才允许切方向？
ready 拉低时，地址和计数器有没有提前递增？
是否存在已经发出读命令但读 FIFO 空间不足的情况？
是否存在已经启动写 burst 但写 FIFO 数据不够的情况？
```

### 建议排查步骤

```text
1. 把 burst 长度先降到 1，验证是否稳定
2. 逐步增加 burst 长度
3. 人为制造 ready 随机拉低的仿真
4. ILA 触发 FIFO overflow/underflow
5. 抓仲裁状态、burst_count、addr_counter
6. 检查切换读写方向时是否有 pending transaction
7. 长时间运行并统计首个错误发生前的状态
```

## 9. 推荐测试 pattern

从简单到复杂：

```text
固定地址写读：
0x00000000
0xFFFFFFFF
0xA5A55A5A
0x5A5AA5A5

地址相关数据：
data = address
data = ~address
data = address ^ 0xA5A55A5A

位测试：
walking 1
walking 0

连续地址：
递增地址单 beat
递增地址 burst
跨 4KB 前后的边界地址
低地址、中间地址、高地址

压力测试：
连续写后连续读
读写交替
随机读写
随机 backpressure
FIFO 接近 full/empty 的边界测试
```

## 10. ILA 触发建议

### 初始化类触发

```verilog
init_calib_complete
ui_clk_sync_rst
```

### AXI 错误触发

```verilog
s_axi_bvalid && (s_axi_bresp != 2'b00)
s_axi_rvalid && (s_axi_rresp != 2'b00)
fifo_overflow
fifo_underflow
error_flag
```

### Native 错误触发

```verilog
fifo_overflow
fifo_underflow
error_flag
app_en && !app_rdy
app_wdf_wren && !app_wdf_rdy
```

`app_en && !app_rdy` 或 `app_wdf_wren && !app_wdf_rdy` 本身不一定是错误，但很适合观察 backpressure 下状态机是否保持 payload 稳定。

## 11. 最重要的调试原则

每次只放大一个维度：

```text
先固定地址、固定数据、单 beat
再连续地址、单 beat
再连续地址、burst
再加读写混合
再加 backpressure
最后加满速压力
```

这样可以明确知道错误是从哪一步开始出现的。

MIG 调试最怕一开始就是全功能满速跑。那时所有问题都会叠在一起，看起来像 DDR 本体不稳定，但真实原因可能只是一个 `valid` 提前撤销、一个地址单位算错、一个 FIFO 水位晚判断了一拍，或者一个读写切换时的 pending transaction 没处理干净。
