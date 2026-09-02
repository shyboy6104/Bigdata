#!/bin/bash

# Spark Worker / PySpark Executor运行环境
export JAVA_HOME=${JAVA_HOME:-/usr/lib/jvm/java-8-openjdk-amd64}
export SPARK_HOME=${SPARK_HOME:-/opt/spark}
export HADOOP_CONF_DIR=${HADOOP_CONF_DIR:-/opt/hadoop/etc/hadoop}

# 每个Worker必须能用同一路径启动Python Worker进程。
export PYSPARK_PYTHON=${PYSPARK_PYTHON:-/usr/bin/python3}
export PYTHONPATH="$SPARK_HOME/python:$SPARK_HOME/python/lib/py4j-0.10.9-src.zip:${PYTHONPATH:-}"
