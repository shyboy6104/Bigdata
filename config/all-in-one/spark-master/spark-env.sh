#!/bin/bash

# Spark Master / PySpark Driver运行环境
export JAVA_HOME=${JAVA_HOME:-/usr/lib/jvm/java-8-openjdk-amd64}
export SPARK_HOME=${SPARK_HOME:-/opt/spark}
export HADOOP_CONF_DIR=${HADOOP_CONF_DIR:-/opt/hadoop/etc/hadoop}

# Driver负责运行Python主程序，Executor中的Python Worker负责执行分布式函数。
export PYSPARK_DRIVER_PYTHON=${PYSPARK_DRIVER_PYTHON:-/usr/bin/python3}
export PYSPARK_PYTHON=${PYSPARK_PYTHON:-/usr/bin/python3}
export PYTHONPATH="$SPARK_HOME/python:$SPARK_HOME/python/lib/py4j-0.10.9-src.zip:${PYTHONPATH:-}"
