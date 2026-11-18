#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""PySpark 最小示例。

默认 local[*] 单机运行，不需要启动任何组件：
    python3 python/pyspark_wordcount.py

提交到 Spark 集群（需先启动 hadoop + spark）：
    SPARK_MASTER=spark://spark-master:7077 python3 python/pyspark_wordcount.py
    （也可以 export SPARK_MASTER 后再运行）

说明：代码里显式设置的 master 优先于 spark-defaults.conf 与
spark-submit 的 --master，因此本示例统一用 SPARK_MASTER 控制。
"""
import os

from pyspark import SparkContext

DATA = [
    "spark flink hadoop",
    "spark kafka hive",
    "hadoop mapreduce spark flink",
    "kafka flume hive flink",
]

MASTER = os.environ.get("SPARK_MASTER", "local[*]")


def main():
    sc = SparkContext(master=MASTER, appName="client-wordcount")
    try:
        sc.setLogLevel("WARN")
        counts = (sc.parallelize(DATA, 2)
                    .flatMap(lambda line: line.split())
                    .map(lambda word: (word, 1))
                    .reduceByKey(lambda a, b: a + b)
                    .collect())
        print("PySpark 版本：%s" % sc.version)
        print("master：%s" % sc.master)
        for word, n in sorted(counts):
            print("  %-12s %d" % (word, n))
    finally:
        sc.stop()


if __name__ == "__main__":
    main()
