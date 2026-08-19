#!/bin/bash

# ===============================================
# Spark内存计算引擎启动脚本
# 作用：配置Spark运行环境，根据Hadoop环境动态生成配置文件
# 原理：支持标准Hadoop和HA Hadoop两种环境，自动适配配置
# 重要性：Spark依赖Hadoop环境，正确的配置确保任务执行正常
# ===============================================

# 设置严格错误处理模式：任何命令失败立即退出脚本
set -e

# ===============================================
# 基础环境变量设置
# 作用：加载系统环境变量，设置Spark和Hadoop相关路径
# 原理：确保脚本能正确找到Spark和Hadoop的安装位置
# 变量说明：
#   - SPARK_HOME: Spark安装目录
#   - HADOOP_CONF_DIR: Hadoop配置目录
# ===============================================

# 设置环境变量
source /etc/profile

# 设置默认环境变量
export SPARK_HOME=${SPARK_HOME:-/opt/spark}
export HADOOP_CONF_DIR=${HADOOP_CONF_DIR:-/opt/spark/conf}

# ===============================================
# 环境配置加载
# 作用：加载外部环境配置文件，支持动态配置
# 原理：如果存在/config/environment.conf文件，则加载其中的配置
# 配置内容：可能包含版本信息、集群参数等自定义配置
# ===============================================

# Docker Compose 显式传入的部署模式优先于共享环境文件中的默认值。
REQUESTED_HADOOP_ENVIRONMENT=${HADOOP_ENVIRONMENT:-}

# 加载环境配置
if [ -f /config/environment.conf ]; then
    source /config/environment.conf
fi

# ===============================================
# Hadoop环境类型设置
# 作用：指定使用的Hadoop环境类型（标准或HA）
# 原理：根据环境类型加载不同的Hadoop配置文件
# 默认值：ha（高可用环境），支持standard（标准环境）
# ===============================================

# 设置默认Hadoop环境
export HADOOP_ENVIRONMENT=${REQUESTED_HADOOP_ENVIRONMENT:-${HADOOP_ENVIRONMENT:-ha}}

# ===============================================
# 配置目录准备
# 作用：创建Hadoop配置目录，确保配置文件的正确存储
# 原理：mkdir -p确保目录存在，避免文件复制失败
# 重要性：配置目录是Spark读取Hadoop配置的关键路径
# ===============================================

# 创建Hadoop配置目录
mkdir -p $HADOOP_CONF_DIR

# ===============================================
# Spark配置文件复制
# 作用：将外部配置目录中的Spark配置文件复制到安装目录
# 原理：支持配置热更新，便于调试和配置管理
# 配置内容：spark-defaults.conf、spark-env.sh等核心配置
# ===============================================

# 复制Spark配置文件
cp -r /config/spark/* $SPARK_HOME/conf/

# 根据环境配置复制Hadoop配置文件
echo "Using Hadoop environment: $HADOOP_ENVIRONMENT"
if [ "$HADOOP_ENVIRONMENT" = "ha" ]; then
    echo "Copying Hadoop HA configuration..."
    cp -r /config/hadoop-ha/* $HADOOP_CONF_DIR/
    # 设置HA环境的HDFS nameservice
    export HDFS_NAMESERVICE="hdfs://mycluster"
elif [ "$HADOOP_ENVIRONMENT" = "standard" ]; then
    echo "Copying standard Hadoop configuration..."
    cp -r /config/hadoop/* $HADOOP_CONF_DIR/
    # 设置标准环境的HDFS nameservice
    export HDFS_NAMESERVICE="hdfs://namenode:8020"
else
    echo "Warning: Unknown Hadoop environment '$HADOOP_ENVIRONMENT', using HA configuration as default"
    cp -r /config/hadoop-ha/* $HADOOP_CONF_DIR/
    export HDFS_NAMESERVICE="hdfs://mycluster"
fi

# 动态生成Spark配置文件
echo "Generating Spark configuration files..."

# 生成spark-defaults.conf
if [ -f /config/spark/spark-defaults.conf.template ]; then
    # 使用不同的分隔符避免路径中的斜杠冲突
    sed "s|{{HDFS_NAMESERVICE}}|$HDFS_NAMESERVICE|g" /config/spark/spark-defaults.conf.template > $SPARK_HOME/conf/spark-defaults.conf
    echo "Generated spark-defaults.conf with HDFS nameservice: $HDFS_NAMESERVICE"
else
    echo "Warning: spark-defaults.conf.template not found, using static configuration"
    cp -r /config/spark/* $SPARK_HOME/conf/
fi

# 生成spark-env.sh
if [ -f /config/spark/spark-env.sh.template ]; then
    # 使用不同的分隔符避免路径中的斜杠冲突
    sed "s|{{HDFS_NAMESERVICE}}|$HDFS_NAMESERVICE|g" /config/spark/spark-env.sh.template > $SPARK_HOME/conf/spark-env.sh
    echo "Generated spark-env.sh with HDFS nameservice: $HDFS_NAMESERVICE"
else
    echo "Warning: spark-env.sh.template not found, using static configuration"
    cp -r /config/spark/* $SPARK_HOME/conf/
fi

# 确保HADOOP_CONF_DIR在classpath中
export SPARK_DIST_CLASSPATH=$HADOOP_CONF_DIR

# 等待HDFS服务就绪（通过测试HDFS端口连通性）
echo "Waiting for HDFS services to be ready..."
HDFS_READY=false
for i in {1..60}; do
    if [ "$HADOOP_ENVIRONMENT" = "ha" ]; then
        if (echo > /dev/tcp/namenode1/8020) 2>/dev/null; then
            echo "HDFS NameNode is ready!"
            HDFS_READY=true
            break
        fi
    else
        if (echo > /dev/tcp/namenode/8020) 2>/dev/null; then
            echo "HDFS NameNode is ready!"
            HDFS_READY=true
            break
        fi
    fi
    echo "Waiting for HDFS... (attempt $i/60)"
    sleep 1
done

if [ "$HDFS_READY" = "false" ]; then
    echo "Warning: HDFS not available, event logging may fail"
fi

# 根据角色启动服务
case "$ROLE" in
    "master")
        echo "Starting Spark Master..."
        $SPARK_HOME/sbin/start-master.sh
        echo "Starting Spark History Server..."
        $SPARK_HOME/sbin/start-history-server.sh
        # 保持容器运行
        tail -f $SPARK_HOME/logs/*
        ;;
    "worker")
        echo "Waiting for Spark Master to start..."
        sleep 30
        echo "Starting Spark Worker..."
        $SPARK_HOME/sbin/start-worker.sh spark://spark-master:7077
        # 保持容器运行
        tail -f $SPARK_HOME/logs/*
        ;;
    *)
        echo "Unknown role: $ROLE"
        exit 1
        ;;
esac
