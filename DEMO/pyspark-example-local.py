"""PySpark 教学示例：Driver 在 Windows，Executor 在 Docker 容器中。

运行方式：
    conda activate pyspark_proj
    python DEMO/pyspark-example-local.py

运行结构：
    Windows Python（Driver）
        -> Docker 映射端口 127.0.0.1:7077（Master）
        -> spark-worker1、spark-worker2（Executor）
"""

import os
import sys
from pathlib import Path

import pyspark
from pyspark.sql import SparkSession
from pyspark.sql.functions import col, sum as spark_sum


# 当前脚本所在目录。后面用它定位教学专用的 Log4j 配置文件。转换成绝对
# file URI 后，即使从其他工作目录启动脚本，Java 也能找到该配置文件。
SCRIPT_DIR = Path(__file__).resolve().parent
LOG4J_CONFIG = SCRIPT_DIR / "log4j-local.properties"


# -----------------------------------------------------------------------------
# 一、配置 Python 与 Spark 运行环境
# -----------------------------------------------------------------------------
# os.environ 用来设置当前 Python 进程的环境变量。
# SparkSession 尚未创建，所以稍后启动的 Java 网关和 Spark 子进程都能读取
# 这些设置。环境变量必须在 getOrCreate() 之前完成配置。

# SPARK_HOME 表示本地 Spark 的安装目录。
# pip/conda 安装 pyspark 后，Spark 的 bin、jars 等目录就在 pyspark 包目录中。
# 因为下面的 PYSPARK_PYTHON 是 Linux 路径，Windows 启动脚本无法用它寻找
# SPARK_HOME，所以这里先明确告诉启动脚本本地 Spark 在哪里。
os.environ["SPARK_HOME"] = str(Path(pyspark.__file__).resolve().parent)

# PYSPARK_DRIVER_PYTHON 指定 Driver 使用的 Python。
# sys.executable 是当前正在运行本脚本的解释器，例如：
# C:\Users\Lenovo\.conda\envs\pyspark_proj\python.exe
# 这样可以确保 Driver 使用已激活的 conda 环境，而不是系统中的其他 Python。
os.environ["PYSPARK_DRIVER_PYTHON"] = sys.executable

# PYSPARK_PYTHON 指定 Executor 执行 Python 任务时使用的解释器。
# Executor 位于 Linux 容器中，不能使用上面的 Windows 路径；本集群的容器
# 已安装 /usr/bin/python3，因此需要填写容器内路径。
os.environ["PYSPARK_PYTHON"] = "/usr/bin/python3"


# -----------------------------------------------------------------------------
# 二、创建 SparkSession
# -----------------------------------------------------------------------------
# SparkSession 是 DataFrame / SQL API 的统一入口。
# builder 先逐项收集配置，getOrCreate() 才真正启动 Driver 并连接集群。
spark = (
    SparkSession.builder

    # 应用名称会显示在 Spark Master Web UI（http://localhost:8080）中，
    # 便于从多个任务中识别当前示例。
    .appName("PySparkLocalExample")

    # Windows 通过 docker-compose 暴露的 7077 端口连接 Spark Master。
    # 这里使用 127.0.0.1，不直接依赖可能在容器重启后改变的 172.18.x.x IP。
    .master("spark://127.0.0.1:7077")

    # Driver 的网络服务监听所有本地网卡。Executor 位于 Docker 网络中，
    # 如果只监听 127.0.0.1，容器无法回连 Driver。
    .config("spark.driver.bindAddress", "0.0.0.0")

    # bindAddress 决定“监听在哪里”，driver.host 决定“告诉 Executor 用哪个
    # 地址来连接”。Docker Desktop 会把 host.docker.internal 解析到 Windows。
    .config("spark.driver.host", "host.docker.internal")

    # Hadoop 在 Windows 初始化时会查找 HADOOP_HOME/bin/winutils.exe。本例的
    # Driver 只连接 Docker 集群，不在 Windows 上调用 Hadoop 文件工具，
    # 因此使用独立的 Log4j 配置定向隐藏 org.apache.hadoop.util.Shell 警告。
    #
    # 注意：这只是隐藏与当前场景无关的日志，并没有安装 winutils.exe。
    # 若以后要在 Windows 本地进行 Hadoop 文件操作，应安装匹配版本的
    # winutils.exe 并设置 HADOOP_HOME，而不能依赖日志过滤。
    #
    # spark.driver.extraJavaOptions 会在 Driver JVM 启动时添加 Java 参数；
    # -Dlog4j.configuration 告诉 Log4j 从指定 file URI 读取日志规则。
    .config(
        "spark.driver.extraJavaOptions",
        "-Dlog4j.configuration={}".format(LOG4J_CONFIG.as_uri()),
    )

    # 指定 Spark 启动 Python Worker 时使用的容器内解释器。
    # 它与前面的 PYSPARK_PYTHON 含义相近；在 Spark 配置中再明确设置一次，
    # 可以让该要求随应用配置传递给集群。
    .config("spark.pyspark.python", "/usr/bin/python3")

    # 显式把 PYSPARK_PYTHON 环境变量传给每个 Executor。
    # 这样 Executor 启动 Python Worker 时不会误用不存在或版本不同的解释器。
    .config("spark.executorEnv.PYSPARK_PYTHON", "/usr/bin/python3")

    # 限制整个示例最多使用 2 个 CPU 核心，避免教学代码占满集群资源。
    .config("spark.cores.max", "2")

    # groupBy 会触发 shuffle。Spark 默认通常创建 200 个 shuffle 分区，
    # 对本例的 5 行数据太多；设为 2 可减少无意义的小任务并加快演示。
    .config("spark.sql.shuffle.partitions", "2")

    # 本例只演示计算，不写 Spark History Server 的事件日志，也不依赖 HDFS。
    .config("spark.eventLog.enabled", "false")

    # 根据以上配置创建 SparkSession；若已有兼容会话，则复用已有会话。
    .getOrCreate()
)

# WARN 会隐藏大量 INFO 级内部日志，使学生更容易看到程序的主要输出。
spark.sparkContext.setLogLevel("WARN")


# -----------------------------------------------------------------------------
# 三、创建 DataFrame
# -----------------------------------------------------------------------------
# 每个元组表示一条订单，第二个列表给出各列名称。
orders = spark.createDataFrame(
    [
        (1, "book", 120, "paid"),
        (2, "book", 80, "paid"),
        (3, "food", 50, "paid"),
        (4, "food", 30, "cancelled"),
        (5, "food", 70, "paid"),
    ],
    ["order_id", "category", "amount", "status"],
)


# -----------------------------------------------------------------------------
# 四、使用 DataFrame API 完成转换
# -----------------------------------------------------------------------------
# DataFrame 的转换是惰性执行的：下面只建立计算计划，直到 result.show()
# 这个 action 被调用时，Spark 才把任务发送给 Executor 实际计算。
result = (
    orders
    # 只保留已经支付的订单，取消的 food=30 不参与统计。
    .filter(col("status") == "paid")
    # 按商品类别分组：book 一组、food 一组。
    .groupBy("category")
    # 分别累加每组 amount，并把结果列命名为 total_amount。
    .agg(spark_sum("amount").alias("total_amount"))
    # 排序不是聚合必需步骤，只是让每次展示顺序保持一致。
    .orderBy("category")
)

print("Master:", spark.sparkContext.master)
result.show()

# 主动释放 Driver 与 Executor 使用的资源。普通脚本结束前应养成关闭会话的习惯。
spark.stop()
