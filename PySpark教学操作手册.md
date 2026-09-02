# PySpark 教学操作手册

本文档用于指导学生在本项目中完成 PySpark 环境构建、容器启动、基础功能实验和自动化测试。所有命令均在项目根目录执行。

项目中的 Spark 容器同时支持两套 API：

- Scala：使用 `spark-shell` 或 `spark-submit` 提交 JVM 作业。
- Python：使用 `pyspark` 或 `spark-submit Python文件.py` 提交 PySpark 作业。

本文首先使用“标准 Hadoop + 独立 Spark”架构完成基础实验，再说明“五节点全栈架构”的测试方法。

## 1. 实验环境与通过标准

本项目当前使用：

| 软件 | 版本或路径 | 用途 |
|---|---|---|
| Spark | 3.1.1 | Standalone、YARN、RDD、DataFrame 和 SQL |
| Python | 3.8.10 | Driver 与 Executor 的 Python 解释器 |
| PySpark | 3.1.1 | Spark 安装包自带，无需单独执行 `pip install` |
| Java | OpenJDK 8 | Spark JVM 运行环境 |
| Python 解释器 | `/usr/bin/python3` | Master、Worker 和 YARN 容器统一使用 |

完整基础实验通过时，应同时满足以下条件：

1. `spark-master`、`spark-worker1`、`spark-worker2` 均处于运行状态。
2. Spark Master 页面显示两个 Worker。
3. 三个 Spark 容器均可运行 Python 3。
4. Master 能导入 PySpark，且 PySpark 版本为 3.1.1。
5. Scala SparkPi 作业输出 `Pi is roughly`。
6. PySpark 作业能完成 RDD 与 DataFrame 计算，并输出 `PYSPARK_SMOKE_OK`。

PySpark 作业的主要执行关系如下：

```text
学生提交 Python 程序
        |
        v
spark-master 中的 Driver
        |
        +----> spark-worker1 中的 Executor ----> Python Worker
        |
        +----> spark-worker2 中的 Executor ----> Python Worker
```

因此，仅在 Master 中成功执行 `import pyspark` 还不能证明环境完整；必须提交一个包含 Python 转换函数的分布式作业，确认 Worker 也能启动 Python Worker 进程。

## 2. 实验前检查

### 2.1 进入项目目录

PowerShell：

```powershell
Set-Location E:\Programs\Bigdata
```

Git Bash 或 WSL：

```bash
cd /e/Programs/Bigdata
```

如果项目位于其他目录，请替换为实际路径。

### 2.2 检查 Docker

```powershell
docker version
docker compose version
```

通过条件：

- `docker version` 同时显示 Client 与 Server 信息。
- `docker compose version` 能显示 Compose V2 版本。
- 如果只有 Client 信息或提示无法连接 daemon，应先启动 Docker Desktop。

### 2.3 下载并检查 Spark 离线安装包

构建 `bigdata-spark:latest` 前，必须准备 Spark 3.1.1 的 Hadoop 3.2 预编译二进制包。`dockerfile.spark` 和 `dockerfile.all-in-one` 会读取以下文件：

```text
module/spark-3.1.1-bin-hadoop3.2.tgz
```

虽然本实验使用 PySpark，但这里应下载完整的 `spark-3.1.1-bin-hadoop3.2.tgz`，不需要另行下载 `pyspark-3.1.1.tar.gz`。完整 Spark 二进制包已经包含 Scala Spark、PySpark、Py4J、示例程序和 Hadoop 3.2 客户端依赖。

不要误下成以下文件：

- `spark-3.1.1-bin-hadoop2.7.tgz`：面向 Hadoop 2.7。
- `spark-3.1.1-bin-without-hadoop.tgz`：不包含 Hadoop 客户端依赖。
- `spark-3.1.1.tgz`：Spark 源码包，不是可直接运行的预编译包。
- `pyspark-3.1.1.tar.gz`：单独发布的 Python 包，不是当前 Dockerfile 需要的完整 Spark 发行包。

