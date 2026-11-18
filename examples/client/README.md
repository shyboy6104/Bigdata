# 大数据代码开发容器 · 示例与自检

本目录在容器**每次启动**时按文件粒度增量投放到 `/workspace`（`cp -rn`，不会覆盖你已有的代码），因此镜像构建之后新增的示例也能补进已创建的环境。
主平台对应宿主机 `./workspace`，学生独立环境对应 `stacks/<用户名>/workspace`，重启容器不丢失。

进入容器：在网页「▣ 全交互」终端里操作，或 `docker exec -it client bash -l`。
一定要用**登录 shell**（`bash -l`），否则 `/etc/profile.d/bigdata-client.sh` 里的环境变量不会加载。

## 1. 先自检

```bash
cd /workspace
python3 python/check_libs.py
```

会逐项打印 Python 库版本与命令行工具（`hadoop` / `beeline` / `flink` / `mvn` / `spark-submit` 等）是否在 PATH 中。

## 2. 服务地址（容器内直接用服务名）

| 组件 | 地址 | 说明 |
|---|---|---|
| HDFS | `hdfs://namenode:8020` | HA 模式为 `hdfs://mycluster`，由 `config/environment.conf` 自动切换 |
| Spark 集群 | `spark://spark-master:7077` | `spark-submit --master` 指定 |
| HiveServer2 | `hive-server2:10000` | PyHive / beeline |
| Hive Metastore | `thrift://hive-metastore:9083` | |
| Kafka | `kafka1:9092,kafka2:9092,kafka3:9092` | |
| Flume | `flume-kafka` | 见下方说明 |

**必须先启动要用的组件**，否则对应 API 连不上。开发容器本身不会自动拉起 Hadoop / Kafka / Hive。

## 3. 示例脚本

| 文件 | 运行方式 | 前置组件 |
|---|---|---|
| `python/pyspark_wordcount.py` | `python3 python/pyspark_wordcount.py`（默认 `local[*]`） | 无；切集群：`SPARK_MASTER=spark://spark-master:7077 python3 python/pyspark_wordcount.py`（需先起 Hadoop + Spark） |
| `python/kafka_demo.py` | `python3 python/kafka_demo.py` | Kafka（+ ZooKeeper）。单文件内先产后消，快速冒烟 |
| `python/kafka_producer.py` | `python3 python/kafka_producer.py --count 5` | Kafka（+ ZooKeeper）。**独立生产者** |
| `python/kafka_consumer.py` | `python3 python/kafka_consumer.py --max 5` | Kafka（+ ZooKeeper）。**独立消费者** |
| `python/hive_query.py` | `python3 python/hive_query.py` | Hive（+ Hadoop + MySQL） |
| `java/run-wordcount.sh` | `bash java/run-wordcount.sh` | Hadoop |

### 3.1 Kafka 生产者 / 消费者（两个独立程序）

先在网页 `/portal`（学生）或 `/bigdata`（教师）启动 **Kafka**，系统会自动先拉起 ZooKeeper；确认 3 个 broker 就绪后，在 client 容器里：

```bash
cd /workspace

# 终端 A：先启动消费者（等待消息）
python3 python/kafka_consumer.py --topic client-demo --max 5 --timeout 30 --latest

# 终端 B：生产者发送
python3 python/kafka_producer.py --topic client-demo --count 5
```

也可以**先生产、后消费**：消费者默认 `auto_offset_reset=earliest`，会把已写入的历史消息读出来，适合单终端验证：

```bash
python3 python/kafka_producer.py --topic client-demo --count 5
python3 python/kafka_consumer.py --topic client-demo --max 5   # 从头读，收齐即退出
```

两个脚本的公共参数：`--bootstrap`（默认 `kafka1:9092,kafka2:9092,kafka3:9092`，也可用环境变量 `KAFKA_BOOTSTRAP`）、`--topic`（默认 `client-demo`，环境变量 `KAFKA_TOPIC`）。消费者另有 `--group`（消费组）、`--latest`（只读新消息）、`--max`（收够 N 条退出）、`--timeout`（**空闲多少秒**后退出，默认 15；设 `0` 一直等待）。生产者用 `send().get()` 等待 broker 确认，会打印每条消息的 `partition` / `offset`；消息为 JSON 且含中文字段，可验证编码链路。

