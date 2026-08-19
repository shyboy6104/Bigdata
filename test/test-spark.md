# Spark 计算引擎测试说明

## 脚本与依赖

- 脚本：`test/test-spark.sh`
- 容器：`spark-master`、`spark-worker1/2`
- 依赖：Hadoop 标准或 HA 集群

```bash
bash test/test-spark.sh
```

## 测试范围

按“集群页面 → Standalone → HDFS → YARN → SQL → Streaming”的流程验证 Spark 两种运行模式和常用功能。

## 详细测试流程

### 1. 识别 Hadoop 环境

若发现 `namenode1` 则选择 HA，否则使用标准模式的 `namenode`。日志明确记录本次 Spark 连接的是哪套 Hadoop 配置。

### 2. 检查 Spark 页面

访问 Master 8080、History Server 18080、Worker 8081/8082。Master 必须可访问，两个 Worker 页面至少一个正常；History Server 状态单独记录。

### 3. 连接 Standalone

在 `spark-master` 中启动短生命周期 `spark-shell`，连接 `spark://spark-master:7077`，确认 SparkContext 创建成功。

### 4. 准备数据与 HDFS

生成包含 Alice、Bob、Charlie 的 CSV。如果 HDFS 可用，则上传至 `/test/spark/input/` 并记录 HDFS 路径；HDFS 不可用时记录降级到容器本地文件。

### 5. 运行两次 SparkPi

- 使用 `--master spark://spark-master:7077` 验证 Standalone。
- 使用 `--master yarn --deploy-mode client` 验证 Spark on YARN。

两次输出都必须包含 `Pi is roughly`，日志保存计算结果或失败堆栈。

### 6. 验证 Spark SQL

脚本生成 Scala 文件，构造三行 DataFrame，执行 `show`、`count` 和平均年龄聚合。输出必须包含测试标记和查询结果。

### 7. 验证 Spark Streaming

生成第二个 Scala 文件，创建一秒批次的 `StreamingContext`，随后正常停止。日志必须出现完成标记。

### 8. 清理

删除 HDFS `/test/spark` 和宿主机临时 Scala/CSV 文件。

## 结果判定

| 环节 | 通过条件 |
|---|---|
| 集群 | Master 可访问，至少一个 Worker 页面正常 |
| Standalone | SparkPi 输出 Pi 结果 |
| YARN | SparkPi 经 YARN 完成并输出 Pi 结果 |
| SQL | DataFrame 查询标记和结果出现 |
| Streaming | StreamingContext 创建和停止完成 |

脚本最终统计六个关键条件：Master Web UI、至少一个 Worker Web UI、Standalone SparkPi、YARN SparkPi、Spark SQL 和 Spark Streaming。六项全部满足时返回退出码 `0`；任一项失败返回退出码 `1`。History Server 和 HDFS 可用性会记录在日志中，但当前不计入最终 `failure_count`。

## 关键命令、预期结果与通过条件

| 脚本执行的命令或操作 | 预期结果 | 该项通过条件 |
|---|---|---|
| `curl http://localhost:8080` | HTTP 200 | Master Web UI 状态码精确为 200 |
| `curl http://localhost:8081/8082` | 至少一个 HTTP 200 | 两个 Worker 页面中至少一个正常 |
| `curl http://localhost:18080` | HTTP 200 或异常状态码 | 仅记录 History Server 状态，不决定最终退出码 |
| `spark-shell --master spark://spark-master:7077` | 输出包含 `Spark context available` | Standalone 连接检查通过 |
| `spark-submit --master spark://spark-master:7077 ... SparkPi` | 输出包含 `Pi is roughly` | Standalone SparkPi 通过 |
| `yarn node -list` | 输出包含 `Total Nodes` | YARN 状态检查通过；失败会写日志 |
| `spark-submit --master yarn --deploy-mode client ... SparkPi` | 输出包含 `Pi is roughly` | Spark on YARN 通过 |
| 执行 `/tmp/spark-sql-test.scala` | 输出包含 `Spark SQL Test Result` | SQL 测试标记出现；日志同时显示 DataFrame、记录数和平均年龄 |
| 执行 `/tmp/spark-streaming-test.scala` | 输出包含 `Spark Streaming test completed` | StreamingContext 创建和停止完成 |

## 日志与失败定位

日志保存到 `test/test-log/test-spark-时间戳.log`。脚本现在捕获所有终端、Spark Submit 和 Shell 输出。Standalone、YARN、SQL、Streaming 或关键 Web/Worker 状态失败时，脚本返回非零状态并追加三个 Spark 容器日志。

排查时注意区分 Master/Worker 守护进程内存、Driver 内存和 Executor 内存，并检查 Spark 使用的 `HADOOP_CONF_DIR` 是否与当前 Hadoop 架构一致。
