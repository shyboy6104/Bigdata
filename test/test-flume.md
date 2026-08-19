# Flume 组件测试说明

## 脚本与依赖

- 脚本：`test/test-flume.sh`
- 容器：`flume-kafka`、`kafka1/2/3`
- Agent：`agent1`
- Topic：`flume-logs`

```bash
bash test/test-flume.sh
```

## 测试范围

逐层验证 Flume Agent 的进程、配置和实际数据传输，能够把失败定位到 Source、Channel、Sink 或 Kafka。

## 详细测试流程

### 1. 检查容器

检查 `flume-kafka` 和 `kafka1/2/3`。日志保存每个容器的状态、运行标志和退出码。

### 2. 检查 Agent 进程

在 Flume 容器中搜索 `org.apache.flume.node.Application`，输出完整 Java 命令，并要求启动参数包含 `--name agent1`。

### 3. 检查配置链路

从 `/opt/flume/conf/flume-kafka.conf` 验证：

- `agent1.sources = log-source`；
- `agent1.channels = memory-channel`；
- `agent1.sinks = kafka-sink`；
- Source 和 Sink 都绑定到同一个 Channel；
- Kafka Sink 指向 `kafka1/2/3:9092`。

### 4. 准备 Kafka Topic

先列出 Topic；若 `flume-logs` 不存在则创建 3 分区、3 副本 Topic。随后执行 `--describe`，把 Leader、Replicas、ISR 写入日志。

### 5. 写入 Source 文件

生成 `flume-component-<时间戳-进程号>` 唯一消息，追加到 `/var/log/application/application.log`。等待八秒后从文件末尾回读，先确认数据确实进入了 Source 监控文件。

### 6. 从 Kafka 消费

Consumer 读取 `flume-logs`，必须精确找到本轮唯一消息。若未找到，日志附加 Topic 偏移量和 Flume 最近 100 行日志。

## 结果判定

| 环节 | 通过条件 |
|---|---|
| 容器 | Flume 和三个 Broker 均运行 |
| Agent | Java 进程存在且名称为 agent1 |
| 配置 | Source、Channel、Sink 和绑定完整 |
| Topic | Topic 可用，详情可读取 |
| Source | 唯一消息可从监控文件回读 |
| Kafka | 精确消费到本轮唯一消息 |

脚本对每个检查项累计通过数和失败数。最终 `失败` 数为 `0` 时返回退出码 `0`；任何容器、Agent、配置、Topic、文件写入/回读或 Kafka 消费项失败，均返回退出码 `1`。

## 关键命令、预期结果与通过条件

| 脚本执行的命令或检查 | 预期结果 | 该项通过条件 |
|---|---|---|
| `docker inspect` 检查四个容器 | 每个结果包含 `运行中=true` | `flume-kafka`、`kafka1/2/3` 全部运行 |
| `ps ... org.apache.flume.node.Application` | 找到 Java 进程，命令行包含 `--name agent1` | 进程存在且 Agent 名称正确 |
| `grep` 检查 `flume-kafka.conf` | Source、Channel、Sink、两条绑定和三 Broker 地址均匹配 | 所有指定配置字段完整 |
| `kafka-topics.sh --list/--describe` | `flume-logs` 存在且详情命令成功 | Topic 已存在或创建成功，并能读取详情 |
| 追加 `<唯一消息>` 到 `application.log` | 写入命令退出码为 0 | Source 文件可写 |
| `tail -n 5 application.log` | 包含本轮唯一消息 | 写入数据可以从监控文件回读 |
| `kafka-console-consumer.sh` | 输出包含本轮唯一消息 | 15 秒消费窗口内精确匹配消息 |

## 日志与失败定位

日志保存到 `test/test-log/test-flume-时间戳.log`。失败信息会明确指出容器、Agent、配置、Topic、Source 文件或 Kafka 消费环节，并按需附加偏移量及 Flume 最近日志。无消息不再作为警告通过。
