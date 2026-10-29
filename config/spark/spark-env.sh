export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
# Hadoop客户端配置与Spark自身配置分目录保存。
# Hadoop和Spark都存在名为workers的文件；共用/opt/spark/conf会导致
# Hadoop的DataNode列表覆盖Spark的Worker列表。
export HADOOP_CONF_DIR=/opt/spark/hadoop-conf
export YARN_CONF_DIR=/opt/spark/hadoop-conf

# PySpark Python解释器配置
# PYSPARK_DRIVER_PYTHON用于提交作业的Driver；PYSPARK_PYTHON用于Executor中的Python Worker。
# Master和所有Worker必须使用兼容的Python版本，否则分布式任务会在Executor端失败。
export PYSPARK_DRIVER_PYTHON=${PYSPARK_DRIVER_PYTHON:-/usr/bin/python3}
export PYSPARK_PYTHON=${PYSPARK_PYTHON:-/usr/bin/python3}
export PYTHONPATH="$SPARK_HOME/python:$SPARK_HOME/python/lib/py4j-0.10.9-src.zip:${PYTHONPATH:-}"

# 入口脚本和SSH远程会话必须使用同一守护进程标识，否则两种启动方式会生成
# 不同PID文件并在同一容器中重复启动Worker。
export SPARK_IDENT_STRING=${SPARK_IDENT_STRING:-root}

# Spark原生start-all.sh/stop-all.sh会读取workers并通过SSH批量管理Worker。
# BatchMode保证免密认证失败时立即报错；不记录容器主机指纹，避免容器重建后
# 因SSH host key变化阻塞课堂操作。
export SPARK_SSH_OPTS="${SPARK_SSH_OPTS:--o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o LogLevel=ERROR}"

export SPARK_MASTER_HOST=spark-master
export SPARK_MASTER_PORT=7077
export SPARK_MASTER_WEBUI_PORT=8080
export SPARK_WORKER_CORES=2
export SPARK_WORKER_MEMORY=2g
export SPARK_WORKER_WEBUI_PORT=8081
export SPARK_DAEMON_MEMORY=512m
export SPARK_HISTORY_OPTS="-Dspark.history.fs.logDirectory=hdfs://mycluster/spark-logs"
