"""Docker 内的 PySpark 访问 Docker HDFS 的教学示例。

运行方式：
    docker cp DEMO/pyspark-hdfs-example-docker.py spark-master:/tmp/example.py
    docker exec spark-master python3 /tmp/example.py

Driver、Spark Master、Spark Executor 和 Hadoop HDFS 都运行在 Docker 网络中。
"""

import os

from pyspark.sql import SparkSession
from pyspark.sql.functions import sum as spark_sum


# Driver 位于 spark-master Linux 容器，因此 Spark 和 Python 都使用容器路径。
os.environ["SPARK_HOME"] = "/opt/spark"
os.environ["PYSPARK_DRIVER_PYTHON"] = "/usr/bin/python3"
os.environ["PYSPARK_PYTHON"] = "/usr/bin/python3"

# Docker 网络内应优先使用容器名。当前 NameNode IP 虽然是 172.18.0.3，
# 但容器重建后 IP 可能变化；名称 namenode 会由 Docker DNS 自动解析。
SPARK_MASTER = "spark://spark-master:7077"
HDFS_URI = "hdfs://namenode:8020"
HDFS_PATH = HDFS_URI + "/examples/pyspark-hdfs/orders"

spark = (
    SparkSession.builder
    .appName("PySparkHdfsDockerExample")
    .master(SPARK_MASTER)

    # Driver 在 spark-master 容器中监听，并通过容器名供 Worker 回连。
    .config("spark.driver.bindAddress", "0.0.0.0")
    .config("spark.driver.host", "spark-master")

    # 明确指定所有 Executor 使用相同的容器内 Python。
    .config("spark.pyspark.python", "/usr/bin/python3")
    .config("spark.executorEnv.PYSPARK_PYTHON", "/usr/bin/python3")

    # 控制教学示例使用的资源和 shuffle 任务数量。
    .config("spark.cores.max", "2")
    .config("spark.sql.shuffle.partitions", "2")

    # spark.hadoop.* 会传入底层 Hadoop Configuration。
    # fs.defaultFS 指定本应用默认使用的 HDFS NameNode。
    .config("spark.hadoop.fs.defaultFS", HDFS_URI)

    # 集群只有两个 DataNode，因此将 HDFS 数据块副本数设为 2。
    # 这会在两个 DataNode 上各保存一个副本，兼顾教学环境的冗余和资源用量。
    .config("spark.hadoop.dfs.replication", "2")

    .config("spark.eventLog.enabled", "false")
    .getOrCreate()
)

spark.sparkContext.setLogLevel("WARN")

orders = spark.createDataFrame(
    [
        (1, "book", 120),
        (2, "book", 80),
        (3, "food", 50),
        (4, "food", 70),
    ],
    ["order_id", "category", "amount"],
)

# Spark 写 Parquet 时，HDFS_PATH 是一个目录，目录内会生成 part-* 数据文件
# 和表示提交完成的 _SUCCESS 文件。
orders.write.mode("overwrite").parquet(HDFS_PATH)
print("已写入 HDFS：", HDFS_PATH)

# 重新从 HDFS 读取并计算，验证写入的数据可以正常使用。
hdfs_orders = spark.read.parquet(HDFS_PATH)
result = (
    hdfs_orders.groupBy("category")
    .agg(spark_sum("amount").alias("total_amount"))
    .orderBy("category")
)

print("从 HDFS 读取并汇总：")
result.show()

spark.stop()
