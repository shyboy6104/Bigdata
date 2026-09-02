# 五节点全栈综合测试说明

## 脚本与架构

- 脚本：`test/cluster-test.sh`
- 节点：`master`、`worker-1/2/3`、`infra`

```bash
bash test/cluster-test.sh
```

## 测试范围

按照五节点服务依赖顺序进行综合验收，既检查服务是否存活，也执行真实读写、SQL、消息和计算作业。

## 详细测试流程

### 1. 节点与 Supervisor

检查 `master`、三个 Worker、`infra` 容器，随后输出 Master、worker-1、infra 的全部 Supervisor 进程状态。

### 2. JVM 与内存

输出 Master 和 worker-1 的实际 Java 命令行，检查 NameNode、DataNode、HBase、ZooKeeper、Kafka、Spark、Flink 的关键内存参数是否与 Compose 预算一致。

### 3. 存储与资源调度

依次验证 HDFS 安全模式、三个 DataNode、文件写入读取、三个 NodeManager、ResourceManager Web UI，并提交 MapReduce WordCount。

### 4. 协调、数据库和数据仓库

- ZooKeeper：三个端口、`ruok`、znode 创建读取删除。
- HBase：Master/RegionServer、集群状态、建表、put、scan、get、删表。
- Hive：Metastore/HiveServer2、建库建表、插入、查询、聚合和清理。

### 5. 消息与采集链路

验证三个 Kafka Broker，创建 Topic、生产、消费、删除；随后分别运行 Flume → Kafka 和完整数据管道测试，使用唯一消息确认本轮数据到达。

### 6. 计算引擎

- Spark：Master、三个Worker、Python/PySpark运行时、Scala SparkPi以及PySpark RDD/DataFrame作业；Scala与PySpark都分别验证Standalone和YARN模式。
- Flink：JobManager、TaskManager 注册和 WordCount 作业。

### 7. 基础数据库

在 `infra` 中验证 MySQL 端口、连接、`hive_metastore`、测试表 CRUD 和清理。

### 8. 汇总

输出总数、通过、失败、跳过和成功率。任何失败项都会让脚本最终返回退出码 1。

## 结果判定

| 层次 | 通过条件 |
|---|---|
| 容器/进程 | 五个容器和必要 Supervisor 服务运行 |
| 存储/协调 | HDFS、ZooKeeper、HBase 读写成功 |
| SQL/消息 | Hive、MySQL、Kafka、Flume 链路成功 |
| 计算 | MapReduce、Scala Spark、PySpark和Flink作业成功 |
| 汇总 | 失败数为 0 |

`run_test` 会为每个测试项记录名称、实际命令、命令输出和退出码：命令退出码为 `0` 时该项通过，否则该项失败。全部测试结束后，只有 `FAILED_TESTS=0` 时脚本返回退出码 `0`；即使成功率超过 80%，只要存在一个失败项，整体仍返回退出码 `1`。

## 分层命令、预期结果与通过条件

| 测试方面 | 脚本执行的代表命令或操作 | 预期结果与通过条件 |
|---|---|---|
| 五个容器 | `docker ps --format '{{.Names}}'` | `master`、`worker-1/2/3`、`infra` 均能精确匹配 |
| Supervisor/Java | `supervisorctl status`、`ps -ef` | 服务状态和 Java 参数能够读取；各内存 grep 断言成功 |
| HDFS | `dfsadmin -safemode get`、`dfsadmin -report`、HDFS mkdir/put/cat/rm | 安全模式 OFF、Live DataNode 至少 3、写入内容可读回、清理成功 |
| YARN/MapReduce | `yarn node -list`、ResourceManager Web 请求、WordCount | RUNNING NodeManager 至少 3、Web 可访问、作业成功 |
| ZooKeeper | 三节点端口、`ruok`、zkCli create/get/delete | 三个端口可达、返回 `imok`、znode CRUD 全部成功 |
| HBase | Master/RegionServer 端口、Shell `status/create/put/scan/get/drop` | 至少 3 个 RegionServer，表和数据操作逐项成功 |
| Hive | Metastore/HS2 端口、Beeline 建库建表/插入/查询/聚合/清理 | 端口可达，SQL 命令退出码为 0 且脚本中的 grep 结果匹配 |
| Kafka | 三 Broker 端口、Topic create/describe、Producer/Consumer/delete | 三端口可达，Topic 操作成功，消费输出匹配生产消息 |
| Flume | Agent 进程/配置检查、临时 Agent、唯一消息消费 | Agent 与配置存在，Flume 发送的唯一消息能从 Kafka 找到 |
| 完整数据管道 | 创建 Topic、启动管道 Agent、写入唯一数据、Kafka 消费 | 端到端消息匹配且 Topic 可访问 |
| Spark运行时 | Master与三个Worker执行`python3 --version`，Master执行`import pyspark` | 四个节点均有Python 3，PySpark版本与Spark版本一致 |
| Scala Spark | Standalone/YARN SparkPi | 至少3个Worker，两种模式均输出`Pi is roughly` |
| PySpark | Standalone/YARN提交`pyspark-smoke.py` | 两种模式均输出`PYSPARK_SMOKE_OK square_sum=55 adult_count=2` |
| Flink | JobManager 端口/Dashboard、TaskManager 数量、WordCount | 至少 1 个 TaskManager，作业命令成功 |
| MySQL | 端口、连接、`hive_metastore`、测试表 CRUD | 数据库存在，插入值可查询，测试表清理成功 |

## 失败定位顺序

1. 先看容器是否运行。
2. 再看 Supervisor/Java 进程是否存在。
3. 再看进程是否完成集群注册，例如 DataNode、NodeManager、TaskManager。
4. 再执行最小业务操作，例如 HDFS 写一行、Kafka 发一条、Hive 查一行。
5. 最后才运行跨组件链路，避免在底层未就绪时分析上层复杂错误。

## 日志与失败定位

日志保存到 `test/test-log/cluster-test-时间戳.log`。每项测试记录名称和通过/失败状态；失败时额外记录：

- 实际退出码；
- 执行命令；
- 命令输出末尾；
- 对应组件的 Supervisor、Java 进程或容器日志摘要。

脚本最终输出总数、通过、失败、跳过和成功率。存在失败时退出码为 1，便于 CLI 或 CI 判断结果。
