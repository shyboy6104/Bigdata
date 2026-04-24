# 大数据分布式服务实验平台

本项目旨在 Windows WSL (Ubuntu) 环境下，使用 Docker 和 Docker Compose 从零开始构建一个完整的大数据分布式服务实验平台。

## 🎯 项目状态

**✅ 项目已完成并测试通过**

所有组件均已实现并通过功能测试验证，可作为完整的大数据实验平台使用。

## 📋 快速开始

### 环境要求
- **操作系统**: Windows 10/11 with WSL2 (Ubuntu 20.04+)
- **Docker**: 20.10+
- **Docker Compose**: 2.0+
- **内存**: 建议 16GB+ (最低 8GB)
- **存储**: 建议 50GB+ 可用空间

### 架构选择

本项目支持两种部署架构，满足不同使用场景：

#### 架构一：单组件独立集群（推荐学习/开发）
**特点**：每个大数据组件运行在独立的容器集群中，便于单独学习和调试。

| 组件 | 容器数量 | 服务 | 容器主机名 | 说明 |
|------|---------|------|------------|------|
| **Hadoop** | 3个 | NameNode + 2 DataNode + ResourceManager + 2 NodeManager | `hadoop-namenode-1`, `hadoop-datanode-1`, `hadoop-datanode-2` | 标准配置 |
| **Hadoop HA** | 7个 | 2 NameNode + 2 DataNode + 3 JournalNode + ResourceManager + 2 NodeManager | `namenode1`, `namenode2`, `datanode1`, `datanode2`, `journalnode1`, `journalnode2`, `journalnode3` | 高可用配置 |
| **ZooKeeper** | 3个 | 3节点高可用集群 | `zookeeper-1`, `zookeeper-2`, `zookeeper-3` | 协调服务 |
| **HBase** | 3个 | HMaster + 2 RegionServer | `hbase-master-1`, `hbase-regionserver-1`, `hbase-regionserver-2` | NoSQL数据库 |
| **Hive** | 2个 | Metastore + HiveServer2 | `hive-metastore-1`, `hive-server2-1` | 数据仓库 |
| **Kafka** | 3个 | 3 Broker 集群 | `kafka-broker-1`, `kafka-broker-2`, `kafka-broker-3` | 消息队列 |
| **Spark** | 3个 | Master + 2 Worker | `spark-master-1`, `spark-worker-1`, `spark-worker-2` | 计算引擎 |
| **Flink** | 3个 | JobManager + 2 TaskManager | `flink-jobmanager-1`, `flink-taskmanager-1`, `flink-taskmanager-2` | 流处理 |
| **Flume** | 1个 | Agent | `flume-agent-1` | 数据采集 |
| **MySQL** | 1个 | 数据库服务器 | `mysql-server-1` | Hive元数据存储 |

**总容器数**：约 27个容器  
**适用场景**：组件学习、独立调试、开发测试

#### 架构二：5节点全栈集群（推荐生产/集成）
**特点**：采用统一镜像，5个容器承载全部大数据组件，资源利用率高，适合集成测试。

| 节点 | 角色 | 运行服务 | 内存 |
|------|------|---------|------|
| **master** | 管理主节点 | NameNode, ResourceManager, HMaster, Hive Metastore, HiveServer2, Spark Master, Flink JobManager | 4.0 GB |
| **worker-1** | 计算从节点 | DataNode, NodeManager, RegionServer, ZooKeeper, Kafka Broker, Spark Worker, Flink TaskManager | 3.5 GB |
| **worker-2** | 计算从节点 | DataNode, NodeManager, RegionServer, ZooKeeper, Kafka Broker, Spark Worker, Flink TaskManager | 3.5 GB |
| **worker-3** | 计算从节点 | DataNode, NodeManager, RegionServer, ZooKeeper, Kafka Broker, Spark Worker, Flink TaskManager | 3.5 GB |
| **infra** | 基础设施节点 | MySQL, Flume Agent | 1.0 GB |

**总容器数**：5个容器  
**适用场景**：集成测试、生产模拟、性能优化

## 🚀 架构一：单组件独立集群部署

### 使用 CLI 工具管理（推荐）

本项目提供了 `bigdata-cli.sh` 命令行管理工具，支持交互式菜单和命令行两种模式，可一键完成镜像构建、容器部署和功能测试。

