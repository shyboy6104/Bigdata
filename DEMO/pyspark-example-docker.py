"""PySpark 教学示例：Driver 和 Spark 集群都运行在 Docker 中。

运行方式：
    docker cp DEMO/pyspark-example-docker.py spark-master:/tmp/pyspark-example.py
    docker exec spark-master python3 /tmp/pyspark-example.py

运行结构：
    spark-master 容器（Python Driver + Spark Master）
        -> spark-worker1、spark-worker2（Executor）
"""

import os

from pyspark.sql import SparkSession
from pyspark.sql.functions import col, sum as spark_sum


# -----------------------------------------------------------------------------
# 一、配置容器内的 Python 与 Spark 运行环境
# -----------------------------------------------------------------------------
# docker-compose 和镜像已经设置了这些变量。这里再次明确写出，是为了让教学
# 脚本独立、易读，也让学生能直观看到 Spark 如何找到安装目录和解释器。

# Spark 安装在 spark-master 容器的 /opt/spark 目录中。
# Spark 会从这里查找 bin/spark-submit、jars 和 Python 支持文件。
os.environ["SPARK_HOME"] = "/opt/spark"

# Driver 就在 Linux 容器内运行，因此 Driver 使用容器内的 Python 3。
# 这与本地版使用 sys.executable（Windows conda Python）不同。
os.environ["PYSPARK_DRIVER_PYTHON"] = "/usr/bin/python3"

# Executor 同样位于 Linux 容器中，也使用 /usr/bin/python3。
# Driver 与 Executor 的 Python 主次版本应保持一致，以免序列化任务失败。
os.environ["PYSPARK_PYTHON"] = "/usr/bin/python3"


# -----------------------------------------------------------------------------
# 二、创建 SparkSession
# -----------------------------------------------------------------------------
spark = (
    SparkSession.builder

    # 应用名称会显示在 Spark Master Web UI（http://localhost:8080）中。
    .appName("PySparkDockerExample")

    # Docker 网络提供容器名 DNS，因此直接用 spark-master 连接 Master。
    # 容器名比 172.18.0.5 更稳定：容器重建后 IP 可能变化，名称保持不变。
    .master("spark://spark-master:7077")

    # Driver 位于 spark-master 容器，监听容器的所有网络接口，以便其他
    # Worker 容器可以连接。0.0.0.0 仅用于监听，不能作为连接目标地址。
    .config("spark.driver.bindAddress", "0.0.0.0")

    # 告诉 Executor 应通过 spark-master 这个 Docker DNS 名称回连 Driver。
    .config("spark.driver.host", "spark-master")

    # 指定 Spark 为 Python 任务启动 Worker 进程时使用 /usr/bin/python3。
    .config("spark.pyspark.python", "/usr/bin/python3")

    # 将解释器路径作为环境变量显式传给各 Executor，避免不同容器选到不同
    # Python。此项与上项配合，使解释器选择更加明确。
    .config("spark.executorEnv.PYSPARK_PYTHON", "/usr/bin/python3")

    # 整个教学示例最多使用 2 个核心，避免占用全部集群资源。
    .config("spark.cores.max", "2")

    # 本例数据很少，把 groupBy 产生的 shuffle 分区从默认值缩小到 2。
    .config("spark.sql.shuffle.partitions", "2")

    # 不记录 History Server 事件日志，避免简单示例依赖 HDFS 日志目录。
    .config("spark.eventLog.enabled", "false")

    # 真正创建 Driver 上下文并向 Master 注册应用。
    .getOrCreate()
)

# 只展示 WARN 及更严重的 Spark 日志，减少课堂输出噪声。
spark.sparkContext.setLogLevel("WARN")


# -----------------------------------------------------------------------------
# 三、创建 DataFrame
# -----------------------------------------------------------------------------
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
# 四、筛选、分组并聚合
# -----------------------------------------------------------------------------
# filter、groupBy、agg 和 orderBy 都是惰性转换；调用 show() 后才真正执行。
result = (
    orders
    .filter(col("status") == "paid")
    .groupBy("category")
    .agg(spark_sum("amount").alias("total_amount"))
    .orderBy("category")
)

print("Master:", spark.sparkContext.master)
result.show()

# 停止 SparkSession，通知 Master 回收本应用的 Executor 和其他资源。
spark.stop()
