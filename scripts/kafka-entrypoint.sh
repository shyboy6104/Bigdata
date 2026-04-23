#!/bin/bash

# ===============================================
# Kafka消息队列服务启动脚本
# 作用：根据容器主机名自动识别节点ID，加载对应的配置文件
# 原理：通过主机名解析节点标识，支持多Broker集群部署
# 重要性：Kafka集群的核心启动脚本，确保每个Broker使用正确的配置
# ===============================================

# 设置严格错误处理模式：任何命令失败立即退出脚本
set -e

# ===============================================
# 节点标识自动识别
# 作用：从容器主机名中提取Kafka节点ID
# 原理：主机名格式为kafka1、kafka2等，提取数字部分作为节点ID
# 正则表达式：sed 's/kafka//' 移除主机名中的"kafka"前缀
# ===============================================

# Extract node ID from hostname (e.g., kafka1 -> 1)
NODE_ID=$(hostname | sed 's/kafka//')

# ===============================================
# 节点标识验证和容错处理
# 作用：验证提取的节点ID是否有效，提供默认值作为容错机制
# 原理：如果节点ID为空或不是数字，则使用默认值1
# 正则表达式：^[0-9]+$ 确保节点ID是纯数字
# ===============================================

# Fallback if hostname parsing fails
if [ -z "$NODE_ID" ] || [[ ! "$NODE_ID" =~ ^[0-9]+$ ]]; then
    echo "警告：无法从主机名解析节点ID，使用默认值1"
    NODE_ID=1
fi

# ===============================================
# 配置文件选择逻辑
# 作用：根据节点ID选择对应的Kafka配置文件
# 原理：每个Kafka Broker使用独立的配置文件，避免配置冲突
# 文件命名规则：
#   - 节点1: server.properties
#   - 节点2: server2.properties
#   - 节点3: server3.properties
# ===============================================

# Select configuration file
CONFIG_FILE="/opt/kafka/config/server${NODE_ID}.properties"
if [ "$NODE_ID" = "1" ]; then
    CONFIG_FILE="/opt/kafka/config/server.properties"
fi

# ===============================================
# 启动信息输出
# 作用：输出启动信息，便于调试和监控
# 原理：显示节点ID和使用的配置文件路径
# 重要性：在容器日志中提供清晰的启动信息
# ===============================================

echo "Starting Kafka node $NODE_ID with config $CONFIG_FILE..."

# ===============================================
# ClusterId一致性检查
# 作用：检测并修复Kafka本地clusterId与ZooKeeper不一致的问题
# 原理：ZooKeeper数据重置后，Kafka本地meta.properties中的clusterId会与ZooKeeper不一致
#       导致InconsistentClusterIdException，Kafka无法启动
# 修复方式：删除本地meta.properties文件，让Kafka重新从ZooKeeper获取clusterId
# ===============================================

LOG_DIR=$(grep "^log.dirs=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2)
if [ -z "$LOG_DIR" ]; then
    LOG_DIR="/opt/kafka/data"
fi

META_FILE="$LOG_DIR/meta.properties"
if [ -f "$META_FILE" ]; then
    echo "检测到Kafka meta.properties文件: $META_FILE"
    
    ZK_CONNECT=$(grep "^zookeeper.connect=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2)
    if [ -n "$ZK_CONNECT" ]; then
        FIRST_ZK=$(echo "$ZK_CONNECT" | cut -d',' -f1)
        ZK_HOST=$(echo "$FIRST_ZK" | cut -d':' -f1)
        ZK_PORT=$(echo "$FIRST_ZK" | cut -d':' -f2 | cut -d'/' -f1)
        
        ZK_AVAILABLE=false
        for i in $(seq 1 10); do
            if bash -c "echo > /dev/tcp/$ZK_HOST/$ZK_PORT" 2>/dev/null; then
                ZK_AVAILABLE=true
                break
            fi
            echo "等待ZooKeeper连接... (尝试 $i/10)"
            sleep 2
        done
        
        if [ "$ZK_AVAILABLE" = true ]; then
            LOCAL_CLUSTER_ID=$(grep "^cluster.id=" "$META_FILE" 2>/dev/null | cut -d'=' -f2)
            ZK_CLUSTER_ID=$(echo "get /cluster/id" | /opt/kafka/bin/zookeeper-shell.sh "$ZK_CONNECT" 2>/dev/null | grep -o '"id" : "[^"]*"' | head -1 | cut -d'"' -f4)
            
            if [ -n "$LOCAL_CLUSTER_ID" ] && [ -n "$ZK_CLUSTER_ID" ] && [ "$LOCAL_CLUSTER_ID" != "$ZK_CLUSTER_ID" ]; then
                echo "ClusterId不一致! 本地: $LOCAL_CLUSTER_ID, ZooKeeper: $ZK_CLUSTER_ID"
                echo "删除本地meta.properties，让Kafka重新注册..."
                rm -f "$META_FILE"
            else
                echo "ClusterId一致性检查通过"
            fi
        else
            echo "ZooKeeper不可用，为安全起见删除meta.properties"
            rm -f "$META_FILE"
        fi
    fi
fi

# Start Kafka
exec /opt/kafka/bin/kafka-server-start.sh "$CONFIG_FILE"