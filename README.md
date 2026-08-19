# 大数据分布式服务实验平台

本项目面向大数据相关课程和实验教学，在 Windows 10/11 + WSL2 环境中，使用 Docker 与 Docker Compose 搭建可重复部署的大数据分布式实验平台。

平台覆盖镜像构建、集群编排、配置管理、服务初始化、健康监控和功能测试，支持“先学习单个组件，再进行全栈综合实训”的教学路径。

## 项目状态

- 已实现 9 类大数据/基础组件，以及 Hadoop HA 部署变体。
- 已实现 Hadoop 标准模式和 Hadoop HA 模式。
- 已实现 5 节点全栈集群及 Supervisor 多进程管理。
- 已提供统一 CLI、组件测试脚本和 PyQt5 配置可视化工具。
- 仓库历史记录显示完整集群曾通过 73 项测试；当前代码变更后仍应重新执行测试确认。
- 项目定位为教学与实验环境，不建议未经安全加固直接用于生产。

## 组件与版本

版本的主要维护入口是 `config/environment.conf`。

| 组件 | 版本 | 教学用途 |
|---|---:|---|
| Hadoop | 3.1.3 | HDFS、YARN、MapReduce |
| ZooKeeper | 3.6.3 | 分布式协调与选主 |
| HBase | 2.2.3 | HDFS 上的分布式列式数据库 |
| Hive | 3.1.2 | 数据仓库与 SQL 查询 |
| MySQL | 5.7 | Hive Metastore 元数据存储 |
| Kafka | 2.4.1 | 分布式消息队列 |
| Flume | 1.9.0 | 日志采集与 Kafka 联动 |
| Spark | 3.1.1 | Standalone 与 YARN 批处理 |
| Flink | 1.14.0 | 流批处理与作业提交 |

`module/` 中还保存了 Kylin、ClickHouse、Hudi、Redis、Sqoop 等安装包，但当前没有对应的 Dockerfile、Compose、启动脚本和测试，因此不属于已交付组件。

## 两种部署架构

### 1. 独立组件架构

每个组件使用单独的 Dockerfile、Compose 文件和启动脚本，所有服务通过外部网络 `bigdata-net` 互联。

| 组件 | 实际服务/容器 | 说明 |
|---|---|---|
| Hadoop | `namenode`、`datanode1`、`datanode2` | NameNode 同时运行 ResourceManager 和 JobHistoryServer；DataNode 同时运行 NodeManager |
| Hadoop HA | `namenode1/2`、`journalnode1/2/3`、`datanode1/2` | 依赖外部 ZooKeeper，使用 QJM、ZKFC 和双 ResourceManager |
| ZooKeeper | `zoo1/2/3` | 3 节点仲裁集群 |
| HBase | `hbase-master`、`hbase-regionserver1/2` | 依赖 HDFS 和 ZooKeeper |
| Hive | `hive-metastore`、`hive-server2`、`hive-cli` | 依赖 HDFS 和 MySQL |
| Kafka | `kafka1/2/3` | ZooKeeper 模式的 3 Broker 集群 |
| Spark | `spark-master`、`spark-worker1/2` | 支持 Standalone 和 YARN |
| Flink | `flink-jobmanager`、`flink-taskmanager1/2` | Standalone 集群 |
| Flume | `flume-kafka` | 默认演示日志与 Kafka 数据链路 |
| MySQL | `mysql` | 保存 Hive 元数据 |

适合课程中的单组件原理、配置观察、命令操作和故障实验。

### 2. 五节点全栈架构

`docker-compose.5-node-cluster.yml` 使用同一个 `bigdata-all-in-one:latest` 镜像，根据容器主机名分配角色。

| 节点 | 运行服务 | 计划内存 |
|---|---|---:|
| `master` | NameNode、ResourceManager、HMaster、Hive Metastore、HiveServer2、Spark Master、Flink JobManager | 4.0 GB |
| `worker-1` | DataNode、NodeManager、ZooKeeper、Kafka、RegionServer、Spark Worker、Flink TaskManager | 3.5 GB |
| `worker-2` | 同 `worker-1` | 3.5 GB |
| `worker-3` | 同 `worker-1` | 3.5 GB |
| `infra` | MySQL、Flume | 1.0 GB |

计划 JVM/服务内存合计约 15.5 GB。Docker Desktop/WSL2 建议至少分配 16 GB；如果物理内存不足，应按教学场景分批启动组件。

五节点模式是标准单 NameNode 架构，不提供 Hadoop HA。它主要用于组件联动、资源规划和综合实训。