```bash
# 交互式菜单模式（推荐新手使用）
./bigdata-cli.sh

# 命令行模式 - 构建镜像
./bigdata-cli.sh build hadoop-ha

# 命令行模式 - 启动容器
./bigdata-cli.sh start hadoop-ha

# 命令行模式 - 测试功能
./bigdata-cli.sh test hadoop-ha

# 按依赖顺序一键部署所有组件
./bigdata-cli.sh build zookeeper && ./bigdata-cli.sh start zookeeper
./bigdata-cli.sh build hadoop-ha  && ./bigdata-cli.sh start hadoop-ha
./bigdata-cli.sh build mysql      && ./bigdata-cli.sh start mysql
./bigdata-cli.sh build hbase      && ./bigdata-cli.sh start hbase
./bigdata-cli.sh build hive       && ./bigdata-cli.sh start hive
./bigdata-cli.sh build kafka      && ./bigdata-cli.sh start kafka
./bigdata-cli.sh build spark      && ./bigdata-cli.sh start spark
./bigdata-cli.sh build flink      && ./bigdata-cli.sh start flink
./bigdata-cli.sh build flume      && ./bigdata-cli.sh start flume
```

> 详细用法请参考 [CLI_USAGE.md](CLI_USAGE.md)

### 手动部署

### 1. 环境准备
```bash
# 创建Docker网络（所有组件共享同一网络）
./scripts/network.sh create

# 同步组件版本信息
./scripts/update-dockerfile-versions.sh
```

### 2. 构建镜像（可选）
```bash
# 构建基础镜像（所有组件的基础）
docker build -f dockerfile.base -t bigdata-base:latest .

# 单独构建特定组件镜像
docker build -f dockerfile.hadoop -t bigdata-hadoop:latest .
docker build -f dockerfile.hbase -t bigdata-hbase:latest .
docker build -f dockerfile.hive -t bigdata-hive:latest .
docker build -f dockerfile.zookeeper -t bigdata-zookeeper:latest .
docker build -f dockerfile.kafka -t bigdata-kafka:latest .
docker build -f dockerfile.spark -t bigdata-spark:latest .
docker build -f dockerfile.flink -t bigdata-flink:latest .
docker build -f dockerfile.flume -t bigdata-flume:latest .
docker build -f dockerfile.mysql -t bigdata-mysql:latest .
```

### 3. 启动集群
```bash
# 创建大数据平台专用网络


# 按依赖顺序启动组件（启动命令见下方表格）
# 依赖顺序：ZooKeeper → Hadoop → MySQL → HBase → Hive → Kafka → Spark → Flink → Flume
```

### 4. 服务访问地址和启动命令

| 组件 | Web UI | 端口 | 启动命令 | 依赖关系 |
|------|--------|------|----------|----------|
| **ZooKeeper** | - | 2181 | `docker-compose -f docker-compose.zookeeper.yml up -d` | 无依赖 |
| **Hadoop HDFS** | http://localhost:9870 | 9870 | `docker-compose -f docker-compose.hadoop.yml up -d` | 依赖ZooKeeper |
| **Hadoop YARN** | http://localhost:8088 | 8088 | `docker-compose -f docker-compose.hadoop.yml up -d` | 依赖HDFS |
| **Hadoop HA HDFS** | http://localhost:19870 | 19870 | `docker-compose -f docker-compose.hadoop-ha.yml up -d` | 依赖ZooKeeper |
| **MySQL** | - | 3306 | `docker-compose -f docker-compose.mysql.yml up -d` | 无依赖 |
| **HBase** | http://localhost:16010 | 16010 | `docker-compose -f docker-compose.hbase.yml up -d` | 依赖HDFS+ZooKeeper |
| **Hive** | http://localhost:10002 | 10002 | `docker-compose -f docker-compose.hive.yml up -d` | 依赖HDFS+MySQL |
| **Kafka** | - | 9092 | `docker-compose -f docker-compose.kafka.yml up -d` | 依赖ZooKeeper |
| **Spark** | http://localhost:8080 | 8080 | `docker-compose -f docker-compose.spark.yml up -d` | 依赖HDFS |
| **Flink** | http://localhost:8081 | 8081 | `docker-compose -f docker-compose.flink.yml up -d` | 依赖HDFS |
| **Flume** | - | - | `docker-compose -f docker-compose.flume.yml up -d` | 依赖Kafka |

