# Spark 计算引擎测试说明

## 脚本与依赖

- 脚本：`test/test-spark.sh`
- 容器：`spark-master`、`spark-worker1/2`
- 依赖：Hadoop 标准或 HA 集群

```bash
bash test/test-spark.sh
```

## 测试范围

按“配置与运行时 → Connector/J → SSH原生启停 → 集群页面 → Standalone → HDFS → YARN → SQL → Streaming”的流程，验证Spark容器既能运行Scala/PySpark作业，也能使用Spark自带脚本管理整个Standalone集群。

## 详细测试流程

### 1. 识别 Hadoop 环境

若发现 `namenode1` 则选择 HA，否则使用标准模式的 `namenode`。日志明确记录本次 Spark 连接的是哪套 Hadoop 配置。

### 2. 检查配置与Scala、Python/PySpark运行时

脚本在`master`中执行`spark-shell --version`，要求Scala Shell正常返回；随后在`spark-master`、`spark-worker1`、`spark-worker2`中分别执行：

```bash
/usr/bin/python3 --version
```

三个容器都必须返回`Python 3`。最后在Master中直接导入PySpark，要求`pyspark.__version__`与项目的Spark版本一致：

```bash
/usr/bin/python3 -c "import pyspark; print(pyspark.__version__)"
```

脚本还会在Master和两个Worker中检查：

```bash
jar tf /opt/spark/jars/mysql-connector-java-5.1.49.jar \
  | grep '^com/mysql/jdbc/Driver.class$'
```

通过条件：三个容器都存在非空JAR，并且其中包含Connector/J 5.1.49对应的`com.mysql.jdbc.Driver`。`com.mysql.cj.jdbc.Driver`不属于该版本。独立Spark测试不强制依赖MySQL容器，因此这里只验证镜像交付；五节点综合测试会进一步创建测试表并执行真实JDBC读取。

在运行时检查之前，脚本还会分别检查三个 Spark 容器中的 Worker 主机列表：

```bash
awk '!/^[[:space:]]*(#|$)/ {print $1}' /opt/spark/conf/workers
test ! -e /opt/spark/conf/slaves
```

通过条件：`workers` 去除注释和空行后只能包含 `spark-worker1`、`spark-worker2`，旧文件 `slaves` 不存在，并且 `/opt/spark/hadoop-conf/core-site.xml` 存在。Hadoop客户端配置单独放在 `/opt/spark/hadoop-conf`，避免 Hadoop 的 `workers`（DataNode列表）覆盖 Spark 的同名文件。容器首次启动时Worker会主动注册；之后也可以由Master读取该文件，通过SSH批量启动或停止Worker。

### 3. 验证基于SSH的原生集群启停

Spark的`start-all.sh`和`stop-all.sh`并不直接调用Docker API。Master读取`/opt/spark/conf/workers`，然后通过SSH分别进入两个Worker容器执行`start-worker.sh`或`stop-worker.sh`。脚本先验证两条免密连接：

```bash
docker exec spark-master ssh -o BatchMode=yes spark-worker1 hostname
docker exec spark-master ssh -o BatchMode=yes spark-worker2 hostname
```

通过条件：命令不出现密码提示，退出码为`0`，并分别输出`spark-worker1`、`spark-worker2`。之后测试脚本真实执行：

```bash
docker exec spark-master bash -lc \
  'cd /opt/spark && ./sbin/stop-all.sh --wait'

docker exec spark-master bash -lc \
  'cd /opt/spark && ./sbin/start-all.sh'
```

为避免把“Worker本来尚未启动”误判成“停止成功”，脚本会先执行一次幂等的`start-all.sh`建立前置状态，并要求Master容器中恰好一个`Master`进程、每个Worker容器中恰好一个`Worker`进程且`aliveworkers`为`2`，之后才进入正式启停测试。精确检查进程数量还能发现入口脚本与SSH使用不同PID标识而导致的重复启动。`stop-all.sh --wait`通过的条件是命令在60秒内自行结束，并且Master中的`Master`进程和两个Worker容器中的`Worker`进程全部消失；第二次`start-all.sh`通过的条件是三个守护进程各恢复一个，并且Master JSON接口的`aliveworkers`精确为`2`。容器使用不包含Spark类名的保活进程，避免原生脚本的`ps | grep`把日志跟随命令误判成Worker。History Server不属于`start-all.sh/stop-all.sh`的管理范围，因此测试期间继续运行。

这里的SSH仅用于Docker内部`bigdata-net`网络，没有把容器22端口映射到宿主机。`BatchMode=yes`用于保证免密认证失败时立即报错，而不是等待输入密码。

### 4. 检查 Spark 页面

访问 Master 8080、History Server 18080、Worker 8081/8082。Master 必须可访问，两个 Worker 页面至少一个正常；History Server 状态单独记录。

### 5. 连接 Standalone

在 `spark-master` 中启动短生命周期 `spark-shell`，连接 `spark://spark-master:7077`，确认 SparkContext 创建成功。

### 6. 准备数据与 HDFS

生成包含 Alice、Bob、Charlie 的 CSV。如果 HDFS 可用，则上传至 `/test/spark/input/` 并记录 HDFS 路径；HDFS 不可用时记录降级到容器本地文件。

### 7. 运行Scala SparkPi

- 使用 `--master spark://spark-master:7077` 验证 Standalone。
- 使用 `--master yarn --deploy-mode client` 验证 Spark on YARN。

两次输出都必须包含 `Pi is roughly`，日志保存计算结果或失败堆栈。

### 8. 运行Python PySpark冒烟测试

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

### 9. 验证Scala Spark SQL