## 环境要求

- Windows 10/11，WSL2 Ubuntu 20.04 或更新版本
- Docker 20.10+
- Docker Compose 2.x，并保留 `docker-compose` 兼容命令供现有 CLI 使用
- Bash、curl、常用 GNU 工具
- 建议内存 16 GB 以上，可用磁盘空间 50 GB 以上

Windows 环境安装说明见 [安装docker desktop.md](安装docker%20desktop.md)。在 WSL 中建议显式使用 `bash` 执行 `.sh` 文件：

```bash
bash bigdata-cli.sh --help
bash scripts/network.sh
bash test/test-hadoop.sh
```

## 快速开始

### 1. 创建公共网络

除五节点 Compose 自带网络外，独立组件 Compose 使用预先创建的外部网络：

```bash
bash scripts/network.sh
```

### 2. 构建基础镜像

所有 Apache 组件镜像都依赖 `bigdata-base:latest`：

```bash
docker build -f dockerfile.base -t bigdata-base:latest .
```

如需手工构建全部独立组件镜像，可按依赖顺序执行：

```bash
docker build -f dockerfile.hadoop -t bigdata-hadoop:latest .
docker build -f dockerfile.zookeeper -t bigdata-zookeeper:latest .
docker build -f dockerfile.mysql -t bigdata-mysql:latest .
docker build -f dockerfile.hbase -t bigdata-hbase:latest .
docker build -f dockerfile.hive -t bigdata-hive:latest .
docker build -f dockerfile.kafka -t bigdata-kafka:latest .
docker build -f dockerfile.spark -t bigdata-spark:latest .
docker build -f dockerfile.flink -t bigdata-flink:latest .
docker build -f dockerfile.flume -t bigdata-flume:latest .
```

`scripts/update-dockerfile-versions.sh` 用于读取 `config/environment.conf`、检查安装包并同步 Dockerfile 版本。该脚本可能访问网络和修改 Dockerfile，运行前建议先提交或暂存本地改动：

```bash
bash scripts/update-dockerfile-versions.sh
git diff -- dockerfile.*
```

### 3. 启动独立组件

CLI 支持交互菜单和命令模式，但不会自动构建基础镜像，也不会自动启动上游依赖。

```bash
# 查看组件
bash bigdata-cli.sh list

# 构建并启动 ZooKeeper
bash bigdata-cli.sh build zookeeper
bash bigdata-cli.sh start zookeeper

# 构建并启动 Hadoop 标准集群
bash bigdata-cli.sh build hadoop
bash bigdata-cli.sh start hadoop

# 查看状态并运行测试
bash bigdata-cli.sh status hadoop
bash bigdata-cli.sh test hadoop
```

推荐依赖顺序：

```text
ZooKeeper → Hadoop 或 Hadoop HA → MySQL
           ├→ HBase
           ├→ Hive
           ├→ Spark
           └→ Flink
ZooKeeper → Kafka → Flume
```

HBase、Hive 基于 `bigdata-hadoop:latest` 构建，构建它们之前需先构建 Hadoop 镜像。Spark 默认挂载 Hadoop HA 配置；若使用标准 Hadoop，请设置相应的 `HADOOP_ENVIRONMENT` 并核对 `docker-compose.spark.yml`。

CLI 完整用法见 [CLI_USAGE.md](CLI_USAGE.md)。也可以直接使用 Compose：

```bash
docker-compose -f docker-compose.zookeeper.yml up -d
docker-compose -f docker-compose.hadoop.yml up -d
docker-compose -f docker-compose.mysql.yml up -d
```

### 4. 启动五节点全栈集群

```bash
docker build -f dockerfile.all-in-one -t bigdata-all-in-one:latest .
docker-compose -f docker-compose.5-node-cluster.yml up -d
```

也可以使用 CLI：

```bash
bash bigdata-cli.sh --architecture multi build all
bash bigdata-cli.sh --architecture multi start all
bash bigdata-cli.sh --architecture multi status all
bash bigdata-cli.sh --architecture multi test all
```

五节点启动脚本会完成以下工作：

1. 按主机名选择 master、worker 或 infra 配置。
2. 初始化 HDFS、MySQL 和 Hive Metastore Schema。
3. 检查 DataNode Cluster ID、Kafka Cluster ID 和 HBase 残留状态。
4. 使用 Supervisor 按依赖顺序启动服务。
5. 启动健康监控，异常时有限次数重启对应服务。

## 服务端口

