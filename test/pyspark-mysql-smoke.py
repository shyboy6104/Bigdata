#!/usr/bin/env python3
"""PySpark读取MySQL的教学冒烟测试。

表结构要求包含id、name、age三列。连接信息通过环境变量传入，使同一脚本可以
用于独立组件架构和五节点全栈架构。
"""

import os
import socket
import sys
import traceback

from pyspark.sql import SparkSession
from pyspark.sql import functions as F


JDBC_URL = os.environ.get(
    "MYSQL_JDBC_URL",
    "jdbc:mysql://infra:3306/hive_metastore?useSSL=false",
)
JDBC_TABLE = os.environ.get("MYSQL_JDBC_TABLE", "spark_jdbc_test_person")
JDBC_USER = os.environ.get("MYSQL_JDBC_USER", "hive")
JDBC_PASSWORD = os.environ.get("MYSQL_JDBC_PASSWORD", "hive")
JDBC_DRIVER = os.environ.get("MYSQL_JDBC_DRIVER", "com.mysql.jdbc.Driver")
EXPECTED_ROWS = int(os.environ.get("MYSQL_JDBC_EXPECTED_ROWS", "3"))
EXPECTED_AGE_SUM = int(os.environ.get("MYSQL_JDBC_EXPECTED_AGE_SUM", "90"))


def main():
    spark = None
    try:
        spark = SparkSession.builder.appName("PySparkMySQLSmokeTest").getOrCreate()

        # 先在Driver端显式加载类，类名错误时给出比DataFrame load更直接的诊断。
        loaded_driver = spark._jvm.java.lang.Class.forName(JDBC_DRIVER).getName()
        print("[信息] MySQL JDBC驱动类已加载：{}".format(loaded_driver))
        print("[信息] JDBC地址：{}".format(JDBC_URL))
        print("[信息] 测试表：{}".format(JDBC_TABLE))

        data_frame = (
            spark.read.format("jdbc")
            .option("driver", JDBC_DRIVER)
            .option("url", JDBC_URL)
            .option("dbtable", JDBC_TABLE)
            .option("user", JDBC_USER)
            .option("password", JDBC_PASSWORD)
            .load()
        )

        row_count = data_frame.count()
        age_sum_value = data_frame.agg(F.sum("age").alias("age_sum")).first()["age_sum"]
        age_sum = int(age_sum_value or 0)

        # 触发一次Executor侧计算并记录实际节点，证明不仅Driver能够看到JAR。
        executor_hosts = sorted(
            data_frame.rdd.mapPartitions(
                lambda rows: [socket.gethostname()] if list(rows) else []
            ).distinct().collect()
        )

        print("[信息] JDBC读取记录数：{}，预期：{}".format(row_count, EXPECTED_ROWS))
        print("[信息] age字段合计：{}，预期：{}".format(age_sum, EXPECTED_AGE_SUM))
        print("[信息] 实际执行节点：{}".format(",".join(executor_hosts) or "未识别"))

        if row_count != EXPECTED_ROWS or age_sum != EXPECTED_AGE_SUM:
            raise AssertionError(
                "JDBC计算结果不符合预期：rows={}, age_sum={}".format(
                    row_count, age_sum
                )
            )

        print(
            "PYSPARK_MYSQL_JDBC_OK rows={} age_sum={} driver={}".format(
                row_count, age_sum, loaded_driver
            )
        )
    except Exception:
        print("[错误] PySpark MySQL JDBC冒烟测试失败", file=sys.stderr)
        traceback.print_exc()
        return 1
    finally:
        if spark is not None:
            spark.stop()

    return 0


if __name__ == "__main__":
    sys.exit(main())
