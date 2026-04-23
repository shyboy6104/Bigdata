#!/bin/bash

# Hadoop高可用集群启动脚本
# 作用：根据容器角色启动相应的Hadoop服务，实现高可用集群的自动部署
# 原理：通过环境变量ROLE识别容器角色，执行对应的服务启动流程
# 幂等性设计：通过标记文件确保格式化操作只执行一次

# ===============================================
# 基础服务启动
# ===============================================

# 启动SSH服务，用于容器间通信和远程管理
# 原理：Hadoop集群组件间需要通过SSH进行通信和故障检测
/etc/init.d/ssh start

# 动态配置加载：如果挂载了外部配置文件，则覆盖默认配置
# 原理：支持配置热更新，便于调试和配置管理
if [ -d "/config/hadoop-ha" ]; then
    echo "加载外部Hadoop HA配置文件..."
    cp -f /config/hadoop-ha/* $HADOOP_CONF_DIR/
fi

# ===============================================
# 角色识别和分发
# ===============================================

# 获取容器角色参数，用于确定启动哪些服务
# 参数来源：Docker Compose command字段传递的角色标识
ROLE=$1

# ===============================================
# JournalNode服务启动
# ===============================================

if [ "$ROLE" = "journalnode" ]; then
    echo "启动JournalNode服务..."
    # JournalNode作用：存储HDFS编辑日志，实现NameNode数据同步
    # 启动原理：启动独立的JournalNode进程，加入仲裁集群
    $HADOOP_HOME/bin/hdfs --daemon start journalnode

# ===============================================
# NameNode1服务启动（主节点）
# ===============================================

elif [ "$ROLE" = "namenode1" ]; then
    # 等待JournalNode集群启动完成，确保编辑日志服务可用
    # 原理：NameNode需要JournalNode来存储编辑日志
    echo "等待JournalNode集群启动..."
    sleep 10
    
    # 格式化ZKFC（ZooKeeper Failover Controller）
    # 幂等性：通过标记文件确保只执行一次格式化
    # 原理：在ZooKeeper中创建HA选举节点，用于自动故障转移
    if [ ! -f "/opt/hadoop/data/zkfc_formatted" ]; then
        echo "格式化ZKFC（ZooKeeper Failover Controller）..."
        $HADOOP_HOME/bin/hdfs zkfc -formatZK -force -nonInteractive
        touch /opt/hadoop/data/zkfc_formatted
    fi
    
    # 格式化NameNode元数据存储
    # 幂等性：检查元数据目录是否存在，避免重复格式化
    # 原理：创建NameNode的命名空间镜像和编辑日志初始结构
    if [ ! -d "/opt/hadoop/data/dfs/name" ]; then
        echo "格式化NameNode元数据..."
        $HADOOP_HOME/bin/hdfs namenode -format -force -nonInteractive
    fi
    
    # 启动NameNode服务
    echo "启动NameNode服务..."
    $HADOOP_HOME/bin/hdfs --daemon start namenode
    
    # 启动ZKFC服务，实现自动故障转移
    echo "启动ZKFC（自动故障转移控制器）..."
    $HADOOP_HOME/bin/hdfs --daemon start zkfc
    
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
# NameNode2服务启动（备节点）
# ===============================================

elif [ "$ROLE" = "namenode2" ]; then
    # 等待NameNode1完全启动并格式化完成
    # 原理：备节点需要从主节点同步元数据，确保数据一致性
    echo "等待NameNode1启动完成..."
    sleep 20
    
    # 从NameNode1同步元数据（幂等操作）
    # 原理：通过bootstrapStandby命令从主节点获取最新的元数据镜像
    if [ ! -d "/opt/hadoop/data/dfs/name" ]; then
        echo "从NameNode1同步元数据..."
        $HADOOP_HOME/bin/hdfs namenode -bootstrapStandby -force -nonInteractive
    fi
    
    # 启动NameNode2服务（Standby模式）
    echo "启动NameNode2服务（Standby模式）..."
    $HADOOP_HOME/bin/hdfs --daemon start namenode
    
    # 启动ZKFC服务，参与自动故障转移选举
    echo "启动ZKFC（自动故障转移控制器）..."
    $HADOOP_HOME/bin/hdfs --daemon start zkfc
    
    # 启动ResourceManager（Standby模式）
    echo "启动ResourceManager（Standby模式）..."
    $HADOOP_HOME/bin/yarn --daemon start resourcemanager

# ===============================================
# DataNode服务启动（数据存储节点）
# ===============================================

elif [ "$ROLE" = "datanode" ]; then
    # 等待NameNode集群启动完成
    # 原理：DataNode需要向Active NameNode注册，需要确保NameNode可用
    echo "等待NameNode集群启动完成..."
    sleep 30
    
    # ===============================================
    # 环境变量优化配置
    # 作用：修复MapReduce Application Master启动失败的问题
    # 原理：确保MapReduce作业运行时能找到正确的Hadoop类路径
    # ===============================================
    
    # 设置系统环境变量
    echo "配置MapReduce环境变量..."
    echo "export HADOOP_MAPRED_HOME=/opt/hadoop" >> /etc/profile
    echo "export HADOOP_CONF_DIR=/opt/hadoop/etc/hadoop" >> /etc/profile
    echo "export YARN_CONF_DIR=/opt/hadoop/etc/hadoop" >> /etc/profile
    echo "export HADOOP_CLASSPATH=\$($HADOOP_HOME/bin/hadoop classpath)" >> /etc/profile
    source /etc/profile
    
    # 配置Hadoop环境文件
    echo "配置Hadoop环境文件..."
    echo "export HADOOP_MAPRED_HOME=/opt/hadoop" >> $HADOOP_CONF_DIR/hadoop-env.sh
    echo "export HADOOP_CONF_DIR=/opt/hadoop/etc/hadoop" >> $HADOOP_CONF_DIR/hadoop-env.sh
    echo "export YARN_CONF_DIR=/opt/hadoop/etc/hadoop" >> $HADOOP_CONF_DIR/hadoop-env.sh
    echo "export HADOOP_CLASSPATH=\$($HADOOP_HOME/bin/hadoop classpath)" >> $HADOOP_CONF_DIR/hadoop-env.sh
    
    # 配置YARN环境文件
    echo "配置YARN环境文件..."
    echo "export HADOOP_MAPRED_HOME=/opt/hadoop" >> $HADOOP_CONF_DIR/yarn-env.sh
    echo "export HADOOP_CONF_DIR=/opt/hadoop/etc/hadoop" >> $HADOOP_CONF_DIR/yarn-env.sh
    echo "export YARN_CONF_DIR=/opt/hadoop/etc/hadoop" >> $HADOOP_CONF_DIR/yarn-env.sh
    echo "export HADOOP_CLASSPATH=\$($HADOOP_HOME/bin/hadoop classpath)" >> $HADOOP_CONF_DIR/yarn-env.sh
    
    # 启动DataNode服务
    echo "启动DataNode服务..."
    $HADOOP_HOME/bin/hdfs --daemon start datanode
    
    # 启动NodeManager服务
    echo "启动NodeManager服务..."
    $HADOOP_HOME/bin/yarn --daemon start nodemanager
fi

# 保持容器运行
tail -f /dev/null
