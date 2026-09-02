"""PySpark分布式冒烟测试。

该脚本同时执行RDD与DataFrame操作。RDD中的Python函数会在Executor节点的
Python Worker中运行，因此不仅能验证Driver导入PySpark，还能验证Worker端
是否安装了可用且路径一致的Python解释器。
"""

import socket
import sys

import pyspark
from pyspark.sql import SparkSession


spark = SparkSession.builder.appName("PySparkSmokeTest").getOrCreate()
spark.sparkContext.setLogLevel("WARN")

print("[信息] Python版本：{}".format(sys.version.split()[0]))
print("[信息] PySpark版本：{}".format(pyspark.__version__))

# map中的lambda会交给Executor上的Python Worker执行。
numbers = spark.sparkContext.parallelize([1, 2, 3, 4, 5], 4)
square_sum = numbers.map(lambda value: value * value).sum()

# 记录实际执行Python任务的容器主机名，便于失败时确认任务落在哪些Worker。
executor_hosts = sorted(
    spark.sparkContext.parallelize(range(8), 8)
    .mapPartitions(lambda _: [socket.gethostname()])
    .distinct()
    .collect()
)

people = spark.createDataFrame(
    [(1, "Alice", 25), (2, "Bob", 30), (3, "Charlie", 35)],
    ["id", "name", "age"],
)
adult_count = people.filter("age >= 30").count()

print("[信息] Python任务实际执行节点：{}".format(",".join(executor_hosts)))
print("[信息] RDD平方和实际结果：{}，预期结果：55".format(int(square_sum)))
print("[信息] DataFrame年龄>=30记录数：{}，预期结果：2".format(adult_count))

if int(square_sum) != 55:
    raise RuntimeError("RDD平方和错误：期望55，实际{}".format(square_sum))
if adult_count != 2:
    raise RuntimeError("DataFrame过滤结果错误：期望2，实际{}".format(adult_count))
if not executor_hosts:
    raise RuntimeError("没有获得任何Executor Python Worker主机名")

print("PYSPARK_SMOKE_OK square_sum=55 adult_count=2")
spark.stop()