### 独立组件架构

| 服务 | 主机访问地址/端口 |
|---|---|
| Hadoop NameNode | http://localhost:19870 |
| Hadoop YARN | http://localhost:18088 |
| Hadoop JobHistory | http://localhost:19888 |
| Hadoop HA NameNode 1/2 | http://localhost:19870 / http://localhost:29870 |
| Hadoop HA YARN 1/2 | http://localhost:18088 / http://localhost:28088 |
| ZooKeeper 1/2/3 | `localhost:2181/2182/2183` |
| HBase Master | http://localhost:16210 |
| HBase RegionServer 1/2 | http://localhost:16030 / http://localhost:16031 |
| HBase REST / Thrift | `localhost:18280` / `localhost:19090` |
| Hive Metastore | `localhost:19083` |
| HiveServer2 JDBC / Web UI | `localhost:11000` / http://localhost:11002 |
| Kafka 1/2/3 | `localhost:19092/19093/19094` |
| Spark Master / History | http://localhost:8080 / http://localhost:18080 |
| Spark Worker 1/2 | http://localhost:8081 / http://localhost:8082 |
| Flink Dashboard | http://localhost:18081 |
| MySQL | `localhost:3307` |

### 五节点架构

| 服务 | 主机访问地址/端口 |
|---|---|
| HDFS NameNode | http://localhost:29870 |
| YARN ResourceManager | http://localhost:28088 |
| YARN JobHistory | http://localhost:29888 |
| HBase Master | http://localhost:26010 |
| HiveServer2 JDBC / Web UI | `localhost:21001` / http://localhost:21002 |
| Spark Master / RPC | http://localhost:28080 / `localhost:27077` |
| Flink Dashboard | http://localhost:28081 |
| MySQL | `localhost:3307` |

容器内部应优先通过服务名和容器端口通信，不应使用上述主机映射端口。

## 教学实验操作手册

下面恢复并修正各组件的常用操作示例。独立组件示例使用当前 Compose 中的实际容器名；五节点示例使用 `master`、`worker-1` 和 `infra`。

### 独立组件服务管理

```bash
# 查看所有容器
docker ps

# 查看某个组件状态和日志
docker-compose -f docker-compose.hadoop.yml ps
docker-compose -f docker-compose.hadoop.yml logs -f

# 停止、重启或移除组件容器
docker-compose -f docker-compose.hadoop.yml stop
docker-compose -f docker-compose.hadoop.yml restart
docker-compose -f docker-compose.hadoop.yml down

# 同时删除数据卷会丢失持久化数据
docker-compose -f docker-compose.hadoop.yml down -v
```

### Hadoop：HDFS、YARN 与 MapReduce

```bash
# 进入标准 Hadoop NameNode 容器
docker exec -it namenode bash

# HDFS 文件操作
hdfs dfs -ls /
hdfs dfs -mkdir -p /user/test/input
echo "hello hadoop" > /tmp/input.txt
hdfs dfs -put -f /tmp/input.txt /user/test/input/
hdfs dfs -cat /user/test/input/input.txt
hdfs dfs -du -h /user/test
hdfs dfs -cp /user/test/input/input.txt /user/test/input/input-copy.txt
hdfs dfs -chmod 755 /user/test

# HDFS 管理
hdfs dfsadmin -report
hdfs dfsadmin -safemode get

# YARN 管理
yarn node -list
yarn application -list
yarn application -kill <application_id>

# YARN Pi 示例
yarn jar /opt/hadoop/share/hadoop/mapreduce/hadoop-mapreduce-examples-3.1.3.jar pi 10 100

# MapReduce WordCount
hadoop jar /opt/hadoop/share/hadoop/mapreduce/hadoop-mapreduce-examples-3.1.3.jar \
  wordcount /user/test/input /user/test/wordcount-output
hdfs dfs -cat /user/test/wordcount-output/part-r-00000

# 清理实验数据
hdfs dfs -rm -r -f /user/test
```

Hadoop HA 模式使用逻辑地址 `hdfs://mycluster`。可以在任意 NameNode 查询主备状态：

```bash
docker exec namenode1 hdfs haadmin -getAllServiceState
docker exec namenode1 hdfs haadmin -getServiceState nn1
docker exec namenode2 hdfs haadmin -getServiceState nn2
```

教学环境可使用以下命令演示手动切换，切换前应确认两个 NameNode 和三个 JournalNode 均正常：

```bash
docker exec namenode1 hdfs haadmin -failover nn1 nn2
```