### 5. 功能测试
```bash
# 单独测试各组件
./test/test-hadoop.sh        # Hadoop功能测试
./test/test-hadoop-ha.sh     # Hadoop高可用功能测试
./test/test-hbase.sh         # HBase功能测试
./test/test-hive.sh          # Hive功能测试
./test/test-zookeeper.sh     # ZooKeeper功能测试
./test/test-kafka.sh         # Kafka功能测试
./test/test-spark.sh         # Spark功能测试
./test/test-flink.sh         # Flink功能测试
./test/test-flume.sh         # Flume功能测试
./test/test-mysql.sh         # MySQL功能测试

# 测试Flume与Kafka联动
./test/test-flume-kafka.sh

# 测试Hadoop高可用模式
./test/test-hadoop-ha.sh
```

### 6. 服务管理
```bash
# 查看所有容器状态
docker ps

# 查看特定组件日志
docker-compose -f docker-compose.hadoop.yml logs -f

# 停止特定组件
docker-compose -f docker-compose.hadoop.yml down

# 重启特定组件
docker-compose -f docker-compose.hadoop.yml restart

# 清理数据（谨慎使用）
docker-compose -f docker-compose.hadoop.yml down -v
```

### 7. 常用操作示例

#### Hadoop操作
```bash
# 进入Hadoop容器
docker exec -it hadoop-namenode-1 bash

# HDFS文件操作
hdfs dfs -ls /                    # 列出根目录
hdfs dfs -mkdir /user/test        # 创建目录
hdfs dfs -put localfile.txt /user/test/  # 上传文件
hdfs dfs -cat /user/test/localfile.txt   # 查看文件内容
hdfs dfs -rm /user/test/localfile.txt    # 删除文件
hdfs dfs -du -h /user/test        # 查看目录大小
hdfs dfs -chmod 755 /user/test    # 修改权限
hdfs dfs -cp /user/test/localfile.txt /user/backup/  # 复制文件

# HDFS管理
hdfs dfsadmin -report             # 查看集群状态
hdfs dfsadmin -safemode get       # 检查安全模式
hdfs dfsadmin -safemode leave     # 退出安全模式

# YARN作业提交
yarn jar /opt/hadoop/share/hadoop/mapreduce/hadoop-mapreduce-examples-3.1.3.jar pi 10 100

# MapReduce作业
yarn jar /opt/hadoop/share/hadoop/mapreduce/hadoop-mapreduce-examples-3.1.3.jar wordcount /user/test/input /user/test/output

# YARN管理
yarn node -list                   # 查看节点列表
yarn application -list            # 查看应用列表
yarn application -kill <app_id>   # 停止应用
```

#### HBase操作
```bash
# 进入HBase容器
docker exec -it hbase-master-1 bash

# HBase Shell
hbase shell

# 表操作
create 'test_table', 'cf1', 'cf2'                    # 创建表
list                                                  # 列出所有表
describe 'test_table'                                # 查看表结构
disable 'test_table'                                 # 禁用表
drop 'test_table'                                    # 删除表

# 数据操作
put 'test_table', 'row1', 'cf1:name', 'value1'       # 插入数据
put 'test_table', 'row1', 'cf2:age', '25'            # 插入另一列族数据
get 'test_table', 'row1'                             # 获取单行数据
get 'test_table', 'row1', 'cf1'                      # 获取指定列族
scan 'test_table'                                    # 扫描全表
delete 'test_table', 'row1', 'cf1:name'              # 删除数据

# 管理操作
status                                               # 集群状态
version                                              # HBase版本
```

#### Hive操作
```bash
# 连接HiveServer2
beeline -u jdbc:hive2://localhost:10000

# 数据库操作
CREATE DATABASE test_db;                    # 创建数据库
SHOW DATABASES;                             # 列出数据库
USE test_db;                                # 切换数据库

# 表操作
CREATE TABLE test_table (id INT, name STRING, age INT) PARTITIONED BY (dt STRING);
SHOW TABLES;                                # 列出表
DESCRIBE test_table;                        # 查看表结构

# 数据操作
INSERT INTO test_table VALUES (1, 'Alice', 25, '2024-01-01');
INSERT INTO test_table VALUES (2, 'Bob', 30, '2024-01-01');
SELECT * FROM test_table;                   # 查询数据
SELECT name, age FROM test_table WHERE age > 25;  # 条件查询

# 分区操作
SHOW PARTITIONS test_table;                 # 查看分区
ALTER TABLE test_table ADD PARTITION (dt='2024-01-02');

# 外部表操作
CREATE EXTERNAL TABLE external_table (id INT, name STRING) 
LOCATION '/user/hive/external_table';

# 视图操作
CREATE VIEW test_view AS SELECT name, age FROM test_table WHERE age > 25;
SELECT * FROM test_view;

# 数据导出
INSERT OVERWRITE LOCAL DIRECTORY '/tmp/output' SELECT * FROM test_table;
```

