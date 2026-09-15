"""本地 PySpark 访问 Docker HDFS 的教学示例。

运行方式：
    conda activate pyspark_proj
    python DEMO/pyspark-hdfs-example-local.py

Driver 在 Windows 中运行，Spark Executor 和 Hadoop HDFS 在 Docker 中运行。
程序依次完成：创建 DataFrame -> 写入 HDFS -> 从 HDFS 读回 -> 汇总展示。
"""

import os
import socket
import sys
from pathlib import Path

import pyspark
from pyspark.sql import SparkSession
from pyspark.sql.functions import sum as spark_sum


SCRIPT_DIR = Path(__file__).resolve().parent
LOG4J_CONFIG = SCRIPT_DIR / "log4j-local.properties"

# SPARK_HOME 指向 conda 环境中随 pyspark 安装的 Spark 目录。
os.environ["SPARK_HOME"] = str(Path(pyspark.__file__).resolve().parent)
# Driver 使用当前 Windows conda Python。
os.environ["PYSPARK_DRIVER_PYTHON"] = sys.executable
# Executor 位于 Linux 容器中，所以 Python 必须使用容器内路径。
os.environ["PYSPARK_PYTHON"] = "/usr/bin/python3"

# Spark Master 通过宿主机映射端口访问。
SPARK_MASTER = "spark://127.0.0.1:7077"

# 为什么不用 hdfs://172.18.0.3:8020？
# 172.18.0.3 是 NameNode 当前的容器 IP，容器重建后可能变化，而且 Windows
# 不能直接访问当前 Docker bridge IP。下面取得 Windows 主机名所对应的局域网
# IPv4 地址；Docker 已将 NameNode 的 8020 端口发布到所有宿主机网络接口。
# 这个地址既能被本地 Driver 访问，也能被 Docker Executor 访问。
WINDOWS_HOST_IP = socket.gethostbyname(socket.gethostname())
HDFS_URI = "hdfs://{}:8020".format(WINDOWS_HOST_IP)
HDFS_PATH = HDFS_URI + "/examples/pyspark-hdfs/orders"

spark = (
    SparkSession.builder
    .appName("PySparkHdfsLocalExample")
    .master(SPARK_MASTER)

    # Driver 监听所有本机接口，并把 Docker 可访问的主机名告诉 Executor。
    .config("spark.driver.bindAddress", "0.0.0.0")
    .config("spark.driver.host", "host.docker.internal")

    # Executor 使用 Docker 容器内的 Python 解释器。
    .config("spark.pyspark.python", "/usr/bin/python3")
    .config("spark.executorEnv.PYSPARK_PYTHON", "/usr/bin/python3")

    # 小型教学任务只使用两个核心和两个 shuffle 分区。
    .config("spark.cores.max", "2")
    .config("spark.sql.shuffle.partitions", "2")

    # 显式指定 HDFS 默认地址。代码使用完整 HDFS URI，即使不设置此项也能
    # 访问；保留该配置是为了展示 Spark 如何把 Hadoop 配置传给应用。
    .config("spark.hadoop.fs.defaultFS", HDFS_URI)

    # 当前实验集群有两个 DataNode，所以每个 HDFS 数据块保存两个副本。
    # spark.hadoop. 前缀会被移除，再作为 dfs.replication 传给 Hadoop 客户端。
    # 如果请求 3 个副本而集群只有 2 个 DataNode，文件虽可读取，但 HDFS
    # 会长期报告 under-replicated（副本不足）。
    .config("spark.hadoop.dfs.replication", "2")

    # 本例不向 HDFS 写 Spark History 事件日志，只写下面的教学数据。
    .config("spark.eventLog.enabled", "false")

    # 使用项目内日志配置，隐藏本例不需要的 Windows winutils.exe 警告。
    .config(
        "spark.driver.extraJavaOptions",
        "-Dlog4j.configuration={}".format(LOG4J_CONFIG.as_uri()),
    )
    .getOrCreate()
)

spark.sparkContext.setLogLevel("WARN")

# 创建一个小型订单 DataFrame。这里的数据最初只存在于 Driver 内存中。
orders = spark.createDataFrame(
    [
        (1, "book", 120),
        (2, "book", 80),
        (3, "food", 50),
        (4, "food", 70),
    ],
    ["order_id", "category", "amount"],
)

# mode("overwrite") 便于反复运行课堂示例：目标存在时覆盖旧目录。
# format("parquet") 使用 Spark 常用的列式存储格式，保留列名和数据类型。
orders.write.mode("overwrite").format("parquet").save(HDFS_PATH)
print("已写入 HDFS：", HDFS_PATH)

# 从 HDFS 重新读取，而不是继续使用内存中的 orders，以证明文件确实可用。
hdfs_orders = spark.read.parquet(HDFS_PATH)

# 按类别汇总 HDFS 文件中的订单金额。show() 是 action，会真正触发 Spark 作业。
result = (
    hdfs_orders.groupBy("category")
    .agg(spark_sum("amount").alias("total_amount"))
    .orderBy("category")
)

print("从 HDFS 读取并汇总：")
result.show()

spark.stop()