脚本生成 Scala 文件，构造三行 DataFrame，执行 `show`、`count` 和平均年龄聚合。输出必须包含测试标记和查询结果。

### 10. 验证Scala Spark Streaming

生成第二个 Scala 文件，创建一秒批次的 `StreamingContext`，随后正常停止。日志必须出现完成标记。

### 11. 清理

删除 HDFS `/test/spark` 和宿主机临时 Scala/CSV 文件。

## 结果判定

| 环节 | 通过条件 |
|---|---|
| Scala环境 | `spark-shell --version`成功，Scala SparkPi、Spark SQL和Spark Streaming均通过 |
| Python环境 | Master和两个Worker均能运行Python 3，Master可直接导入同版本PySpark |
| Worker主机列表 | 三个容器的`workers`均为`spark-worker1`、`spark-worker2`，不存在旧`slaves`，且Hadoop配置位于独立目录 |
| SSH原生启停 | Master可免密登录两个Worker；`stop-all.sh --wait`完整停止集群；`start-all.sh`恢复Master和两个已注册Worker |
| MySQL Connector/J | Master和两个Worker的Spark默认JAR目录均包含5.1.49驱动及`com.mysql.jdbc.Driver`类 |
| 集群 | Master可访问，至少一个Worker页面正常 |
| Scala Standalone | SparkPi输出`Pi is roughly` |
| PySpark Standalone | RDD平方和为55、DataFrame过滤结果为2，并输出精确成功标记 |
| Scala on YARN | SparkPi经YARN完成并输出`Pi is roughly` |
| Scala SQL | DataFrame查询标记和结果出现 |
| Scala Streaming | StreamingContext创建和停止完成 |

脚本最终统计十二个关键条件：Scala运行时、Python/PySpark运行时、Worker主机列表、SSH原生启停、MySQL Connector/J、Master Web UI、至少一个Worker Web UI、Scala Standalone SparkPi、PySpark Standalone冒烟作业、Scala on YARN SparkPi、Scala Spark SQL和Scala Spark Streaming。十二项全部满足时返回退出码`0`；任一项失败返回退出码`1`。History Server和HDFS可用性会记录在日志中，但当前不计入最终`failure_count`。

## 关键命令、预期结果与通过条件

| 脚本执行的命令或操作 | 预期结果 | 该项通过条件 |
|---|---|---|
| `curl http://localhost:8080` | HTTP 200 | Master Web UI 状态码精确为 200 |
| `curl http://localhost:8081/8082` | 至少一个 HTTP 200 | 两个 Worker 页面中至少一个正常 |
| `curl http://localhost:18080` | HTTP 200 或异常状态码 | 仅记录 History Server 状态，不决定最终退出码 |
| 三个容器执行`python3 --version` | 均输出`Python 3` | Master和两个Worker的Python解释器都存在 |
| 三个容器读取`/opt/spark/conf/workers`并检查`slaves` | 两个正确hostname且无旧文件 | 配置只包含`spark-worker1`、`spark-worker2`，旧`slaves`不存在 |
| 三个容器执行`jar tf mysql-connector-java-5.1.49.jar` | 输出`com/mysql/jdbc/Driver.class` | Master和两个Worker均已由镜像内置正确版本驱动 |
| Master分别执行`ssh -o BatchMode=yes <worker> hostname` | 无密码提示并返回对应hostname | 两个Worker免密SSH均通过 |
| 先执行`start-all.sh`并检查三个进程 | Master和两个Worker均运行，`aliveworkers`为2 | 已建立“确实有服务可停止”的测试前置状态 |
| Master执行`stop-all.sh --wait` | Master和两个Worker守护进程消失 | SSH远程停止完整生效且命令在60秒内结束 |
| Master执行`start-all.sh` | Master、两个Worker进程恢复，`aliveworkers`为2 | Spark原生SSH批量启动完整通过 |
| `python3 -c "import pyspark; ..."` | 输出PySpark版本与Spark版本一致 | Python模块路径和Py4J配置正确 |
| `spark-shell --master spark://spark-master:7077` | 输出包含 `Spark context available` | Standalone 连接检查通过 |
| `spark-submit --master spark://spark-master:7077 ... SparkPi` | 输出包含 `Pi is roughly` | Standalone SparkPi 通过 |
| `spark-submit --master spark://spark-master:7077 pyspark-smoke.py` | 输出精确成功标记 | Executor Python Worker、RDD和DataFrame均正常 |
| `yarn node -list` | 输出包含 `Total Nodes` | YARN 状态检查通过；失败会写日志 |
| `spark-submit --master yarn --deploy-mode client ... SparkPi` | 输出包含 `Pi is roughly` | Spark on YARN 通过 |
| 执行 `/tmp/spark-sql-test.scala` | 输出包含 `Spark SQL Test Result` | SQL 测试标记出现；日志同时显示 DataFrame、记录数和平均年龄 |
| 执行 `/tmp/spark-streaming-test.scala` | 输出包含 `Spark Streaming test completed` | StreamingContext 创建和停止完成 |

## 日志与失败定位

日志保存到`test/test-log/test-spark-时间戳.log`。脚本捕获SSH连接、原生启停脚本、守护进程状态、Scala Shell、Python版本、PySpark导入、Spark Submit和计算结果。SSH失败时会指出具体Worker和实际输出；原生启停失败时会列出三个容器中的`jps`结果。Python失败时会指出具体容器、实际Python/PySpark版本或PySpark作业输出末尾；任一关键项失败时追加三个Spark容器日志并返回非零状态。

排查时注意区分 Master/Worker 守护进程内存、Driver 内存和 Executor 内存，并检查 Spark 使用的 `HADOOP_CONF_DIR` 是否与当前 Hadoop 架构一致。
