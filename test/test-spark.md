# Spark 计算引擎测试说明

## 脚本与依赖

- 脚本：`test/test-spark.sh`
- 容器：`spark-master`、`spark-worker1/2`
- 依赖：Hadoop 标准或 HA 集群

```bash
bash test/test-spark.sh
```

## 测试范围

按“Scala/Python运行时 → 集群页面 → Standalone → HDFS → YARN → SQL → Streaming”的流程，验证Spark容器既能运行Scala作业，也能运行Python/PySpark作业。

## 详细测试流程

### 1. 识别 Hadoop 环境

若发现 `namenode1` 则选择 HA，否则使用标准模式的 `namenode`。日志明确记录本次 Spark 连接的是哪套 Hadoop 配置。

### 2. 检查Scala与Python/PySpark运行时

脚本在`master`中执行`spark-shell --version`，要求Scala Shell正常返回；随后在`spark-master`、`spark-worker1`、`spark-worker2`中分别执行：

```bash
/usr/bin/python3 --version
```

三个容器都必须返回`Python 3`。最后在Master中直接导入PySpark，要求`pyspark.__version__`与项目的Spark版本一致：

```bash
/usr/bin/python3 -c "import pyspark; print(pyspark.__version__)"
```

### 3. 检查 Spark 页面

访问 Master 8080、History Server 18080、Worker 8081/8082。Master 必须可访问，两个 Worker 页面至少一个正常；History Server 状态单独记录。

### 4. 连接 Standalone

在 `spark-master` 中启动短生命周期 `spark-shell`，连接 `spark://spark-master:7077`，确认 SparkContext 创建成功。

### 5. 准备数据与 HDFS

生成包含 Alice、Bob、Charlie 的 CSV。如果 HDFS 可用，则上传至 `/test/spark/input/` 并记录 HDFS 路径；HDFS 不可用时记录降级到容器本地文件。

### 6. 运行Scala SparkPi

- 使用 `--master spark://spark-master:7077` 验证 Standalone。
- 使用 `--master yarn --deploy-mode client` 验证 Spark on YARN。

两次输出都必须包含 `Pi is roughly`，日志保存计算结果或失败堆栈。

### 7. 运行Python PySpark冒烟测试

脚本把`test/pyspark-smoke.py`复制到Master，并使用Standalone模式提交：

```bash
spark-submit \
  --master spark://spark-master:7077 \
  /tmp/pyspark-smoke.py
```

该作业通过Python RDD计算`1²+2²+3²+4²+5²`，再通过DataFrame统计年龄不小于30的记录。RDD中的Python函数会在Spark Worker的Python Worker进程中执行，因此可以同时验证Driver和Executor的Python环境。

通过时输出必须包含：

```text
PYSPARK_SMOKE_OK square_sum=55 adult_count=2
```

### 8. 验证Scala Spark SQL

脚本生成 Scala 文件，构造三行 DataFrame，执行 `show`、`count` 和平均年龄聚合。输出必须包含测试标记和查询结果。

### 9. 验证Scala Spark Streaming

生成第二个 Scala 文件，创建一秒批次的 `StreamingContext`，随后正常停止。日志必须出现完成标记。

### 10. 清理

删除 HDFS `/test/spark` 和宿主机临时 Scala/CSV 文件。

## 结果判定

| 环节 | 通过条件 |
|---|---|
| Scala环境 | `spark-shell --version`成功，Scala SparkPi、Spark SQL和Spark Streaming均通过 |
| Python环境 | Master和两个Worker均能运行Python 3，Master可直接导入同版本PySpark |
| 集群 | Master可访问，至少一个Worker页面正常 |
| Scala Standalone | SparkPi输出`Pi is roughly` |
| PySpark Standalone | RDD平方和为55、DataFrame过滤结果为2，并输出精确成功标记 |
| Scala on YARN | SparkPi经YARN完成并输出`Pi is roughly` |
| Scala SQL | DataFrame查询标记和结果出现 |
| Scala Streaming | StreamingContext创建和停止完成 |

脚本最终统计九个关键条件：Scala运行时、Python/PySpark运行时、Master Web UI、至少一个Worker Web UI、Scala Standalone SparkPi、PySpark Standalone冒烟作业、Scala on YARN SparkPi、Scala Spark SQL和Scala Spark Streaming。九项全部满足时返回退出码`0`；任一项失败返回退出码`1`。History Server和HDFS可用性会记录在日志中，但当前不计入最终`failure_count`。

## 关键命令、预期结果与通过条件

| 脚本执行的命令或操作 | 预期结果 | 该项通过条件 |
|---|---|---|
| `curl http://localhost:8080` | HTTP 200 | Master Web UI 状态码精确为 200 |
| `curl http://localhost:8081/8082` | 至少一个 HTTP 200 | 两个 Worker 页面中至少一个正常 |
| `curl http://localhost:18080` | HTTP 200 或异常状态码 | 仅记录 History Server 状态，不决定最终退出码 |
| 三个容器执行`python3 --version` | 均输出`Python 3` | Master和两个Worker的Python解释器都存在 |
| `python3 -c "import pyspark; ..."` | 输出PySpark版本与Spark版本一致 | Python模块路径和Py4J配置正确 |
| `spark-shell --master spark://spark-master:7077` | 输出包含 `Spark context available` | Standalone 连接检查通过 |
| `spark-submit --master spark://spark-master:7077 ... SparkPi` | 输出包含 `Pi is roughly` | Standalone SparkPi 通过 |
| `spark-submit --master spark://spark-master:7077 pyspark-smoke.py` | 输出精确成功标记 | Executor Python Worker、RDD和DataFrame均正常 |
| `yarn node -list` | 输出包含 `Total Nodes` | YARN 状态检查通过；失败会写日志 |
| `spark-submit --master yarn --deploy-mode client ... SparkPi` | 输出包含 `Pi is roughly` | Spark on YARN 通过 |
| 执行 `/tmp/spark-sql-test.scala` | 输出包含 `Spark SQL Test Result` | SQL 测试标记出现；日志同时显示 DataFrame、记录数和平均年龄 |
| 执行 `/tmp/spark-streaming-test.scala` | 输出包含 `Spark Streaming test completed` | StreamingContext 创建和停止完成 |

## 日志与失败定位

日志保存到`test/test-log/test-spark-时间戳.log`。脚本捕获Scala Shell、Python版本、PySpark导入、Spark Submit和计算结果。Python失败时会指出具体容器、实际Python/PySpark版本或PySpark作业输出末尾；任一关键项失败时追加三个Spark容器日志并返回非零状态。

排查时注意区分 Master/Worker 守护进程内存、Driver 内存和 Executor 内存，并检查 Spark 使用的 `HADOOP_CONF_DIR` 是否与当前 Hadoop 架构一致。