> 两个程序都连容器内部服务名 `kafka1/2/3:9092`（主平台走 `bigdata-net`，学生栈走 `bigdata-u<uid>-net`，**服务名不变**），不需要宿主机端口映射；宿主机上的 `19092/19093/19094`（学生栈为各自端口段）仅供外部客户端使用。

### 3.2 学生专属环境（多用户）下的 Kafka

在 `/portal` 启动 Kafka（会自动带起 ZooKeeper）+「代码开发 / Client 环境」后，容器名都带用户前缀。以 uid=6 的 stu1 为例：`u6-zoo1/2/3`、`u6-kafka1/2/3`、`u6-client`，同在专属网络 `bigdata-u6-net`。

**只需把进入容器的名字换成 `u6-client`，其余一条都不用改**：

```bash
docker exec -it u6-client bash -l
cd /workspace
python3 python/kafka_producer.py --topic client-demo --count 5
python3 python/kafka_consumer.py --topic client-demo --max 5
```

原因：`generate_user_compose()` 只改 `container_name` 和 `networks`，**服务名 `kafka1/kafka2/kafka3` 与 `hostname` 原样保留**；共享配置 `config/kafka/server*.properties` 里的 `advertised.listeners=PLAINTEXT://kafka1:9092` 也不会变。broker 返回给客户端的元数据永远是 `kafka1:9092`，所以脚本默认的 `--bootstrap` 就是正确值，**不要改成 `u6-kafka1:9092,...`** —— 容器名虽能被 Docker DNS 解析，但与 advertised 地址不一致，容易出现「连得上却发不出 / 收不到」。主平台那个公共 `client` 容器在 `bigdata-net`，看不到 `bigdata-u6-net`，不能拿来连学生集群。

**topic 不需要预先创建**：Kafka 2.4.1 的 `auto.create.topics.enable` 默认开启，生产者首次 `send()` 会自动建 topic，分区数取 `num.partitions=3`、副本数取 `default.replication.factor=3`；只是首条消息可能多一次元数据重试。若要显式控制分区数 / 副本数，在任一 broker 容器内执行：

```bash
docker exec -it u6-kafka1 bash -lc \
  '/opt/kafka/bin/kafka-topics.sh --create --bootstrap-server kafka1:9092 \
   --topic my-topic --partitions 3 --replication-factor 3'
docker exec -it u6-kafka1 bash -lc \
  '/opt/kafka/bin/kafka-topics.sh --list --bootstrap-server kafka1:9092'
```

> 提示：`--replication-factor 3` 要求 3 个 broker 全部在线。Git Bash 下若命令里含容器绝对路径，记得加 `MSYS_NO_PATHCONV=1` 前缀，避免路径被转成 Windows 格式。

## 4. 关于 Flume

当前 `config/flume/flume-kafka.conf` 使用的是 **exec source**（tail 容器内 `/var/log/application/application.log`）+ **Kafka sink**（topic `flume-logs`），它没有对外监听端口，因此不存在可直接调用的 Flume 网络 API。

在开发容器里"接 Flume 的数据"就是消费它写入 Kafka 的 `flume-logs` topic，`python/kafka_demo.py` 已演示。如果课程需要程序直接向 Flume 发送事件，需要把 source 改为 `avro` / `netcat` 并在 `docker-compose.flume.yml` 发布端口；镜像里已经预置 `flume-ng-sdk-1.9.0.jar` 和 `avro-python3` 库供这类改造使用。

## 5. Java 开发

- `BIGDATA_JARS` 由入口脚本生成，包含 Spark / Hadoop / Hive / Kafka / Flink / Flume 的客户端 jar（已过滤 `*-sources.jar` 等干扰包），用 `javac -cp "$BIGDATA_JARS" ...` 即可离线编译。
- 源码含中文注释时必须加 `-encoding UTF-8`（容器 `LANG` 已设为 `C.UTF-8`，但 javac 显式声明更保险），示例见 `java/run-wordcount.sh`。
- Maven 3.6.3 已安装（`mvn -v`），有网时也可以用标准 `pom.xml` 从中央仓库拉依赖。

## 6. Spark eventLog

开发容器默认把 `spark.eventLog.enabled` 设为 `false`，方便单机 `local[*]` 调试。
需要把作业历史交给 History Server 时：先启动 Hadoop，再设 `CLIENT_SPARK_EVENTLOG=true` 重启容器，或提交时 `--conf spark.eventLog.enabled=true`。