可以用浏览器从 [Apache Spark 3.1.1 官方归档目录](https://archive.apache.org/dist/spark/spark-3.1.1/) 下载，也可以在项目根目录使用 PowerShell：

```powershell
curl.exe -fL "https://archive.apache.org/dist/spark/spark-3.1.1/spark-3.1.1-bin-hadoop3.2.tgz" -o "module\spark-3.1.1-bin-hadoop3.2.tgz"
```

下载完成后检查文件：

```powershell
Get-Item module\spark-3.1.1-bin-hadoop3.2.tgz | Select-Object Name, Length, LastWriteTime
```

预期文件名为 `spark-3.1.1-bin-hadoop3.2.tgz`，大小约为 218 MiB。还可以下载 Apache 提供的 SHA-512 文件并计算本地摘要：

```powershell
curl.exe -fL "https://archive.apache.org/dist/spark/spark-3.1.1/spark-3.1.1-bin-hadoop3.2.tgz.sha512" -o "module\spark-3.1.1-bin-hadoop3.2.tgz.sha512"
Get-FileHash module\spark-3.1.1-bin-hadoop3.2.tgz -Algorithm SHA512
Get-Content module\spark-3.1.1-bin-hadoop3.2.tgz.sha512
```

通过条件：

- 压缩包位于项目的 `module` 目录。
- 文件名必须精确为 `spark-3.1.1-bin-hadoop3.2.tgz`。
- 文件不是 0 字节，大小与官方归档页面所列大小基本一致。
- 本地 `Get-FileHash` 输出的 SHA-512 值与官方 `.sha512` 文件中的值一致。

镜像构建会直接复制该压缩包，不会在构建过程中在线下载 Spark。Spark 3.1.1 已属于历史版本，本项目固定该版本是为了与现有教学环境和 Hadoop 依赖保持一致。

### 2.4 下载并检查 Hadoop 离线安装包

如果只构建 Spark 镜像，需要准备上一节的 Spark 压缩包；如果还要按照本文启动标准 Hadoop，则必须另外准备 Hadoop 3.1.3 二进制压缩包。

`dockerfile.hadoop` 中的默认版本为 `3.1.3`，构建时会读取以下文件：

```text
module/hadoop-3.1.3.tar.gz
```

注意应下载名称为 `hadoop-3.1.3.tar.gz` 的二进制发行包，不要误下成 `hadoop-3.1.3-src.tar.gz` 源码包或 `hadoop-3.1.3-site.tar.gz` 文档包。

可以用浏览器从 [Apache Hadoop 3.1.3 官方归档目录](https://archive.apache.org/dist/hadoop/common/hadoop-3.1.3/) 下载，也可以在项目根目录使用 PowerShell：

```powershell
curl.exe -fL "https://archive.apache.org/dist/hadoop/common/hadoop-3.1.3/hadoop-3.1.3.tar.gz" -o "module\hadoop-3.1.3.tar.gz"
```

下载完成后检查文件：

```powershell
Get-Item module\hadoop-3.1.3.tar.gz | Select-Object Name, Length, LastWriteTime
```

预期文件名为 `hadoop-3.1.3.tar.gz`，大小约为 322 MiB。还可以下载 Apache 提供的 SHA-512 文件并计算本地摘要：

```powershell
curl.exe -fL "https://archive.apache.org/dist/hadoop/common/hadoop-3.1.3/hadoop-3.1.3.tar.gz.sha512" -o "module\hadoop-3.1.3.tar.gz.sha512"
Get-FileHash module\hadoop-3.1.3.tar.gz -Algorithm SHA512
Get-Content module\hadoop-3.1.3.tar.gz.sha512
```

通过条件：

- 压缩包位于项目的 `module` 目录。
- 文件名必须精确为 `hadoop-3.1.3.tar.gz`。
- 文件不是 0 字节，大小与官方归档页面所列大小基本一致。
- 本地 `Get-FileHash` 输出的 SHA-512 值与官方 `.sha512` 文件中的值一致。

Hadoop 3.1.3 已属于历史版本，本项目固定该版本是为了与现有教学镜像和组件配置保持一致，不代表生产环境的版本建议。

## 3. 构建 PySpark 镜像

Spark 镜像依赖基础镜像；若要同时启动标准 Hadoop，还需要先按 2.4 节下载 Hadoop 压缩包并构建 Hadoop 镜像。按以下顺序执行：

```powershell
docker build -f dockerfile.base -t bigdata-base:latest .
docker build -f dockerfile.hadoop -t bigdata-hadoop:latest .
docker build -f dockerfile.spark -t bigdata-spark:latest .
```

每条命令都应以 `Successfully tagged`、`naming to` 或构建成功信息结束，且退出码为 0。

查看镜像：

```powershell
docker image ls bigdata-base:latest
docker image ls bigdata-hadoop:latest
docker image ls bigdata-spark:latest
```

### 3.1 在启动集群前检查镜像中的运行时

```powershell
docker run --rm --entrypoint bash bigdata-spark:latest -c "python3 --version && python3 -c 'import pyspark; print(pyspark.__version__)' && spark-submit --version"
```

预期看到类似内容：

```text
Python 3.8.10
3.1.1
version 3.1.1
```

通过条件：三个检查都成功，尤其是 `import pyspark` 不能出现 `ModuleNotFoundError`。

## 4. 启动独立组件架构

基础教学推荐使用标准 Hadoop 和 Spark Standalone。Hadoop 提供 HDFS、YARN 和 Spark History Server 所需的存储路径，Spark 集群由一个 Master 和两个 Worker 组成。

### 4.1 创建公共 Docker 网络

先检查网络：

```powershell
docker network inspect bigdata-net
```

如果提示网络不存在，再执行：

```powershell
docker network create bigdata-net
```

通过条件：命令能返回 `bigdata-net` 的网络信息。Compose 文件将各组件接入该外部网络，以便 Spark 通过容器名访问 Hadoop。

### 4.2 启动标准 Hadoop

```powershell
docker compose -f docker-compose.hadoop.yml up -d
docker compose -f docker-compose.hadoop.yml ps
```

应看到以下容器处于 `Up` 或 `running` 状态：

- `namenode`
- `datanode1`
- `datanode2`

检查 HDFS：

```powershell
docker exec namenode hdfs dfsadmin -report
```

通过条件：命令成功返回 HDFS 报告，且 `Live datanodes` 不为 0。首次启动时 NameNode 可能需要数十秒完成初始化，可以稍后再次执行。

检查 YARN：

```powershell
docker exec namenode yarn node -list
```

通过条件：输出包含 `Total Nodes`，并列出可用 NodeManager。基础 PySpark Standalone 实验只依赖 HDFS；Spark on YARN 实验还要求 YARN 节点可用。

### 4.3 启动 Spark Master 与 Worker

`docker-compose.spark.yml` 默认连接 Hadoop HA。当前使用标准 Hadoop，因此必须先设置环境变量。

PowerShell：

```powershell
$env:HADOOP_ENVIRONMENT = 'standard'
docker compose -f docker-compose.spark.yml up -d
docker compose -f docker-compose.spark.yml ps
```

Git Bash 或 Linux Shell：

```bash
HADOOP_ENVIRONMENT=standard docker compose -f docker-compose.spark.yml up -d
docker compose -f docker-compose.spark.yml ps
```

应看到以下容器处于 `Up` 或 `running` 状态：

- `spark-master`
- `spark-worker1`
- `spark-worker2`

如果容器刚启动，可以查看初始化日志：

```powershell
docker logs spark-master --tail 100
docker logs spark-worker1 --tail 100
docker logs spark-worker2 --tail 100
```

通过条件：日志中没有持续重复的启动失败信息，Worker 日志能够表明其正在连接 `spark://spark-master:7077`。

### 4.4 检查 Spark 页面与 Worker 注册

浏览器访问：

- Spark Master：http://localhost:8080
- Spark Worker 1：http://localhost:8081
- Spark Worker 2：http://localhost:8082
- Spark History Server：http://localhost:18080

Master 页面通过条件：

- 页面可以打开。
- Master URL 为 `spark://spark-master:7077`。
- `Workers` 区域能看到两个状态为 `ALIVE` 的 Worker。

也可以直接读取 Master 的 JSON 状态：

```powershell
docker exec spark-master bash -c "curl -s http://localhost:8080/json/"
```

通过条件：返回 JSON，且 `aliveworkers` 的值为 `2`。

## 5. 检查 Scala 与 PySpark 双语言环境

### 5.1 检查 Scala Spark Shell

```powershell
docker exec spark-master spark-shell --version
```

通过条件：输出包含 Spark 3.1.1 版本信息，命令退出码为 0。

### 5.2 检查三个容器的 Python

```powershell
docker exec spark-master python3 --version
docker exec spark-worker1 python3 --version
docker exec spark-worker2 python3 --version
```

通过条件：三个容器都输出 `Python 3.8.10`。Worker 缺少 Python 时，简单的 Driver 端导入可能仍然成功，但分布式 Python 作业会失败。

### 5.3 检查 PySpark 与 Python 路径

```powershell
docker exec spark-master python3 -c "import pyspark; print(pyspark.__version__)"
docker exec spark-master bash -c 'echo PYSPARK_PYTHON=$PYSPARK_PYTHON; echo PYSPARK_DRIVER_PYTHON=$PYSPARK_DRIVER_PYTHON; echo PYTHONPATH=$PYTHONPATH'
```

通过条件：

- PySpark 版本输出 `3.1.1`。
- `PYSPARK_PYTHON` 与 `PYSPARK_DRIVER_PYTHON` 均为 `/usr/bin/python3`。
- `PYTHONPATH` 中包含 `/opt/spark/python` 和 Py4J 压缩包路径。

## 6. 测试 Scala 基础功能

先运行 Scala SparkPi，作为与 PySpark 对照的 JVM 基准作业：

```powershell
docker exec spark-master bash -c 'SPARK_EXAMPLE_JAR=$(ls /opt/spark/examples/jars/spark-examples_*.jar | head -1); spark-submit --class org.apache.spark.examples.SparkPi --master spark://spark-master:7077 "$SPARK_EXAMPLE_JAR" 20'
```

预期结果：

```text
Pi is roughly 3.14...
```

通过条件：输出包含 `Pi is roughly`，且作业最终状态为 `FINISHED`。这里不要求每次计算的小数完全相同，因为 SparkPi 使用随机采样近似计算圆周率。

## 7. 使用 PySpark Shell 完成基础实验

启动交互式 PySpark：

```powershell
docker exec -it spark-master pyspark --master spark://spark-master:7077
```

出现 `>>>` 提示符并显示 SparkContext 可用后，依次输入以下内容。不要把 `>>>` 本身输入 Shell。

### 7.1 RDD 创建、转换与行动算子

```python
numbers = sc.parallelize([1, 2, 3, 4, 5], 4)
squares = numbers.map(lambda value: value * value)
squares.collect()
squares.sum()
```

预期结果：

```text
[1, 4, 9, 16, 25]
55
```

通过条件：`collect()` 返回五个平方数，`sum()` 返回 `55`。

这组命令同时展示：

- `parallelize`：把本地集合转换为分布式 RDD。
- `map`：定义转换规则，只有遇到行动算子时才真正执行。
- `collect` 与 `sum`：触发计算并把结果返回 Driver。
- 第二个参数 `4`：把数据划分为四个分区，便于观察并行任务。

### 7.2 DataFrame 创建、过滤与聚合

```python
people = spark.createDataFrame(
    [(1, "Alice", 25), (2, "Bob", 30), (3, "Charlie", 35)],
    ["id", "name", "age"]
)
people.show()
people.filter("age >= 30").show()
people.groupBy().avg("age").show()
```

预期结果：

- 第一张表显示三条记录。
- 过滤结果只包含 Bob 与 Charlie。
- 平均年龄为 `30.0`。

通过条件：三条命令均成功，过滤结果正好为两条记录。

### 7.3 Spark SQL

```python
people.createOrReplaceTempView("people")
spark.sql("SELECT name, age FROM people WHERE age >= 30 ORDER BY age").show()
```

预期结果：

```text
+-------+---+
|   name|age|
+-------+---+
|    Bob| 30|
|Charlie| 35|
+-------+---+
```

通过条件：SQL 返回 Bob 和 Charlie，且顺序与年龄升序一致。

退出 PySpark Shell：

```python
quit()
```

## 8. 使用 spark-submit 提交 PySpark 文件

交互式 Shell 适合逐行讲解，`spark-submit` 更接近实际作业运行方式。本项目提供了 `test/pyspark-smoke.py`，其中包含 RDD、DataFrame 和 Executor Python Worker 检查。

### 8.1 把程序复制到 Master

```powershell
docker cp test/pyspark-smoke.py spark-master:/tmp/pyspark-smoke.py
```

检查文件：

```powershell
docker exec spark-master ls -l /tmp/pyspark-smoke.py
```

通过条件：容器中能看到该文件，且文件大小不为 0。

### 8.2 提交 Standalone 作业

```powershell
docker exec spark-master spark-submit --master spark://spark-master:7077 /tmp/pyspark-smoke.py
```

程序会执行以下检查：

1. 输出 Driver 使用的 Python 与 PySpark 版本。
2. 在 Executor 的 Python Worker 中计算 `1²+2²+3²+4²+5²`。
3. 收集实际执行 Python 任务的容器主机名。
4. 创建 DataFrame 并统计年龄不小于 30 的记录。

预期核心输出：

```text
[信息] Python版本：3.8.10
[信息] PySpark版本：3.1.1
[信息] Python任务实际执行节点：spark-worker1,spark-worker2
[信息] RDD平方和实际结果：55，预期结果：55
[信息] DataFrame年龄>=30记录数：2，预期结果：2
PYSPARK_SMOKE_OK square_sum=55 adult_count=2
```

实际任务可能只落到其中一个 Worker，因此执行节点数量不作为失败条件。通过条件是：

- 输出至少一个 Executor 主机名。
- RDD 平方和为 `55`。
- DataFrame 过滤结果为 `2`。
- 最终出现精确标记 `PYSPARK_SMOKE_OK square_sum=55 adult_count=2`。
- 命令退出码为 0。

如果只看到版本信息而没有最终成功标记，不能判定为通过，应继续查看输出末尾的 Python 或 Executor 异常。

## 9. 测试 PySpark 读取 HDFS

先在 HDFS 创建测试文件：

```powershell
docker exec namenode bash -c "printf 'spark hadoop\npyspark spark\nhadoop docker\n' > /tmp/pyspark-words.txt"
docker exec namenode hdfs dfs -mkdir -p /teaching/pyspark/input
docker exec namenode hdfs dfs -put -f /tmp/pyspark-words.txt /teaching/pyspark/input/words.txt
docker exec namenode hdfs dfs -cat /teaching/pyspark/input/words.txt
```

通过条件：最后一条命令能显示三行文本。

启动 PySpark Shell：

```powershell
docker exec -it spark-master pyspark --master spark://spark-master:7077
```

在 `>>>` 提示符后执行：

```python
lines = spark.read.text("hdfs:///teaching/pyspark/input/words.txt")
lines.show(truncate=False)
lines.count()
```

通过条件：DataFrame 显示三行原始文本，`count()` 返回 `3`。这证明 PySpark Driver 能读取当前 Hadoop 配置，并通过 HDFS URI 访问数据。

退出后清理本次 HDFS 测试数据：

```powershell
docker exec namenode hdfs dfs -rm -r -f /teaching/pyspark
```

## 10. 运行 Spark 自动化测试

手工实验便于理解每一步，自动化脚本用于一次性验收完整环境。

在 Git Bash 或 WSL 中执行：

```bash
bash test/test-spark.sh
```

脚本按以下顺序测试：

1. 识别标准 Hadoop 或 Hadoop HA 环境。
2. 检查 Scala、Python 和 PySpark 运行时。
3. 检查 Spark Master、Worker 和 History Server 页面。
4. 检查 Standalone 连接。
5. 准备本地与 HDFS 测试数据。
6. 提交 Scala Standalone SparkPi。
7. 提交 PySpark Standalone RDD/DataFrame 冒烟作业。
8. 提交 Scala on YARN SparkPi。
9. 执行 Scala Spark SQL 和 Spark Streaming 测试。

通过条件：脚本最后显示九项关键测试全部正常，并返回退出码 `0`。任一关键项失败时脚本返回退出码 `1`。

测试日志保存在：

```text
test/test-log/test-spark-时间戳.log
```

查看最新日志：

```powershell
Get-ChildItem test\test-log\test-spark-*.log | Sort-Object LastWriteTime -Descending | Select-Object -First 1
```

详细的测试步骤、预期输出和失败判定见 [test/test-spark.md](test/test-spark.md)。

## 11. 五节点全栈架构中的 PySpark

五节点架构把 Hadoop、Spark 和其他大数据组件组合到五个容器中：

- `master`：运行 Spark Master、HDFS NameNode 和 YARN ResourceManager 等服务。
- `worker-1`、`worker-2`、`worker-3`：运行 Spark Worker、DataNode 和 NodeManager 等服务。
- `infra`：运行部分基础设施服务。

由于 Master 和 Worker 使用同一个 `bigdata-all-in-one:latest` 镜像，容器内都包含统一的 Python 3 与 PySpark 环境，既可测试 Standalone，也可测试 PySpark on YARN。

### 11.1 构建与启动

五节点架构使用 `dockerfile.all-in-one` 构建全栈镜像。该 Dockerfile 会在一次构建中复制 Hadoop、Hive、HBase、ZooKeeper、Kafka、Flume、Spark、Flink 和兼容性 JAR，因此构建前不能只检查 Spark 与 Hadoop 两个文件。

应确认 `module` 目录至少包含以下文件：

| 对应组件或用途 | Dockerfile 要求的文件名 |
|---|---|
| Hadoop | `hadoop-3.1.3.tar.gz` |
| Hive | `apache-hive-3.1.2-bin.tar.gz` |
| HBase | `hbase-2.2.3-bin.tar.gz` |
| ZooKeeper | `apache-zookeeper-3.6.3-bin.tar.gz` |
| Kafka | `kafka_2.12-2.4.1.tgz` |
| Flume | `apache-flume-1.9.0-bin.tar.gz` |
| Spark 与 PySpark | `spark-3.1.1-bin-hadoop3.2.tgz` |
| Flink | `flink-1.14.0-bin-scala_2.12.tar` |
| MySQL JDBC 驱动 | `mysql-connector-java-5.1.49.jar` |
| Guava 兼容依赖 | `guava-27.0-jre.jar` |

在项目根目录运行以下 PowerShell 检查：

```powershell
$packageFiles = @(
    'module\hadoop-3.1.3.tar.gz'
    'module\apache-hive-3.1.2-bin.tar.gz'
    'module\hbase-2.2.3-bin.tar.gz'
    'module\apache-zookeeper-3.6.3-bin.tar.gz'
    'module\kafka_2.12-2.4.1.tgz'
    'module\apache-flume-1.9.0-bin.tar.gz'
    'module\spark-3.1.1-bin-hadoop3.2.tgz'
    'module\flink-1.14.0-bin-scala_2.12.tar'
    'module\mysql-connector-java-5.1.49.jar'
    'module\guava-27.0-jre.jar'
)

$invalidPackages = @(
    $packageFiles | Where-Object {
        -not (Test-Path -LiteralPath $_ -PathType Leaf) -or
        (Get-Item -LiteralPath $_ -ErrorAction SilentlyContinue).Length -eq 0
    }
)

if ($invalidPackages.Count -gt 0) {
    Write-Host '以下构建依赖不存在或文件大小为0：' -ForegroundColor Red
    $invalidPackages | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    throw 'module目录检查失败，请先补齐文件再构建五节点镜像。'
}

Get-Item -LiteralPath $packageFiles |
    Select-Object Name, Length, LastWriteTime

Write-Host 'module目录检查通过，可以开始构建五节点镜像。' -ForegroundColor Green
```

通过条件：

- 命令输出上述十个文件的名称、大小和修改时间。
- 没有显示“文件不存在或文件大小为0”。
- 最后一行显示 `module目录检查通过，可以开始构建五节点镜像。`。

如果缺少 Spark 或 Hadoop 包，分别按照 2.3、2.4 节下载。其他文件也必须使用表格中的精确名称；Docker 构建上下文中的文件名与 `COPY` 指令不一致时，构建会立即失败。

如果本次课程只讲授 PySpark，不需要同时运行 Hive、HBase、Kafka、Flume 和 Flink，建议使用第 4 节的独立组件架构；五节点架构适合全栈综合实验，因此需要准备全部构建依赖。

确认检查通过后再执行构建与启动：

```powershell
docker build -f dockerfile.base -t bigdata-base:latest .
docker build -f dockerfile.all-in-one -t bigdata-all-in-one:latest .
docker compose -f docker-compose.5-node-cluster.yml up -d
docker compose -f docker-compose.5-node-cluster.yml ps
```

五节点会启动较多进程。应等待各节点完成初始化，再进行测试。可查看 Supervisor 状态：

```powershell
docker exec master supervisorctl status
docker exec worker-1 supervisorctl status
docker exec worker-2 supervisorctl status
docker exec worker-3 supervisorctl status
docker exec infra supervisorctl status
```

通过条件：Spark Master/Worker、HDFS、YARN 等本次实验所需进程处于 `RUNNING`，而不是反复进入 `BACKOFF` 或 `FATAL`。

Spark Master 页面：http://localhost:28080

页面通过条件：能看到三个已注册的 Spark Worker。

### 11.2 手工提交 PySpark Standalone 作业

```powershell
docker cp test/pyspark-smoke.py master:/tmp/pyspark-smoke.py
docker exec master spark-submit --master spark://master:7077 /tmp/pyspark-smoke.py
```

通过条件与独立架构相同：最终必须输出 `PYSPARK_SMOKE_OK square_sum=55 adult_count=2`。

### 11.3 手工提交 PySpark on YARN 作业

```powershell
docker exec master spark-submit --master yarn --deploy-mode client /tmp/pyspark-smoke.py
```

通过条件：

- YARN 接受并完成应用。
- 输出至少一个 Python 任务执行节点。
- 最终输出 `PYSPARK_SMOKE_OK square_sum=55 adult_count=2`。
- 命令退出码为 0。

这里需要同时检查 NodeManager 所在容器的 Python。YARN 会在 Worker 节点启动 Executor；如果只在 Master 安装 Python，Driver 可以启动，但 Executor 会因找不到 `/usr/bin/python3` 而失败。

### 11.4 运行五节点综合测试

在 Git Bash 或 WSL 中执行：

```bash
bash test/cluster-test.sh
```

与 PySpark 直接相关的通过条件包括：

- Master 与三个 Worker 均能运行 Python 3。
- Master 能导入项目版本的 PySpark。
- Scala Spark Standalone 作业通过。
- PySpark Standalone RDD/DataFrame 作业通过。
- Scala Spark on YARN 作业通过。
- PySpark on YARN RDD/DataFrame 作业通过。

完整流程和每项判定见 [test/cluster-test.md](test/cluster-test.md)。

## 12. 常见故障与定位方法

| 现象 | 说明 | 检查命令或处理方法 |
|---|---|---|
| 构建 Spark 镜像时提示找不到 `spark-3.1.1-bin-hadoop3.2.tgz` | Spark 离线包尚未下载、目录不正确或下载了其他发行包 | 按 2.3 节下载完整预编译包，并确认路径精确为 `module/spark-3.1.1-bin-hadoop3.2.tgz` |
| 构建 Hadoop 镜像时提示找不到 `hadoop-3.1.3.tar.gz` | Hadoop 离线包尚未下载、目录不正确或文件名不匹配 | 按 2.4 节下载二进制发行包，并确认路径精确为 `module/hadoop-3.1.3.tar.gz` |
| `ModuleNotFoundError: No module named 'pyspark'` | Python 没有找到 Spark 自带模块 | 执行 `docker exec spark-master bash -c 'echo $PYTHONPATH'`，确认含 `/opt/spark/python` 和 Py4J 路径 |
| `Cannot run program /usr/bin/python3` | Executor 容器缺少 Python 或解释器路径不一致 | 分别在 Master、每个 Worker 中执行 `python3 --version` |
| `Failed to connect to master` | Master 未启动、地址错误或网络不通 | 检查 `docker compose ... ps`、`docker logs spark-master` 和 `spark://spark-master:7077` |
| Master 页面没有 Worker | Worker 尚未注册或反复退出 | 查看两个 Worker 日志，检查三个容器是否都连接 `bigdata-net` |
| 作业一直等待资源 | Worker 没有可用 Core/Memory | 查看 Master 页面中的 Worker 资源和正在运行的 Application |
| HDFS 路径不存在 | Hadoop 未启动或 Spark 读取了错误配置 | 检查 `HADOOP_ENVIRONMENT=standard`，再执行 `docker exec namenode hdfs dfs -ls /` |
| History Server 报 event log 错误 | HDFS 日志目录未初始化或 HDFS 尚未就绪 | 先确认 HDFS 可用，再查看 `docker logs spark-master` |
| Standalone 成功但 YARN 失败 | YARN、HDFS 或 NodeManager 端运行时异常 | 执行 `yarn node -list`，并查看 ResourceManager/NodeManager 日志 |
| 只出现 Python 版本，没有成功标记 | Driver 启动成功，但计算过程或 Executor 失败 | 查看 `spark-submit` 输出末尾及 Worker 日志，不能只根据版本信息判定通过 |

查看 Spark 应用相关日志：

```powershell
docker logs spark-master --tail 200
docker logs spark-worker1 --tail 200
docker logs spark-worker2 --tail 200
```

五节点环境改用：

```powershell
docker logs master --tail 200
docker logs worker-1 --tail 200
docker logs worker-2 --tail 200
docker logs worker-3 --tail 200
```

## 13. 停止并清理实验环境

停止独立 Spark 与标准 Hadoop：

```powershell
docker compose -f docker-compose.spark.yml down
docker compose -f docker-compose.hadoop.yml down
Remove-Item Env:HADOOP_ENVIRONMENT -ErrorAction SilentlyContinue
```

停止五节点集群：

```powershell
docker compose -f docker-compose.5-node-cluster.yml down
```

以上命令停止并删除本次 Compose 创建的容器和普通网络连接，但不会主动删除项目中的持久化数据目录。不要随意添加 `-v`，因为它可能删除卷中的实验数据。

## 14. 最终验收清单

| 检查项 | 执行方式 | 通过结果 |
|---|---|---|
| 镜像运行时 | 临时运行 `bigdata-spark:latest` | Python 3.8.10、PySpark 3.1.1、Spark 3.1.1 |
| 容器状态 | `docker compose ... ps` | Master 和两个 Worker 均运行 |
| Worker 注册 | Master Web UI 或 `/json/` | 独立架构 2 个 Worker；五节点架构 3 个 Worker |
| Scala 基础功能 | Scala SparkPi | 输出 `Pi is roughly` |
| PySpark RDD | `pyspark-smoke.py` | 平方和为 55 |
| PySpark DataFrame | `pyspark-smoke.py` | 年龄不小于 30 的记录数为 2 |
| Executor Python | 冒烟程序输出执行节点 | 至少得到一个 Worker 主机名 |
| 自动化测试 | `bash test/test-spark.sh` | 九项关键条件全部通过，退出码为 0 |
| 五节点综合测试 | `bash test/cluster-test.sh` | Standalone 与 YARN 的 Scala/PySpark 项均通过 |

学生应以“命令退出码为 0、计算结果正确、最终成功标记出现”三者共同作为作业通过依据，不能只根据容器处于运行状态或 Web 页面能够打开来判断 PySpark 已经可用。
