export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
export HADOOP_CONF_DIR=/opt/spark/conf
export YARN_CONF_DIR=/opt/spark/conf

# PySpark Python解释器配置
# PYSPARK_DRIVER_PYTHON用于提交作业的Driver；PYSPARK_PYTHON用于Executor中的Python Worker。
# Master和所有Worker必须使用兼容的Python版本，否则分布式任务会在Executor端失败。
export PYSPARK_DRIVER_PYTHON=${PYSPARK_DRIVER_PYTHON:-/usr/bin/python3}
export PYSPARK_PYTHON=${PYSPARK_PYTHON:-/usr/bin/python3}
export PYTHONPATH="$SPARK_HOME/python:$SPARK_HOME/python/lib/py4j-0.10.9-src.zip:${PYTHONPATH:-}"

export SPARK_MASTER_HOST=spark-master
export SPARK_MASTER_PORT=7077
export SPARK_MASTER_WEBUI_PORT=8080
export SPARK_WORKER_CORES=2
export SPARK_WORKER_MEMORY=2g
export SPARK_WORKER_WEBUI_PORT=8081
export SPARK_DAEMON_MEMORY=512m
export SPARK_HISTORY_OPTS="-Dspark.history.fs.logDirectory=hdfs://mycluster/spark-logs"
