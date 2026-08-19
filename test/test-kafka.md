# Kafka 三节点集群测试说明

## 脚本与依赖

- 脚本：`test/test-kafka.sh`
- Kafka：`kafka1/2/3`
- ZooKeeper：`zoo1/2/3`

```bash
bash test/test-kafka.sh
```

## 测试范围

从 ZooKeeper 依赖、Broker 就绪、Topic 元数据到消息收发，逐层验证三节点 Kafka 集群。

## 详细测试流程

### 1. 检查依赖容器

依次检查 `zoo1/2/3` 和 `kafka1/2/3` 的 Docker 运行状态。缺少任一节点都会停止测试，避免把降级集群误判为完整三节点集群。

### 2. 等待 Broker API

以两秒间隔执行最多 30 次 `kafka-topics.sh --list --bootstrap-server kafka1:9092`。成功后记录现有 Topic；60 秒仍不可用则判定 Broker 启动失败。

### 3. 创建唯一 Topic

Topic 名称包含时间戳和进程号，脚本执行：

```bash
kafka-topics.sh --create \
  --partitions 3 --replication-factor 3 \
  --bootstrap-server kafka1:9092
```

### 4. 校验分区、副本和 ISR

读取 `--describe` 输出，要求 `PartitionCount=3`、`ReplicationFactor=3`，并逐分区计算 ISR 数量。三个分区都必须拥有三个同步副本。

### 5. 生产和消费

Producer 写入一条本轮唯一消息；Consumer 从该唯一 Topic 读取一条消息。消费结果必须逐行精确匹配，历史消息不能替代本轮消息。

### 6. 清理

提交 Topic 删除请求，并在退出前再次执行兜底删除，减少失败测试留下的资源。

## 结果判定

| 环节 | 通过条件 |
|---|---|
| 依赖 | 三个 ZooKeeper、三个 Broker 均运行 |
| Broker API | 60 秒内能够列出 Topic |
| Topic | 3 分区、3 副本，全部 ISR 完整 |
| 消息 | Producer 成功且 Consumer 精确读到唯一消息 |
| 清理 | Topic 删除请求成功 |

脚本只有在容器、Broker API、Topic 配置、ISR、消息收发和清理全部通过时返回退出码 `0`。只创建出 Topic、但 ISR 不完整或消费不到本轮消息，均判定失败。

## 关键命令、预期结果与通过条件

| 脚本执行的命令 | 预期结果 | 该项通过条件 |
|---|---|---|
| `kafka-topics.sh --list --bootstrap-server kafka1:9092` | 正常返回 Topic 列表 | 60 秒内至少成功执行一次 |
| `kafka-topics.sh --create ... --partitions 3 --replication-factor 3` | `Created topic` 或命令退出码为 0 | 唯一测试 Topic 创建命令成功 |
| `kafka-topics.sh --describe --topic <topic>` | `PartitionCount: 3`、`ReplicationFactor: 3` | 两个字段均精确匹配 3 |
| 同一 `--describe` 输出 | 三个 Partition 的 `Isr` 都包含三个 Broker ID | 三个分区均有 3 个 ISR |
| `kafka-console-producer.sh` | 命令退出码为 0 | 唯一消息生产成功 |
| `kafka-console-consumer.sh --max-messages 1` | 输出与唯一消息完全相同 | 20 秒内消费到且逐行精确匹配本轮消息 |
| `kafka-topics.sh --delete --topic <topic>` | 命令退出码为 0 | Topic 删除请求提交成功 |

## 日志与失败定位

日志保存到 `test/test-log/test-kafka-时间戳.log`。失败时会记录 Topic 创建/描述、Producer、Consumer、最新偏移量等原始输出，并追加三个 Broker 的最近日志。脚本不再把“Topic 可能已存在”或空消费结果当作通过。

常见问题包括 Broker Cluster ID 与 ZooKeeper 不一致、可用 Broker 少于三个、分区 Leader 缺失、ISR 未同步以及 Topic 删除功能被禁用。
