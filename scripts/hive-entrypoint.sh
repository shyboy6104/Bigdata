#!/bin/bash

# ===============================================
# Hive数据仓库启动脚本
# 作用：启动Hive Metastore服务和HiveServer2服务
# 原理：配置Hive环境变量，解决Guava版本冲突，启动Hive服务
# 重要性：Hive依赖Hadoop和MySQL，需要正确的环境配置
# ===============================================

# ===============================================
# 环境变量配置
# 作用：设置Hive和Hadoop相关的环境变量
# 原理：Hive需要知道Hadoop的安装位置才能正确访问HDFS
# 变量说明：
#   - HIVE_HOME: Hive安装目录
#   - HADOOP_HOME: Hadoop安装目录
#   - PATH: 包含Hadoop和Hive的可执行文件路径
# ===============================================

export HIVE_HOME=/opt/hive
export HADOOP_HOME=/opt/hadoop
export HADOOP_PREFIX=/opt/hadoop
export PATH=$HADOOP_HOME/bin:$HIVE_HOME/bin:$PATH

# ===============================================
# 环境变量持久化
# 作用：将环境变量写入系统文件，确保在子进程中可用
# 原理：/etc/environment文件在系统启动时自动加载
# 重要性：确保Hive服务在后台运行时能正确找到依赖库
# ===============================================

echo "HADOOP_HOME=$HADOOP_HOME" > /etc/environment
echo "HADOOP_PREFIX=$HADOOP_PREFIX" >> /etc/environment
echo "HIVE_HOME=$HIVE_HOME" >> /etc/environment
echo "PATH=$PATH" >> /etc/environment

# ===============================================
# 服务启动信息
# 作用：显示Hive服务启动前的环境信息
# 原理：便于调试和验证环境配置是否正确
# 输出内容：Hadoop和Hive的安装目录信息
# ===============================================

echo "Starting Hive services..."
echo "HADOOP_HOME: $HADOOP_HOME"
echo "HIVE_HOME: $HIVE_HOME"

# ===============================================
# Guava版本冲突解决
# 作用：解决Hive和Hadoop之间Guava库的版本冲突问题
# 原理：Hive自带的Guava版本与Hadoop不兼容，需要替换
# 操作步骤：
#   1. 删除Hive自带的旧版Guava
#   2. 复制Hadoop中的兼容版Guava到Hive lib目录
# ===============================================

# 检查并修复Guava版本冲突
if [ -f /opt/hive/lib/guava-19.0.jar ]; then
    rm -f /opt/hive/lib/guava-19.0.jar
fi
if [ ! -f /opt/hive/lib/guava-27.0-jre.jar ]; then
    cp /opt/hadoop/share/hadoop/common/lib/guava-27.0-jre.jar /opt/hive/lib/
fi

# ===============================================
# 配置文件复制
# 作用：将外部挂载的配置文件复制到Hive配置目录
# 原理：支持配置热更新，便于调试和配置管理
# 配置内容：hive-site.xml等Hive核心配置文件
# ===============================================