#### ZooKeeper操作
```bash
# 进入ZooKeeper容器
docker exec -it zookeeper-1 bash

# 连接ZooKeeper
zkCli.sh -server localhost:2181

# 节点操作
ls /                                      # 列出根节点
create /test_node "test_data"            # 创建节点
get /test_node                           # 获取节点数据
set /test_node "updated_data"            # 更新节点数据
delete /test_node                        # 删除节点

# 监控操作
stat /                                   # 查看节点状态
ls2 /                                    # 详细列出节点
```

#### Kafka操作
```bash
# 进入Kafka容器
docker exec -it kafka-broker-1 bash

# 主题操作
kafka-topics.sh --create --topic test-topic --partitions 3 --replication-factor 3 --bootstrap-server localhost:9092
kafka-topics.sh --list --bootstrap-server localhost:9092
kafka-topics.sh --describe --topic test-topic --bootstrap-server localhost:9092

# 生产消息
echo "test message 1" | kafka-console-producer.sh --topic test-topic --bootstrap-server localhost:9092
echo "test message 2" | kafka-console-producer.sh --topic test-topic --bootstrap-server localhost:9092

# 消费消息
kafka-console-consumer.sh --topic test-topic --from-beginning --bootstrap-server localhost:9092
kafka-console-consumer.sh --topic test-topic --group test-group --bootstrap-server localhost:9092

# 查看消费者组
kafka-consumer-groups.sh --list --bootstrap-server localhost:9092
kafka-consumer-groups.sh --describe --group test-group --bootstrap-server localhost:9092
```

#### Spark操作
```bash
# 进入Spark容器
docker exec -it spark-master-1 bash

# Spark Shell交互
spark-shell --master spark://spark-master:7077

# 提交Spark作业
spark-submit --class org.apache.spark.examples.SparkPi --master spark://spark-master:7077 /opt/spark/examples/jars/spark-examples_2.12-3.1.1.jar 100

# YARN模式提交
spark-submit --class org.apache.spark.examples.SparkPi --master yarn /opt/spark/examples/jars/spark-examples_2.12-3.1.1.jar 100

# 读取HDFS数据
spark-submit --class org.apache.spark.examples.SparkPi --master spark://spark-master:7077 --conf spark.sql.warehouse.dir=/user/hive/warehouse /opt/spark/examples/jars/spark-examples_2.12-3.1.1.jar 100
```

#### Flink操作
```bash
# 进入Flink容器
docker exec -it flink-jobmanager-1 bash

# 提交Flink作业
flink run -d /opt/flink/examples/streaming/WordCount.jar --input hdfs://namenode:9000/user/test/input --output hdfs://namenode:9000/user/test/output

# 查看作业状态
flink list
flink cancel <job_id>

# 提交批处理作业
flink run -d /opt/flink/examples/batch/WordCount.jar --input hdfs://namenode:9000/user/test/input --output hdfs://namenode:9000/user/test/output
```

#### Flume操作
```bash
# 进入Flume容器
docker exec -it flume-agent-1 bash

# 启动Flume Agent
flume-ng agent --conf /opt/flume/conf --conf-file /opt/flume/conf/flume-kafka.conf --name agent -Dflume.root.logger=INFO,console

# 测试数据流
echo "test log message" >> /tmp/test.log
```

## 🚀 架构二：5节点全栈集群部署

### 1. 构建统一镜像
```bash
# 构建基础镜像
docker build -f dockerfile.base -t bigdata-base:latest .

# 构建全栈镜像
docker build -f dockerfile.all-in-one -t bigdata-all-in-one:latest .
```

