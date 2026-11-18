#!/bin/bash
# ===============================================================
# 大数据代码开发容器（client）启动脚本
#
# 职责：把挂载进来的共享配置渲染到各客户端的实际配置目录，生成交互式
#       shell 需要的环境变量（含 Java CLASSPATH 用的 BIGDATA_JARS），
#       首次启动时把示例代码放进持久化目录，然后保持容器常驻。
#
# 注意：本容器不启动任何大数据服务，容器本身只需保持运行，
#       所有代码编写与作业提交都通过 docker exec 进入完成。
# ===============================================================
set -u

export HADOOP_HOME=${HADOOP_HOME:-/opt/hadoop}
export HIVE_HOME=${HIVE_HOME:-/opt/hive}
export KAFKA_HOME=${KAFKA_HOME:-/opt/kafka}
export FLINK_HOME=${FLINK_HOME:-/opt/flink}
export FLUME_HOME=${FLUME_HOME:-/opt/flume}
export MAVEN_HOME=${MAVEN_HOME:-/opt/maven}
export SPARK_HOME=${SPARK_HOME:-/opt/spark}
export HADOOP_CONF_DIR=${HADOOP_CONF_DIR:-/opt/hadoop/etc/hadoop}
export YARN_CONF_DIR=${YARN_CONF_DIR:-/opt/hadoop/etc/hadoop}
export HIVE_CONF_DIR=${HIVE_CONF_DIR:-/opt/hive/conf}
export SPARK_CONF_DIR=${SPARK_CONF_DIR:-/opt/spark/conf}

# ---------------------------------------------------------------
# 1. 解析 Hadoop 环境（standard / ha），与 spark-entrypoint.sh 一致：
#    宿主机显式设置优先，否则读挂载的 config/environment.conf。
# ---------------------------------------------------------------
ENV_MODE=""
if [ -f /config/environment.conf ]; then
    ENV_MODE=$(grep -m1 '^HADOOP_ENVIRONMENT=' /config/environment.conf \
               | cut -d= -f2 | tr -d '[:space:]' | tr -d '"' | tr -d "'" \
               | tr '[:upper:]' '[:lower:]')
fi
if [ -n "${HADOOP_ENVIRONMENT_OVERRIDE:-}" ]; then
    ENV_MODE=$(echo "$HADOOP_ENVIRONMENT_OVERRIDE" | tr '[:upper:]' '[:lower:]')
fi

case "$ENV_MODE" in
    ha) HCONF=/config/hadoop-ha; NAMESERVICE="hdfs://mycluster" ;;
    *)  HCONF=/config/hadoop;    NAMESERVICE="hdfs://namenode:8020"; ENV_MODE="standard" ;;
esac

# ---------------------------------------------------------------
# 2. 渲染各组件客户端配置
# ---------------------------------------------------------------
mkdir -p "$HADOOP_CONF_DIR" "$SPARK_CONF_DIR" "$HIVE_CONF_DIR"

cp -f "$HCONF"/*.xml "$HADOOP_CONF_DIR"/ 2>/dev/null || true
[ -f "$HCONF/workers" ] && cp -f "$HCONF/workers" "$HADOOP_CONF_DIR"/
[ -f /config/hive/hive-site.xml ] && cp -f /config/hive/hive-site.xml "$HIVE_CONF_DIR"/

for tpl in spark-defaults.conf spark-env.sh; do
    if [ -f "/config/spark/$tpl.template" ]; then
        sed "s|{{HDFS_NAMESERVICE}}|$NAMESERVICE|g" \
            "/config/spark/$tpl.template" > "$SPARK_CONF_DIR/$tpl"
    elif [ -f "/config/spark/$tpl" ]; then
        cp -f "/config/spark/$tpl" "$SPARK_CONF_DIR/$tpl"
    fi
done

# 开发容器经常用 local[*] 做单机调试，此时 HDFS 可能没启动；
# 默认关闭 eventLog 避免刷屏告警。需要 History Server 时设
# CLIENT_SPARK_EVENTLOG=true（并先启动 Hadoop），或提交时用 --conf 覆盖。
if [ "${CLIENT_SPARK_EVENTLOG:-false}" != "true" ]; then
    sed -i 's/^spark.eventLog.enabled.*/spark.eventLog.enabled           false/' \
        "$SPARK_CONF_DIR/spark-defaults.conf" 2>/dev/null || true
