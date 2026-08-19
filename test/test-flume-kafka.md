# Flume → Kafka 严格集成测试说明

## 脚本与依赖

- 脚本：`test/test-flume-kafka.sh`
- 依赖：正在运行的 Flume Agent 和 Kafka 三节点集群

```bash
bash test/test-flume-kafka.sh
```

## 测试范围

在组件检查的基础上，专门验证一条消息是否真正经过 Flume Source → Memory Channel → Kafka Sink → Kafka Consumer。

## 详细测试流程

### 1. 检查必要容器

依次检查 `flume-kafka`、`kafka1`、`kafka2`、`kafka3`，任一容器未运行立即终止并指出容器名称。

### 2. 检查 Agent 和绑定

输出 Flume Java 进程并确认 `agent1`；随后验证 Source、Channel、Sink 及两条绑定关系。这里不只检查配置文件存在，而是检查关键字段内容。

### 3. 准备 Topic

确认 `flume-logs` 可访问；不存在时创建 3 分区、3 副本 Topic。日志保存完整 `--describe` 输出，便于观察 Leader、Replicas 和 ISR。

### 4. 写入唯一消息

生成 `flume-kafka-integration-<时间戳-进程号>`，写入 `/var/log/application/application.log`，再用 `tail` 回读。回读失败说明问题发生在挂载或日志写入阶段，不进入消费重试。

### 5. 三次消费验证

从 Kafka 读取历史数据并搜索唯一消息，每次最多等待十秒；未匹配则等待五秒后重试，共三次。任何一轮匹配成功即通过。

### 6. 失败诊断

三次均未匹配时输出 Agent 进程、Topic 详情、最新偏移量、Consumer 输出末尾和 Flume 最近日志，最后返回退出码 1。

## 结果判定

| 环节 | 通过条件 |
|---|---|
| 服务 | Flume 与三个 Broker 均运行 |
| 配置 | agent1 及 Source → Channel → Sink 完整 |
| 输入 | 唯一消息成功写入并可从 Source 文件回读 |
| 输出 | 三次机会内从 Kafka 精确消费到唯一消息 |

脚本在任意一轮 Kafka 消费中找到本轮唯一消息后立即返回退出码 `0`。任一前置检查失败，或三轮消费都未匹配消息，返回退出码 `1`。

## 关键命令、预期结果与通过条件

| 脚本执行的命令或检查 | 预期结果 | 该项通过条件 |
|---|---|---|
| `docker inspect` 检查四个容器 | 每个结果包含 `运行中=true` | Flume 和三个 Broker 全部运行 |
| 检查进程参数 `--name agent1` | Agent Java 命令存在且名称一致 | 进程检查成功且文本匹配 |
| `grep` 检查 Source/Channel/Sink 绑定 | 五个关键字段均匹配 | 配置检查组合命令退出码为 0 |
| `kafka-topics.sh --list/--describe` | `flume-logs` 存在或创建成功，详情可读取 | 两条 Kafka 命令均成功 |
| 写入唯一消息 | 命令退出码为 0，`tail` 能回读 | 文件可写且末尾包含唯一消息 |
| 第 1～3 次 Kafka 消费 | 任意一次输出包含唯一消息 | 最多三轮、每轮 10 秒内至少匹配一次 |
| `GetOffsetShell` | 各分区显示当前 offset | 仅在失败诊断时记录，不单独决定通过 |

## 失败路径示例

- **文件回读失败**：重点检查宿主机卷挂载、文件路径和写权限。
- **文件有消息、Topic offset 不增长**：重点检查 Flume Source、Channel 和 Sink 日志。
- **offset 增长但匹配不到消息**：检查 Consumer 参数、Topic 名称和消息序列化内容。

本脚本验证功能正确性和最终可达性，不测吞吐量、端到端延迟上限、全局顺序或 Exactly Once。

## 日志与失败定位

日志保存到 `test/test-log/test-flume-kafka-时间戳.log`。三次未匹配会返回非零状态，并输出 Agent 进程、Topic/ISR、最新偏移量、消费者输出和 Flume 最近日志。