### 2. 启动集群
```bash
# 一键启动5节点集群
docker-compose -f docker-compose.5-node-cluster.yml up -d
```

### 3. 服务启动顺序
集群启动时，每个节点的entrypoint脚本会按以下顺序启动服务：

**Worker节点启动流程**：
1. ZooKeeper → 2. DataNode → 3. NodeManager → 4. Kafka → 5. HBase RegionServer → 6. Spark Worker → 7. Flink TaskManager

**Master节点启动流程**：
1. NameNode → 2. ResourceManager → 3. Hive Metastore → 4. Hive Server2 → 5. HBase Master → 6. Spark Master → 7. Flink JobManager

**Infra节点启动流程**：
1. MySQL → 2. Flume Agent

### 4. 服务访问地址

| 服务 | Web UI | 映射端口 | 容器端口 |
|------|--------|----------|----------|
| **HDFS NameNode** | http://localhost:29870 | 29870 | 9870 |
| **YARN ResourceManager** | http://localhost:28088 | 28088 | 8088 |
| **HBase Master** | http://localhost:26010 | 26010 | 16010 |
| **Spark Master** | http://localhost:28080 | 28080 | 8080 |
| **Flink Dashboard** | http://localhost:28081 | 28081 | 8081 |
| **HiveServer2** | http://localhost:21002 | 21002 | 10002 |

### 5. 功能测试
```bash
# 运行完整集群功能测试（73项测试）
./test/cluster-test.sh

# 测试结果示例
# ========================================
#   测试结果汇总
# ========================================
#   总测试数: 73
#   通过: 73
#   失败: 0
#   跳过: 0
#   成功率: 100%
```

### 6. 服务管理

#### 查看服务状态
```bash
# 查看容器状态
docker-compose -f docker-compose.5-node-cluster.yml ps

# 查看各节点Supervisor服务状态
docker exec master supervisorctl status
docker exec worker-1 supervisorctl status
docker exec infra supervisorctl status
```

#### 日志管理
```bash
# 查看所有容器日志
docker-compose -f docker-compose.5-node-cluster.yml logs -f

# 查看特定节点日志
docker logs -f master
docker logs -f worker-1

# 查看特定服务日志
docker exec master tail -f /opt/hadoop/logs/hadoop-root-namenode-master.log
```

#### 集群操作
```bash
# 停止集群
docker-compose -f docker-compose.5-node-cluster.yml down

# 重启集群
docker-compose -f docker-compose.5-node-cluster.yml restart

# 清理数据卷（谨慎使用）
docker-compose -f docker-compose.5-node-cluster.yml down -v
```

### 7. 常用操作示例

#### 集群内操作
```bash
# 进入Master节点
docker exec -it master bash

# HDFS操作
hdfs dfs -ls /
hdfs dfs -mkdir -p /user/test
hdfs dfs -put /opt/hadoop/LICENSE.txt /user/test/

# HBase操作
hbase shell
create 'test_table', 'cf1', 'cf2'
put 'test_table', 'row1', 'cf1:name', 'value1'
scan 'test_table'

# Hive操作
beeline -u jdbc:hive2://localhost:10000
CREATE DATABASE test_db;
USE test_db;
CREATE TABLE test_table (id INT, name STRING);
INSERT INTO test_table VALUES (1, 'test_value');
SELECT * FROM test_table;
```

#### Kafka操作
```bash
# 进入Worker节点
docker exec -it worker-1 bash

# Kafka主题操作
kafka-topics.sh --create --topic test-topic --partitions 3 --replication-factor 3 --bootstrap-server worker-1:9092
kafka-topics.sh --list --bootstrap-server worker-1:9092

# 生产消息
echo "test message" | kafka-console-producer.sh --topic test-topic --bootstrap-server worker-1:9092

# 消费消息
kafka-console-consumer.sh --topic test-topic --from-beginning --bootstrap-server worker-1:9092
```

#### Spark操作
```bash
# Spark Pi计算示例（Standalone模式）
spark-submit --class org.apache.spark.examples.SparkPi --master spark://master:7077 /opt/spark/examples/jars/spark-examples_2.12-3.1.1.jar 100

# Spark Pi计算示例（YARN模式）
spark-submit --class org.apache.spark.examples.SparkPi --master yarn /opt/spark/examples/jars/spark-examples_2.12-3.1.1.jar 100
```