fi

# ---------------------------------------------------------------
# 3. 生成登录 shell 的环境变量（bash -l / script 启动的 PTY 都会加载）
#    BIGDATA_JARS 供 javac -cp 与 Maven 使用，不强行塞进 CLASSPATH，
#    避免 Hive/Flink/Flume 自带的 guava、slf4j 互相污染。
# ---------------------------------------------------------------
JARS=$(find /opt/hadoop/share/hadoop /opt/hive/lib /opt/kafka/libs \
            /opt/flink/lib /opt/flume/lib -type f -name '*.jar' \
            ! -name '*-sources.jar' ! -name '*-javadoc.jar' \
            ! -name '*-tests.jar' ! -name '*-test-sources.jar' \
            ! -name '*-sources*.jar' 2>/dev/null \
       | sort | paste -sd: -)

PROFILE=/etc/profile.d/bigdata-client.sh
{
    echo '# 由 scripts/client-entrypoint.sh 生成，勿手工编辑'
    echo 'export LANG=C.UTF-8'
    echo 'export LC_ALL=C.UTF-8'
    echo 'export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64'
    echo 'export HADOOP_HOME=/opt/hadoop'
    echo 'export HIVE_HOME=/opt/hive'
    echo 'export KAFKA_HOME=/opt/kafka'
    echo 'export FLINK_HOME=/opt/flink'
    echo 'export FLUME_HOME=/opt/flume'
    echo 'export MAVEN_HOME=/opt/maven'
    echo 'export SPARK_HOME=/opt/spark'
    echo 'export HADOOP_CONF_DIR=/opt/hadoop/etc/hadoop'
    echo 'export YARN_CONF_DIR=/opt/hadoop/etc/hadoop'
    echo 'export HIVE_CONF_DIR=/opt/hive/conf'
    echo 'export SPARK_CONF_DIR=/opt/spark/conf'
    echo 'export PYSPARK_PYTHON=/usr/bin/python3'
    echo 'export PYSPARK_DRIVER_PYTHON=/usr/bin/python3'
    echo 'export PYTHONPATH="$SPARK_HOME/python:$SPARK_HOME/python/lib/py4j-0.10.9-src.zip:${PYTHONPATH:-}"'
    echo "export BIGDATA_JARS=\"/opt/spark/jars/*:$JARS\""
    echo 'export PATH="$MAVEN_HOME/bin:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$HIVE_HOME/bin:$KAFKA_HOME/bin:$FLINK_HOME/bin:$FLUME_HOME/bin:$SPARK_HOME/bin:$SPARK_HOME/sbin:$PATH"'
} > "$PROFILE"
chmod 0644 "$PROFILE"

# ---------------------------------------------------------------
# 4. 首次启动投放示例代码；cp -n 保证不覆盖学生已有代码
# ---------------------------------------------------------------
# 按文件粒度增量投放：cp -n 本身不覆盖学生已有代码，无需以 README.md 是否存在为门槛，
# 这样镜像构建之后新增的示例也能补进已创建过的 workspace。
if [ -d /opt/client-examples ]; then
    cp -rn /opt/client-examples/. /workspace/ 2>/dev/null || true
fi

echo "=========================================================="
echo " 大数据代码开发容器 (client) 已就绪"
echo "----------------------------------------------------------"
echo " Hadoop 模式   : $ENV_MODE  ($NAMESERVICE)"
echo " Spark/PySpark : $SPARK_HOME  (Spark 3.1.1 自带 pyspark)"
echo " Hadoop 客户端 : $HADOOP_HOME  (hdfs / yarn / hadoop jar)"
echo " Hive 客户端   : $HIVE_HOME  (beeline / PyHive)"
echo " Kafka 客户端  : $KAFKA_HOME  (kafka-python / kafka-clients)"
echo " Flink 客户端  : $FLINK_HOME  (flink run)"
echo " Flume SDK     : $FLUME_HOME"
echo " Maven         : $MAVEN_HOME"
echo " 代码目录      : /workspace  (宿主机挂载，重启不丢失)"
echo " 进入方式      : 网页「▣ 全交互」/「>_ 终端」或 docker exec"
echo "=========================================================="

# 不启动任何服务，仅保持容器常驻。
exec tail -f /dev/null