### HBase：表与数据操作

```bash
docker exec -it hbase-master hbase shell

# 在 HBase Shell 中执行
status
version
create 'test_table', 'cf1', 'cf2'
list
describe 'test_table'

put 'test_table', 'row1', 'cf1:name', 'Alice'
put 'test_table', 'row1', 'cf2:age', '25'
put 'test_table', 'row2', 'cf1:name', 'Bob'
get 'test_table', 'row1'
scan 'test_table'
count 'test_table'

delete 'test_table', 'row1', 'cf2:age'
disable 'test_table'
drop 'test_table'
```

HBase 依赖 HDFS 和 ZooKeeper。排障时应同时检查三层状态，而不能只观察 HMaster 进程。

### Hive：数据库、分区表与外部表

```bash
# 从 Hive CLI 容器连接 HiveServer2
docker exec -it hive-cli beeline -u jdbc:hive2://hive-server2:10000
```

进入 Beeline 后可以执行：

```sql
CREATE DATABASE IF NOT EXISTS test_db;
SHOW DATABASES;
USE test_db;

CREATE TABLE test_table (
  id INT,
  name STRING,
  age INT
)
PARTITIONED BY (dt STRING);

INSERT INTO test_table PARTITION (dt='2026-08-19')
VALUES (1, 'Alice', 25), (2, 'Bob', 30);

SELECT * FROM test_table;
SELECT name, age FROM test_table WHERE age > 25;
SHOW PARTITIONS test_table;

ALTER TABLE test_table ADD IF NOT EXISTS PARTITION (dt='2026-08-20');

CREATE EXTERNAL TABLE external_table (
  id INT,
  name STRING
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
LOCATION '/user/hive/external_table';

CREATE VIEW test_view AS
SELECT name, age FROM test_table WHERE age > 25;

DROP VIEW test_view;
DROP TABLE external_table;
DROP TABLE test_table;
DROP DATABASE test_db;
```

### ZooKeeper：节点与集群状态

```bash
docker exec -it zoo1 /opt/zookeeper/bin/zkCli.sh -server localhost:2181

# 在 ZooKeeper CLI 中执行
ls /
create /test-node "test-data"
get /test-node
set /test-node "updated-data"
stat /test-node
delete /test-node
quit
```

在宿主机检查三个节点的角色和四字命令响应：

```bash
echo ruok | nc localhost 2181
echo stat | nc localhost 2181
echo stat | nc localhost 2182
echo stat | nc localhost 2183
```

### Kafka：Topic、生产者和消费者

```bash
docker exec -it kafka1 bash

# 创建并查看 Topic
kafka-topics.sh --create \
  --topic test-topic \
  --partitions 3 \
  --replication-factor 3 \
  --bootstrap-server kafka1:9092
kafka-topics.sh --list --bootstrap-server kafka1:9092
kafka-topics.sh --describe --topic test-topic --bootstrap-server kafka1:9092

# 生产消息；输入完成后按 Ctrl+D
kafka-console-producer.sh \
  --topic test-topic \
  --bootstrap-server kafka1:9092

# 从头消费消息
kafka-console-consumer.sh \
  --topic test-topic \
  --from-beginning \
  --bootstrap-server kafka1:9092

# 使用消费者组
kafka-console-consumer.sh \
  --topic test-topic \
  --group test-group \
  --bootstrap-server kafka1:9092
kafka-consumer-groups.sh --list --bootstrap-server kafka1:9092
kafka-consumer-groups.sh --describe --group test-group --bootstrap-server kafka1:9092

# 清理 Topic
kafka-topics.sh --delete --topic test-topic --bootstrap-server kafka1:9092
```

### Spark：Standalone、YARN 与 Spark SQL

```bash
docker exec -it spark-master bash

# 交互式 Shell
spark-shell --master spark://spark-master:7077

# 自动定位示例 JAR
SPARK_EXAMPLE_JAR=$(ls /opt/spark/examples/jars/spark-examples_*.jar | head -1)

# Standalone 模式
spark-submit \
  --class org.apache.spark.examples.SparkPi \
  --master spark://spark-master:7077 \
  "$SPARK_EXAMPLE_JAR" 100

# YARN 模式
spark-submit \
  --class org.apache.spark.examples.SparkPi \
  --master yarn \
  --deploy-mode client \
  "$SPARK_EXAMPLE_JAR" 100
```

Spark 默认读取 Hadoop HA 配置。如果课程使用标准 Hadoop，应将 Spark Compose 中的 `HADOOP_ENVIRONMENT` 设置为 `standard` 后重新启动。

