#!/bin/bash

# ===============================================
# Hadoop标准集群启动脚本
# 作用：根据容器角色启动相应的Hadoop服务
# 原理：通过命令行参数识别容器角色，执行对应的服务启动流程
# 适用场景：标准Hadoop集群（非HA模式）
# ===============================================

# ===============================================
# 基础服务启动
# ===============================================

# 启动SSH服务，用于容器间通信和远程管理
# 原理：Hadoop集群组件间需要通过SSH进行通信和故障检测
/etc/init.d/ssh start

# ===============================================
# 动态配置加载
# ===============================================

# 如果挂载了外部配置文件，则覆盖默认配置
# 原理：支持配置热更新，便于调试和配置管理
if [ -d "/config/hadoop" ]; then
    echo "加载外部Hadoop配置文件..."
    cp -f /config/hadoop/* $HADOOP_CONF_DIR/
fi

# ===============================================
# 角色识别和服务启动分发
# ===============================================

# 根据传入的参数决定启动什么服务
# 参数来源：Docker Compose command字段传递的角色标识

# ===============================================
# NameNode服务启动（主节点）
# ===============================================

if [ "$1" = "namenode" ]; then
    # 格式化NameNode元数据存储（幂等操作）
    # 原理：检查元数据目录是否存在，避免重复格式化
    if [ ! -d "/opt/hadoop/data/dfs/name" ]; then
        echo "格式化NameNode元数据..."
        $HADOOP_HOME/bin/hdfs namenode -format -force -nonInteractive
    fi
    
    # 启动NameNode服务
    echo "启动NameNode服务..."
    $HADOOP_HOME/bin/hdfs --daemon start namenode
    
    # 启动ResourceManager，负责YARN资源调度
    echo "启动ResourceManager（YARN资源管理器）..."
    $HADOOP_HOME/bin/yarn --daemon start resourcemanager
    
    # 启动JobHistoryServer，记录MapReduce作业历史
    echo "启动JobHistoryServer（作业历史服务器）..."
    $HADOOP_HOME/bin/mapred --daemon start historyserver
    
    # 等待HDFS退出安全模式后创建Spark日志目录
    echo "等待HDFS退出安全模式..."
    for i in {1..30}; do
        if $HADOOP_HOME/bin/hdfs dfsadmin -safemode get 2>/dev/null | grep -q "OFF"; then
            echo "HDFS已退出安全模式"
            break
        fi
        echo "等待HDFS安全模式... (尝试 $i/30)"
        sleep 2
    done
    
    # 创建Spark事件日志目录
    echo "创建Spark事件日志目录..."
    $HADOOP_HOME/bin/hdfs dfs -mkdir -p /spark-logs 2>/dev/null
    $HADOOP_HOME/bin/hdfs dfs -chmod 777 /spark-logs 2>/dev/null
    echo "Spark事件日志目录创建完成: /spark-logs"

# ===============================================
# DataNode服务启动（数据存储节点）
# ===============================================

elif [ "$1" = "datanode" ]; then
    echo "启动DataNode服务..."
    $HADOOP_HOME/bin/hdfs --daemon start datanode
    
    echo "Starting NodeManager..."
    $HADOOP_HOME/bin/yarn --daemon start nodemanager
fi

# 保持容器运行
tail -f /dev/null