#### Flink操作
```bash
# 提交Flink WordCount作业
flink run -d /opt/flink/examples/streaming/WordCount.jar --input hdfs://master:9000/user/test/LICENSE.txt --output hdfs://master:9000/user/test/wordcount-output

# 查看Flink作业状态
flink list
```

## 🔧 故障排除

### 常见问题

#### 1. HDFS安全模式问题
```bash
# 检查安全模式状态
docker exec master hdfs dfsadmin -safemode get

# 强制退出安全模式
docker exec master hdfs dfsadmin -safemode leave
```

#### 2. HBase启动失败
```bash
# 清理HBase残留数据
docker exec master hdfs dfs -rm -r -skipTrash /hbase
docker exec master hdfs dfs -rm -r -skipTrash /tmp/hbase

# 重启HBase服务
docker exec master supervisorctl restart hbase-master
```

#### 3. 内存不足问题
- 检查Docker内存限制：Docker Desktop → Settings → Resources
- 调整容器内存限制：修改docker-compose文件中的内存配置
- 优化组件内存配置：修改config目录下的配置文件

#### 4. 端口冲突问题
- 检查端口占用：`netstat -an | grep <端口号>`
- 修改映射端口：编辑docker-compose文件中的ports配置

### 性能优化建议

1. **内存优化**：根据物理内存调整各组件内存配置
2. **磁盘优化**：使用SSD存储，配置数据卷优化IO性能
3. **网络优化**：使用host网络模式减少网络开销
4. **配置优化**：根据负载调整HDFS块大小、Spark分区数等参数

## 📊 监控与维护

### 健康监控
每个节点都运行健康监控服务，定期检查关键服务状态：
```bash
# 查看健康监控日志
docker exec master tail -f /opt/hadoop/logs/health-monitor.log
```