Spark SQL 可以在 `spark-shell` 中演示：

```scala
val data = Seq((1, "Alice", 25), (2, "Bob", 30)).toDF("id", "name", "age")
data.createOrReplaceTempView("people")
spark.sql("SELECT name, age FROM people WHERE age >= 30").show()
```

### Flink：作业提交与管理

```bash
docker exec -it flink-jobmanager bash

# 提交内置 WordCount 示例
flink run /opt/flink/examples/streaming/WordCount.jar

# 查看、取消作业
flink list
flink cancel <job_id>

# 需要访问 HDFS 时，标准 Hadoop 使用 hdfs://namenode:8020
export HADOOP_CONF_DIR=/opt/flink/conf
```

Flink 1.14 的示例 JAR 名称和参数可能因发行包不同而变化，应先执行 `ls /opt/flink/examples/streaming/` 确认。

### Flume：日志采集到 Kafka

独立模式的 `config/flume/flume-kafka.conf` 使用 `agent2`，监控 `/var/log/application/application.log` 并写入 Kafka 的 `flume-logs` Topic。当前 `flume-entrypoint.sh` 却以 `agent1` 启动，二者需要按 Todo 的 P0 任务统一。在修复前，完整链路实验可在容器中手工启动 `agent2`：

```bash
# 先确认 Kafka Topic
docker exec kafka1 kafka-topics.sh \
  --create --if-not-exists \
  --topic flume-logs \
  --partitions 3 \
  --replication-factor 3 \
  --bootstrap-server kafka1:9092

# 按配置文件中的真实 Agent 名称启动采集链路
docker exec -d flume-kafka /opt/flume/bin/flume-ng agent \
  --conf /opt/flume/conf \
  --conf-file /opt/flume/conf/flume-kafka.conf \
  --name agent2 \
  -Dflume.root.logger=INFO,console

# 追加测试日志
docker exec flume-kafka bash -c \
  'echo "flume teaching message" >> /var/log/application/application.log'

# 从 Kafka 消费验证
docker exec kafka1 kafka-console-consumer.sh \
  --topic flume-logs \
  --from-beginning \
  --max-messages 1 \
  --bootstrap-server kafka1:9092
```

### 五节点全栈启动顺序

五节点 entrypoint 不依赖 Compose 的简单启动次序，而是在各节点内按服务依赖逐项启动。

**Master 节点：**

1. NameNode
2. ResourceManager
3. 等待 DataNode 注册并退出安全模式
4. 等待 infra MySQL
5. 初始化 Hive Metastore Schema
6. Hive Metastore、HiveServer2
7. 等待 worker ZooKeeper 集群
8. HBase Master
9. Spark Master
10. Flink JobManager
11. 健康监控

**Worker 节点：**

1. ZooKeeper
2. 等待 NameNode
3. 检查 DataNode Cluster ID
4. DataNode、NodeManager
5. Kafka Broker
6. HBase RegionServer
7. Spark Worker
8. Flink TaskManager
9. 健康监控

**Infra 节点：** MySQL → Flume → 健康监控。

### 五节点综合操作

```bash
# 进入 Master
docker exec -it master bash

# HDFS
hdfs dfs -mkdir -p /user/test
hdfs dfs -put -f /opt/hadoop/LICENSE.txt /user/test/
hdfs dfs -ls /user/test

# HBase
echo "status" | hbase shell -n

# Hive
beeline -u jdbc:hive2://localhost:10000

# Spark Standalone
SPARK_EXAMPLE_JAR=$(ls /opt/spark/examples/jars/spark-examples_*.jar | head -1)
spark-submit --class org.apache.spark.examples.SparkPi \
  --master spark://master:7077 "$SPARK_EXAMPLE_JAR" 100

# Spark on YARN
spark-submit --class org.apache.spark.examples.SparkPi \
  --master yarn --deploy-mode client "$SPARK_EXAMPLE_JAR" 100

# Flink
flink list
```

```bash
# 在 Worker 上管理 Kafka
docker exec -it worker-1 bash
kafka-topics.sh --list --bootstrap-server worker-1:9092
```

## 配置结构与生效路径