# 复制配置文件
cp -r /config/hive/* $HIVE_HOME/conf/

# ===============================================
# Hadoop配置目录创建
# 作用：创建Hadoop配置目录的符号链接
# 原理：Hive需要访问Hadoop的配置文件才能与HDFS交互
# 重要性：确保Hive能正确读取Hadoop集群的配置信息
# ===============================================

# 创建Hadoop配置目录
mkdir -p /opt/hadoop/etc/hadoop
export HADOOP_CONF_DIR=/opt/hadoop/etc/hadoop

REQUESTED_HADOOP_ENVIRONMENT=${HADOOP_ENVIRONMENT:-}

if [ -f /config/environment.conf ]; then
    source /config/environment.conf
fi

export HADOOP_ENVIRONMENT=${REQUESTED_HADOOP_ENVIRONMENT:-${HADOOP_ENVIRONMENT:-standard}}

if [ "$HADOOP_ENVIRONMENT" = "ha" ]; then
    cp -r /config/hadoop-ha/* $HADOOP_CONF_DIR/
else
    cp -r /config/hadoop/* $HADOOP_CONF_DIR/
fi

# 等待Hadoop服务就绪
echo "Waiting for Hadoop services to be ready..."
for i in {1..60}; do
    if /opt/hadoop/bin/hdfs dfs -test -d / > /dev/null 2>&1; then
        echo "HDFS is ready!"
        break
    fi
    sleep 2
    if [ $i -eq 60 ]; then
        echo "Error: HDFS not ready after 120 seconds"
        exit 1
    fi
done

# 创建Hive在HDFS上的目录
/opt/hadoop/bin/hdfs dfs -mkdir -p /user/hive/warehouse
/opt/hadoop/bin/hdfs dfs -mkdir -p /tmp/hive
/opt/hadoop/bin/hdfs dfs -chmod 777 /user/hive/warehouse
/opt/hadoop/bin/hdfs dfs -chmod 777 /tmp/hive

# 初始化Hive元数据存储（带错误阻断机制）
if [[ "$HOSTNAME" == *"metastore"* ]]; then
    echo "Initializing Hive metastore..."
    if $HIVE_HOME/bin/schematool -info -dbType mysql 2>/dev/null; then
        echo "Hive metastore schema already exists, skipping initialization..."
    else
        echo "Initializing Hive metastore schema..."
        $HIVE_HOME/bin/schematool -initSchema -dbType mysql
        if [ $? -ne 0 ]; then
            echo "ERROR: Failed to initialize Hive Metastore Schema!"
            echo "Please check MySQL connection and privileges."
            exit 1
        fi
    fi
fi

# 启动Hive Metastore服务
if [[ "$HOSTNAME" == *"metastore"* ]]; then
    echo "Starting Hive Metastore..."
    nohup $HIVE_HOME/bin/hive --service metastore > /opt/hive/logs/metastore.log 2>&1 &
    metastore_pid=$!
    
    for i in {1..30}; do
        if netstat -tuln | grep -q ":9083 "; then
            echo "Hive Metastore started successfully on port 9083"
            break
        fi
        sleep 2
        if [ $i -eq 30 ]; then
            echo "Error: Hive Metastore failed to start"
            exit 1
        fi
    done
fi

# 启动Hive Server2服务
if [[ "$HOSTNAME" == *"server2"* ]]; then
    echo "Starting Hive Server2..."
    for i in {1..60}; do
        if bash -c "cat < /dev/null > /dev/tcp/hive-metastore/9083" 2>/dev/null; then
            break
        fi
        sleep 2
    done
    
    nohup $HIVE_HOME/bin/hive --service hiveserver2 > /opt/hive/logs/hiveserver2.log 2>&1 &
    hiveserver2_pid=$!
    
    for i in {1..60}; do
        if netstat -tuln 2>/dev/null | grep -q ":10000 "; then
            echo "Hive Server2 started successfully on port 10000"
            break
        fi
        sleep 2
    done
fi

# 启动Hive CLI节点
if [[ "$HOSTNAME" == *"cli"* ]]; then
    echo "Starting Hive CLI..."
    source /etc/environment
    export HADOOP_HOME=/opt/hadoop
    export HIVE_HOME=/opt/hive
    export PATH=$HADOOP_HOME/bin:$HIVE_HOME/bin:$PATH
    
    echo "Waiting for Hive Server2 to be ready..."
    for i in {1..60}; do
        # 【修复点】使用主机名 hive-server2 代替硬编码的 172.18.0.7
        if bash -c "cat < /dev/null > /dev/tcp/hive-server2/10000" 2>/dev/null; then
            echo "Hive Server2 is reachable"
            break
        fi
        sleep 2
    done
    
    $HIVE_HOME/bin/hive
fi

echo "Hive services started successfully!"

# 保持容器运行并监控服务状态
while true; do
    if [[ "$HOSTNAME" == *"metastore"* ]] && ! ps -p $metastore_pid > /dev/null 2>&1; then
        echo "Hive Metastore process died, restarting..."
        nohup $HIVE_HOME/bin/hive --service metastore >> /opt/hive/logs/metastore.log 2>&1 &
        metastore_pid=$!
    fi
    
    if [[ "$HOSTNAME" == *"server2"* ]] && ! ps -p $hiveserver2_pid > /dev/null 2>&1; then
        echo "Hive Server2 process died, restarting..."
        nohup $HIVE_HOME/bin/hive --service hiveserver2 >> /opt/hive/logs/hiveserver2.log 2>&1 &
        hiveserver2_pid=$!
    fi
    sleep 10
done