### 性能监控
- **HDFS**：NameNode Web UI (http://localhost:29870)
- **YARN**：ResourceManager Web UI (http://localhost:28088)
- **HBase**：HMaster Web UI (http://localhost:26010)
- **Spark**：Master Web UI (http://localhost:28080)
- **Flink**：Dashboard (http://localhost:28081)

## 🎨 可视化配置工具

项目提供了基于 PyQt5 的可视化配置工具，支持图形化方式管理所有组件的配置文件。

### 主要功能特性

- **多格式支持**：支持 XML、Properties、Shell、INI、YAML、Spark配置、列表文件、纯文本等 9 种文件格式
- **组件管理**：动态添加/删除组件，自动创建工作目录
- **文件管理**：支持新增配置文件，自动检测文件类型并创建模板
- **智能编辑**：表格模式和纯文本模式双界面，预设配置项和详细说明
- **核心标记**：用 * 标识系统必需配置项，避免遗漏关键配置
- **独立运行**：基于工作目录架构，解耦 config/ 目录依赖

### 快速使用

```bash
# 进入可视化工具目录
cd config-visualizer

# 启动可视化配置工具
python main.py
```

### 界面功能

1. **左侧面板**：
   - 组件列表：显示所有大数据组件
   - 配置文件列表：显示当前组件的配置文件
   - 新增组件/文件按钮：支持动态添加

2. **右侧编辑器**：
   - 表格模式：结构化配置项编辑，支持下拉选择
   - 纯文本模式：自由编辑非结构化配置文件
   - 保存按钮：保存到工作目录
   - 同步按钮：将工作目录文件推送到 config/ 目录

### 支持的文件类型

| 文件类型 | 扩展名 | 说明 |
|---------|--------|------|
| XML配置 | .xml | Hadoop、HBase、Hive配置文件 |
| Properties配置 | .properties | Kafka、ZooKeeper配置文件 |
| 键值对配置 | .conf/.cfg | Flume配置文件 |
| Spark配置 | spark-defaults.conf | 空格分隔的键值对 |
| Shell环境变量 | .sh | Spark、Hadoop环境变量 |
| INI配置 | .cnf/.ini | MySQL配置文件 |
| YAML配置 | .yaml/.yml | Flink配置文件 |
| 列表配置 | workers/slaves等 | 主机名列表文件 |
| 纯文本文件 | .txt/.md等 | 自由编辑的文本文件 |

### 工作流程

1. **选择组件** → 显示该组件的配置文件列表
2. **选择文件** → 自动检测文件类型并加载到编辑器
3. **编辑配置** → 表格模式或纯文本模式编辑
4. **保存配置** → 保存到工作目录（output/）
5. **同步到源** → 可选将工作目录文件推送到 config/

### 新增组件示例

1. 点击"➕ 新增组件"按钮
2. 填写组件标识（如：clickhouse）、显示名称（如：ClickHouse）、配置目录
3. 自动在工作目录创建对应子目录
4. 点击"➕ 新增文件"添加配置文件
5. 选择文件类型，自动创建模板并加载编辑

> 可视化工具详细使用说明请参考工具内帮助信息
│   │   └── supervisor/       # Supervisor服务配置
│   └── component/            # 单组件独立集群配置
│       ├── hadoop/           # Hadoop标准配置
│       ├── hadoop-ha/        # Hadoop高可用配置
│       ├── hbase/            # HBase配置
│       ├── hive/             # Hive配置
│       ├── kafka/            # Kafka配置
│       ├── spark/            # Spark配置
│       ├── flink/            # Flink配置
│       ├── zookeeper/        # ZooKeeper配置
│       ├── mysql/            # MySQL配置
│       ├── flume/            # Flume配置
│       └── supervisor/       # Supervisor配置
├── scripts/                  # 管理脚本目录
│   ├── all-in-one-entrypoint.sh  # 5节点集群统一启动脚本
│   ├── hadoop-entrypoint.sh      # Hadoop启动脚本
│   ├── hadoop-ha-entrypoint.sh   # Hadoop高可用启动脚本
│   ├── hbase-entrypoint.sh       # HBase启动脚本
│   ├── hive-entrypoint.sh        # Hive启动脚本
│   ├── kafka-entrypoint.sh       # Kafka启动脚本
│   ├── spark-entrypoint.sh       # Spark启动脚本
│   ├── flink-entrypoint.sh       # Flink启动脚本
│   ├── zookeeper-entrypoint.sh   # ZooKeeper启动脚本
│   ├── mysql-entrypoint.sh       # MySQL启动脚本
│   ├── flume-entrypoint.sh       # Flume启动脚本
│   ├── network.sh                # Docker网络管理脚本
│   └── update-dockerfile-versions.sh  # 版本同步脚本
├── test/                     # 测试脚本目录
│   ├── cluster-test.sh           # 5节点全栈集群完整测试
│   ├── test-hadoop.sh            # Hadoop独立测试
│   ├── test-hadoop-ha.sh         # Hadoop高可用测试
│   ├── test-hbase.sh             # HBase独立测试
│   ├── test-hive.sh              # Hive独立测试
│   ├── test-kafka.sh             # Kafka独立测试
│   ├── test-spark.sh             # Spark独立测试
│   ├── test-flink.sh             # Flink独立测试
│   ├── test-flume.sh             # Flume独立测试
│   ├── test-flume-kafka.sh       # Flume-Kafka联动测试
│   ├── test-mysql.sh             # MySQL独立测试
│   ├── test-zookeeper.sh         # ZooKeeper独立测试
│   └── *.md                      # 测试文档说明
├── module/                   # 组件安装包目录
│   ├── hadoop-3.1.3.tar.gz          # Hadoop安装包
│   ├── apache-hive-3.1.2-bin.tar.gz # Hive安装包
│   ├── hbase-2.2.3-bin.tar.gz       # HBase安装包
│   ├── apache-zookeeper-3.6.3-bin.tar.gz # ZooKeeper安装包
│   ├── kafka_2.12-2.4.1.tgz         # Kafka安装包
│   ├── spark-3.1.1-bin-hadoop3.2.tgz # Spark安装包
│   ├── flink-1.14.0-bin-scala_2.12.tar # Flink安装包
│   ├── apache-flume-1.9.0-bin.tar.gz # Flume安装包
│   ├── mysql-connector-java-5.1.49.jar # MySQL JDBC驱动
│   └── guava-27.0-jre.jar           # Guava库（Hive依赖）
├── dockerfile.all-in-one     # 5节点全栈集群统一镜像构建文件
├── dockerfile.base           # 基础镜像构建文件
├── dockerfile.hadoop         # Hadoop镜像构建文件
├── dockerfile.hbase          # HBase镜像构建文件
├── dockerfile.hive           # Hive镜像构建文件
├── dockerfile.zookeeper      # ZooKeeper镜像构建文件
├── dockerfile.kafka          # Kafka镜像构建文件
├── dockerfile.spark          # Spark镜像构建文件
├── dockerfile.flink          # Flink镜像构建文件
├── dockerfile.flume          # Flume镜像构建文件
├── dockerfile.mysql          # MySQL镜像构建文件
├── docker-compose.5-node-cluster.yml    # 5节点全栈集群编排文件
├── docker-compose.hadoop.yml            # Hadoop集群编排文件
├── docker-compose.hadoop-ha.yml         # Hadoop高可用编排文件
├── docker-compose.hbase.yml             # HBase集群编排文件
├── docker-compose.hive.yml              # Hive服务编排文件
├── docker-compose.kafka.yml             # Kafka集群编排文件
├── docker-compose.spark.yml             # Spark集群编排文件
├── docker-compose.flink.yml             # Flink集群编排文件
├── docker-compose.zookeeper.yml         # ZooKeeper集群编排文件
├── docker-compose.mysql.yml             # MySQL服务编排文件
├── docker-compose.flume.yml             # Flume服务编排文件
├── bigdata-cli.sh            # 命令行管理工具（交互式菜单+命令行模式）
├── README.md                # 项目主文档
└── Todo.md                  # 开发任务清单
```

## 📋 各目录详细作用

### 1. **config/ - 配置文件目录**
- **all-in-one/**：5节点全栈集群配置，按节点角色划分
- **component/**：单组件独立集群配置，按组件类型划分
- 包含XML、YAML、Properties等格式的配置文件
- 支持内存优化、网络配置、服务参数调整

### 2. **scripts/ - 管理脚本目录**
- **entrypoint脚本**：容器启动时的初始化脚本，处理服务依赖和配置
- **network.sh**：创建和管理Docker网络，确保组件间通信
- **update-dockerfile-versions.sh**：同步所有Dockerfile的版本信息

### 3. **test/ - 测试脚本目录**
- **cluster-test.sh**：5节点全栈集群的完整功能测试（73项测试）
- **组件独立测试**：每个大数据组件的功能验证
- **集成测试**：组件间联动测试（如Flume-Kafka）
- **高可用测试**：Hadoop HA模式验证

### 4. **module/ - 组件安装包目录**
- 包含所有大数据组件的官方安装包
- 版本统一管理，确保兼容性
- 包含必要的依赖库（MySQL驱动、Guava等）

### 5. **Dockerfile文件**
- **dockerfile.base**：基础镜像，包含Java环境和系统工具
- **dockerfile.all-in-one**：5节点全栈集群统一镜像
- **组件Dockerfile**：各组件独立镜像构建文件

### 6. **Docker Compose文件**
- **docker-compose.5-node-cluster.yml**：5节点全栈集群编排
- **组件编排文件**：各组件独立集群的容器编排
- 定义服务依赖、网络配置、数据卷等

## 🔧 文件作用总结

| 文件类型 | 主要作用 | 关键文件示例 |
|----------|----------|--------------|
| **配置文件** | 定义服务参数和运行环境 | `config/all-in-one/hadoop/core-site.xml` |
| **启动脚本** | 容器初始化和服务管理 | `scripts/all-in-one-entrypoint.sh` |
| **测试脚本** | 验证集群功能和性能 | `test/cluster-test.sh` |
| **构建文件** | 镜像构建和环境准备 | `dockerfile.all-in-one` |
| **编排文件** | 容器部署和服务编排 | `docker-compose.5-node-cluster.yml` |
| **安装包** | 组件二进制文件和依赖 | `module/hadoop-3.1.3.tar.gz` |

## 🤝 贡献指南

欢迎贡献代码和文档！请遵循以下步骤：

1. Fork 本项目
2. 创建功能分支：`git checkout -b feature/AmazingFeature`
3. 提交更改：`git commit -m 'Add some AmazingFeature'`
4. 推送到分支：`git push origin feature/AmazingFeature`
5. 提交 Pull Request

## 📄 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。

## 🙏 致谢

感谢以下开源项目：
- Apache Hadoop, HBase, Hive, Spark, Flink, Kafka, ZooKeeper, Flume
- Docker & Docker Compose
- Ubuntu WSL2

---

**注意**：本项目主要用于学习和测试目的，生产环境使用前请进行充分测试和性能优化。