```text
config/
├── environment.conf              # 独立组件版本与环境选择
├── hadoop/                       # Hadoop 标准模式
├── hadoop-ha/                    # Hadoop HA 模式
├── hbase/ hive/ kafka/ ...       # 独立组件配置
├── supervisor/supervisord.conf   # 五节点 Supervisor 主配置
└── all-in-one/
    ├── hadoop-master/            # 五节点 master Hadoop 配置
    ├── hadoop-worker/            # 五节点 worker Hadoop 配置
    ├── hbase-master/worker/      # 五节点 HBase 角色配置
    ├── spark-master/worker/      # 五节点 Spark 角色配置
    ├── flink-master/worker/      # 五节点 Flink 角色配置
    ├── hive/ kafka/ zookeeper/   # 五节点共享组件配置
    ├── mysql/ flume/
    └── supervisor/               # 各角色 Supervisor program 配置
```

独立组件由各自 entrypoint 将 `config/<component>/` 复制或挂载到组件目录。五节点模式由 `scripts/all-in-one-entrypoint.sh` 根据角色从 `config/all-in-one/` 复制配置。

### 配置简化审计

当前配置可以继续简化，但建议分阶段完成并在每一步后运行组件测试。

| 级别 | 发现 | 建议 |
|---|---|---|
| 可直接整理 | `config/all-in-one/hadoop/` 的两个文件与 `hadoop-master/` 完全相同，且启动脚本不引用该目录 | 验证无外部使用者后删除重复目录 |
| 可直接整理 | `config/supervisor/conf.d/` 是旧版角色配置；实际运行使用 `config/all-in-one/supervisor/` | 保留 `supervisord.conf`，删除或归档旧 `conf.d` |
| 可直接整理 | `memory-optimization.conf` 当前未被脚本加载 | 删除它，或明确改为唯一内存配置入口，不能继续作为无效副本保留 |
| 可直接整理 | 启动脚本尝试读取不存在的 `/config/all-in-one/environment.conf` | 删除无效分支，或增加真实配置并明确挂载 |
| 需测试后合并 | Hadoop master/worker 的公共连接参数重复，部分 YARN 地址同时出现在 `core-site.xml` 和 `yarn-site.xml` | 收敛为一套公共配置加少量角色差异 |
| 需测试后合并 | HBase master/worker 的 `rootdir`、ZooKeeper 和端口配置重复 | 尝试共用一份 `hbase-site.xml` |
| 需测试后修正 | 五节点 Hadoop 配置仍显式使用 `50010/50075` 等 Hadoop 2.x 端口，并存在 `hadoop.heap.size`、`dfs.permissions` 等疑似失效项 | 删除旧端口覆盖，改用 Hadoop 3.x 默认端口及正式属性名 |
| 需统一来源 | Flink 内存同时在 Compose、entrypoint、YAML 中配置，且存在 512 MB 与 1024 MB 冲突 | 选择一个权威入口，其余仅使用环境变量替换 |
| 需统一来源 | Spark、Hadoop、HBase、Kafka 内存也分散在多处 | Compose 负责节点预算，entrypoint 只提供默认值，组件配置不再重复写死 |
| 建议保留 | Hadoop HA 的 QJM/ZKFC、Kafka Broker ID、Flume Source-Channel-Sink 配置 | 这些内容体现核心教学概念，不宜为了减少行数而隐藏 |

详细任务和验收标准见 [Todo.md](Todo.md)。

## 配置可视化工具

`config-visualizer/` 提供 PyQt5 图形化编辑器，支持 XML、Properties、Shell、INI、YAML、Spark Conf、列表文件和纯文本。

```bash
cd config-visualizer
python main.py
```

主要流程：

1. 从 `config/` 读取组件配置。
2. 在表格或纯文本模式编辑。
3. 保存到 `config-visualizer/output/` 工作区。
4. 人工确认后同步回 `config/`。

工具支持配置项说明、预设值、核心项标记以及新增组件和文件。同步操作会修改运行配置，建议同步前查看 Git diff。

### 界面与文件管理

- 左侧组件列表用于切换 Hadoop、HBase、Hive、Kafka、Spark、Flink 等配置集合。
- 文件列表显示当前组件的配置文件，并支持新增、删除文件。
- 右侧表格模式用于结构化编辑键、值和说明。
- 纯文本模式用于列表、自由文本或无法安全结构化的配置。
- `保存` 只写入 `config-visualizer/output/`。
- `同步到 config/` 才会覆盖项目运行配置。

支持的主要文件类型：

