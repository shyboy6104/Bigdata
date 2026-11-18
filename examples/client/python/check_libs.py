#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""开发容器自检：逐项导入 Python 库并检查客户端命令是否在 PATH 中。

运行：bash -l -c "cd /workspace && python3 python/check_libs.py"
"""
import importlib
import shutil

PY_LIBS = [
    ("pyspark",      "PySpark（Spark 3.1.1 自带，非 pip 安装）"),
    ("kafka",        "kafka-python（Kafka 生产者/消费者）"),
    ("pyhive",       "PyHive（HiveServer2）"),
    ("hdfs",         "hdfs（WebHDFS 客户端）"),
    ("thrift",       "thrift（Hive/Flume RPC 基础）"),
    ("thrift_sasl",  "thrift-sasl（Hive 认证传输）"),
    ("puresasl",     "pure-sasl（免编译 SASL 实现）"),
    ("avro",         "avro-python3（Flume Avro source）"),
    ("pandas",       "pandas（数据处理）"),
    ("numpy",        "numpy（数值计算）"),
    ("requests",     "requests（HTTP 客户端）"),
]

CLI_TOOLS = [
    "java", "javac", "mvn",
    "hadoop", "hdfs", "yarn", "mapred",
    "spark-submit", "pyspark",
    "beeline", "hive",
    "kafka-console-producer.sh", "kafka-console-consumer.sh",
    "flink", "flume-ng",
]


def main():
    print("=== Python 库 ===")
    failed = 0
    for mod, desc in PY_LIBS:
        try:
            m = importlib.import_module(mod)
            ver = getattr(m, "__version__", "")
            print("  OK   %-12s %-38s %s" % (mod, desc, ver))
        except Exception as exc:
            failed += 1
            print("  FAIL %-12s %-38s %s" % (mod, desc, exc))

    print("\n=== 命令行工具 ===")
    for cmd in CLI_TOOLS:
        path = shutil.which(cmd)
        if path:
            print("  OK   %-30s %s" % (cmd, path))
        else:
            failed += 1
            print("  FAIL %-30s 未找到（检查 PATH / 是否用 bash -l 登录）" % cmd)

    print("\n=== 环境变量 ===")
    import os
    for key in ("JAVA_HOME", "HADOOP_HOME", "SPARK_HOME", "HIVE_HOME",
                "KAFKA_HOME", "FLINK_HOME", "FLUME_HOME", "MAVEN_HOME",
                "HADOOP_CONF_DIR", "SPARK_CONF_DIR", "BIGDATA_JARS"):
        val = os.environ.get(key, "")
        if key == "BIGDATA_JARS":
            val = ("已设置，%d 个字符" % len(val)) if val else "未设置"
        print("  %-18s %s" % (key, val or "未设置"))

    print("\n结果：%s" % ("全部通过" if failed == 0 else "%d 项缺失" % failed))
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