| 文件类型 | 典型扩展名/文件 | 适用组件 |
|---|---|---|
| XML | `.xml` | Hadoop、HBase、Hive |
| Properties | `.properties` | Kafka |
| 键值配置 | `.conf`、`.cfg` | Flume |
| Spark Conf | `spark-defaults.conf` | Spark |
| Shell 环境 | `.sh` | Spark、Hadoop 环境变量 |
| INI | `.cnf`、`.ini` | MySQL |
| YAML | `.yaml`、`.yml` | Flink |
| 主机列表 | `workers`、`slaves`、`regionservers` | Hadoop、Spark、HBase |
| 纯文本 | `.txt`、`.md` | 说明或自定义内容 |

新增组件时，工具会在工作区创建组件目录；新增文件时会按类型生成基础模板。配置项说明和核心项标记来自 `config-visualizer/config_data.py`。

## 测试

### 独立组件测试

```bash
bash test/test-hadoop.sh
bash test/test-hadoop-ha.sh
bash test/test-zookeeper.sh
bash test/test-hbase.sh
bash test/test-hive.sh
bash test/test-kafka.sh
bash test/test-spark.sh
bash test/test-flink.sh
bash test/test-flume.sh
bash test/test-flume-kafka.sh
bash test/test-mysql.sh
```

### 五节点综合测试

```bash
bash test/cluster-test.sh
```

综合测试覆盖容器状态、HDFS/YARN/MapReduce、ZooKeeper、HBase、Hive、Kafka、Flume-Kafka、Spark Standalone/YARN、Flink 和 MySQL。测试会创建临时目录、表、Topic 和数据库，脚本结束时会尽量清理。

## 常用管理命令

```bash
# 查看五节点容器
docker-compose -f docker-compose.5-node-cluster.yml ps

# 查看 Supervisor 服务
docker exec master supervisorctl status
docker exec worker-1 supervisorctl status
docker exec infra supervisorctl status

# 查看日志
docker-compose -f docker-compose.5-node-cluster.yml logs -f
docker logs -f master

# 停止但保留数据卷
docker-compose -f docker-compose.5-node-cluster.yml down

# 删除数据卷，数据不可恢复，请谨慎执行
docker-compose -f docker-compose.5-node-cluster.yml down -v
```

## 常见问题

### HDFS 长时间处于安全模式

```bash
docker exec master hdfs dfsadmin -safemode get
docker exec master hdfs dfsadmin -report
docker exec master hdfs dfsadmin -safemode leave
```

先确认 DataNode 已注册，再手动退出安全模式。

### HBase Master 无法完成初始化

检查 HDFS、ZooKeeper、RegionServer 和 Master 日志：

```bash
docker exec master supervisorctl status
docker exec master hdfs dfs -ls /hbase
docker exec worker-1 /opt/zookeeper/bin/zkCli.sh -server localhost:2181
```

五节点 entrypoint 包含残留数据修复逻辑。手工删除 `/hbase` 会丢失数据，不应作为首选操作。

进一步检查：

```bash
# Master 与 RegionServer 进程
docker exec master jps
docker exec worker-1 jps

# HBase 日志
docker exec master tail -n 100 /opt/hbase/logs/hbase-master-error.log
docker exec worker-1 tail -n 100 /opt/hbase/logs/hbase-regionserver-error.log

# ZooKeeper 中的 HBase 节点
docker exec worker-1 bash -c \
  'echo "ls /hbase" | /opt/zookeeper/bin/zkCli.sh -server localhost:2181'
```

只有确认实验数据可以丢弃时，才能清理 ZooKeeper/HDFS 中的 HBase 状态并重新初始化。

### Hive 无法连接 MySQL 或 Metastore

```bash
docker exec infra mysqladmin ping
docker exec infra mysql -uroot -proot -e 'SHOW DATABASES;'
docker exec master bash -c 'echo > /dev/tcp/infra/3306'
docker exec master bash -c 'echo > /dev/tcp/localhost/9083'
docker exec master supervisorctl status hive-metastore hive-server2
```

重点核对 `hive-site.xml` 中的数据库名、用户名、密码、JDBC URL 和 Metastore URI 是否与当前架构一致。独立模式使用 `mysql`、`hive-metastore`，五节点模式使用 `infra`、`master`。

### Kafka Broker 无法启动

```bash
docker exec worker-1 supervisorctl status kafka-broker
docker exec worker-1 tail -n 100 /opt/kafka/logs/kafka-error.log
docker exec worker-1 bash -c 'echo > /dev/tcp/worker-2/2181'
docker exec worker-1 grep -E 'broker.id|advertised.listeners|zookeeper.connect' \
  /opt/kafka/config/server.properties
```

常见原因包括 Broker ID 重复、`advertised.listeners` 使用错误主机名、ZooKeeper 不可达，以及数据卷中的 Cluster ID 与 ZooKeeper 不一致。

### 端口冲突

宿主机端口被占用时，优先只修改 Compose 左侧的主机端口，不要随意修改容器内部服务端口：

```bash
# Windows
netstat -ano | findstr :19870

# WSL/Linux
ss -lntp | grep ':19870'
```

例如 `19870:9870` 中，`19870` 可以改为其他空闲主机端口，而容器内部 `9870` 应与 Hadoop 配置保持一致。

### Windows 脚本换行或路径异常

- 在 WSL 终端中执行命令，路径使用 `/`。
- 推荐 `bash script.sh`，避免 Windows Shell 直接解释 Bash 语法。
- 仓库通过 `.gitattributes` 将 Shell 和配置文件固定为 LF。
- 出现 `bash: $'\r': command not found` 时运行 `dos2unix <script>`。
- 出现 `Permission denied` 时使用 `bash <script>`，或执行 `chmod +x <script>`。
- 从 Windows 路径切换到 WSL 路径时，可使用 `wslpath` 转换。

环境自检：

```bash
wsl --version
docker --version
docker compose version
docker-compose --version
docker info
bash bigdata-cli.sh --help
```

### 内存不足

- 增加 Docker Desktop/WSL2 内存。
- 不要同时启动独立组件架构和五节点架构。
- 按离线数仓、实时链路、Spark/Flink 计算等场景分批启动。
- 修改内存参数后运行对应组件测试。

### 监控与维护

五节点模式可同时从 Supervisor、进程、端口和 Web UI 四个层次观察服务：

```bash
# Supervisor 状态
docker exec master supervisorctl status
docker exec worker-1 supervisorctl status
docker exec infra supervisorctl status

# Java 进程
docker exec master jps
docker exec worker-1 jps

# 健康监控生成的业务日志
docker exec master tail -f /var/log/health-monitor.log

# Supervisor 捕获的健康监控输出
docker exec master tail -f /var/log/health-monitor-stdout.log
```

主要 Web UI：

- HDFS：http://localhost:29870
- YARN：http://localhost:28088
- HBase：http://localhost:26010
- Spark：http://localhost:28080
- Flink：http://localhost:28081

性能观察建议结合 HDFS 副本状态、YARN 容器资源、HBase Region 分布、Kafka Topic 分区、Spark Stage 和 Flink Checkpoint，而不是只观察容器是否运行。

## 项目结构

```text
.
├── config/                       # 独立组件与五节点配置
├── config-visualizer/            # PyQt5 配置编辑器
├── data/                         # 本地日志和运行数据，Git 默认忽略
├── module/                       # 离线安装包，Git 默认忽略
├── scripts/                      # entrypoint、网络和版本脚本
├── test/                         # 组件测试与全栈测试
├── dockerfile.base               # Ubuntu + OpenJDK 8 基础镜像
├── dockerfile.<component>        # 独立组件镜像
├── dockerfile.all-in-one         # 五节点统一镜像
├── docker-compose.<component>.yml
├── docker-compose.5-node-cluster.yml
├── bigdata-cli.sh / .bat         # Linux/WSL 与 Windows 管理入口
├── CLI_USAGE.md
├── Todo.md
└── 安装docker desktop.md
```

各目录职责：

| 目录/文件 | 主要作用 |
|---|---|
| `config/` | 独立组件、HA、五节点角色和 Supervisor 配置 |
| `scripts/` | 容器 entrypoint、初始化、网络与版本同步 |
| `test/` | 独立组件、HA、集成链路和五节点测试 |
| `module/` | 离线安装包与 JDBC/Guava 兼容依赖 |
| `data/` | 本地挂载日志和运行数据，不应提交到 Git |
| `dockerfile.*` | 基础镜像、独立组件镜像和统一全栈镜像 |
| `docker-compose.*.yml` | 服务、网络、端口和数据卷编排 |
| `bigdata-cli.sh` | 镜像、容器、日志、状态和测试的统一入口 |

## 安全与生产边界

当前默认配置使用 root/hive 等教学账号、明文密码、PLAINTEXT Kafka、无 Kerberos、无 TLS，并关闭了部分权限检查。它们降低了实验门槛，但不符合生产安全要求。

如果要扩展到生产模拟，需要至少补充：密钥和密码外置、Kerberos/ACL、TLS、细粒度网络访问、镜像漏洞扫描、指标监控、备份恢复、资源限额以及真实 HA 验证。
