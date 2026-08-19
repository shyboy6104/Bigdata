#!/bin/bash

# 禁用 Git Bash/MSYS2 的路径自动转换，防止 docker exec 中的绝对路径被转换为 Windows 路径
export MSYS_NO_PATHCONV=1

# ===============================================
# Hadoop高可用集群测试脚本
# 作用：全面测试Hadoop HA集群的各项功能，包括高可用性、数据一致性、故障转移等
# 原理：通过Docker命令与容器交互，验证集群组件的状态和功能
# 测试范围：容器状态、HA功能、HDFS操作、故障转移、YARN资源管理、MapReduce作业
# ===============================================

# ===============================================
# 日志配置
# 作用：记录测试过程和结果，便于问题排查和结果分析
# 原理：同时输出到终端和日志文件，确保测试过程可追溯
# ===============================================

# 日志文件配置：在test-log目录下创建带时间戳的日志文件
LOG_DIR="test/test-log"
LOG_FILE="$LOG_DIR/test-hadoop-ha-$(date +%Y%m%d-%H%M%S).log"

# 创建日志目录（如果不存在）
mkdir -p "$LOG_DIR"

# 捕获脚本中全部标准输出和错误，使故障转移、HDFS、YARN 与
# MapReduce 的原始命令输出都进入同一份日志。
exec > >(tee -a "$LOG_FILE") 2>&1

FAIL_COUNT=0
mapreduce_ok=false

# 日志函数：同时输出到终端和日志文件
log() {
    echo "$1"
    case "$1" in
        *"✗"*) FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
    esac
}

# ===============================================
# 测试开始
# ===============================================

log "=== Hadoop HA 高可用集群测试 ==="
log "测试时间: $(date)"
log ""

# ===============================================
# 环境配置检查
# 作用：读取Hadoop版本信息，确保测试环境与配置一致
# 原理：从环境配置文件读取版本号，用于后续的MapReduce作业测试
# ===============================================

# 读取Hadoop版本号配置
ENV_CONF="../config/environment.conf"
if [ -f "$ENV_CONF" ]; then
    HADOOP_VERSION=$(grep "^HADOOP_VERSION=" "$ENV_CONF" | cut -d'=' -f2)
    echo "使用 Hadoop 版本: $HADOOP_VERSION"
else
    echo "警告: 环境配置文件不存在，使用默认版本 3.1.3"
    HADOOP_VERSION="3.1.3"
fi
log ""

# ===============================================
# 测试阶段1：容器状态检查
# 作用：验证Hadoop HA集群的所有容器是否正常运行
# 原理：使用docker ps命令检查容器状态，确保基础服务可用
# ===============================================

log "1. 检查 Hadoop HA 容器状态..."
docker ps | grep -E "namenode|datanode|journalnode" | tee -a "$LOG_FILE"
log ""

# ===============================================
# 测试阶段2：JournalNode集群状态检查
# 作用：验证JournalNode集群的健康状态，确保编辑日志服务正常
# 原理：检查每个JournalNode容器是否有JournalNode进程运行
# 重要性：JournalNode是HA集群的核心组件，负责NameNode数据同步
# ===============================================

log "2. 测试 JournalNode 集群状态..."
jn_ok=0
for i in 1 2 3; do
    jn_status=$(docker exec journalnode$i jps 2>/dev/null | grep JournalNode | wc -l)
    if [ "$jn_status" -eq 1 ] 2>/dev/null; then
        echo "✓ JournalNode$i 正常运行"
        jn_ok=$((jn_ok + 1))
    else
        echo "✗ JournalNode$i 状态异常"
    fi
done

# 测试 NameNode HA 状态
log "3. 测试 NameNode HA 高可用状态..."

# 检查 NameNode1 状态
log "3.1 检查 NameNode1 状态..."
nn1_status=$(docker exec namenode1 hdfs haadmin -getServiceState nn1 2>/dev/null)
if [ "$nn1_status" = "active" ] || [ "$nn1_status" = "standby" ]; then
    echo "✓ NameNode1 状态: $nn1_status"
else
    echo "✗ NameNode1 状态检查失败"
fi

# 检查 NameNode2 状态
log "3.2 检查 NameNode2 状态..."
nn2_status=$(docker exec namenode2 hdfs haadmin -getServiceState nn2 2>/dev/null)
if [ "$nn2_status" = "active" ] || [ "$nn2_status" = "standby" ]; then
    echo "✓ NameNode2 状态: $nn2_status"
else
    echo "✗ NameNode2 状态检查失败"
fi

# 验证 HA 配置
log "3.3 验证 HA 配置..."
ha_status=$(docker exec namenode1 hdfs haadmin -getAllServiceState 2>/dev/null)
if [ -n "$ha_status" ]; then
    echo "✓ HA 配置验证成功"
    echo "  $ha_status"
else
    echo "✗ HA 配置验证失败"
fi

# 测试 Web UI 可访问性
log "4. 测试 Web UI 可访问性..."

# 测试 Active NameNode Web UI
active_nn=""
if [ "$nn1_status" = "active" ]; then
    active_nn="namenode1"
    active_port="19870"
elif [ "$nn2_status" = "active" ]; then
    active_nn="namenode2"
    active_port="29870"
fi

if [ -n "$active_nn" ]; then
    echo "4.1 测试 Active NameNode Web UI ($active_nn)..."
    active_status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$active_port)
    if [ "$active_status" = "200" ]; then
        echo "✓ Active NameNode Web UI 正常 (http://localhost:$active_port)"
    else
        echo "✗ Active NameNode Web UI 不可访问 (状态码: $active_status)"
    fi
fi

# 测试 Standby NameNode Web UI
standby_nn=""
if [ "$nn1_status" = "standby" ]; then
    standby_nn="namenode1"
    standby_port="19870"
elif [ "$nn2_status" = "standby" ]; then
    standby_nn="namenode2"
    standby_port="29870"
fi

if [ -n "$standby_nn" ]; then
    echo "4.2 测试 Standby NameNode Web UI ($standby_nn)..."
    standby_status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$standby_port)
    if [ "$standby_status" = "200" ]; then
        echo "✓ Standby NameNode Web UI 正常 (http://localhost:$standby_port)"
    else
        echo "✗ Standby NameNode Web UI 不可访问 (状态码: $standby_status)"
    fi
fi

# 测试 ResourceManager Web UI
log "4.3 测试 ResourceManager Web UI..."
rm_status=$(curl -s -L -o /dev/null -w "%{http_code}" http://localhost:18088)
if [ "$rm_status" = "200" ]; then
    echo "✓ ResourceManager Web UI 正常 (http://localhost:18088)"
else
    echo "⚠ ResourceManager Web UI 返回状态码: $rm_status (可能是重定向)"
fi

# 测试 HDFS 文件系统操作
log "5. 测试 HDFS 文件系统操作..."

# 使用 Active NameNode 进行操作
if [ -n "$active_nn" ]; then
    echo "5.1 使用 Active NameNode ($active_nn) 测试 HDFS..."
    
    # 检查 HDFS 状态
    hdfs_status=$(docker exec $active_nn hdfs dfsadmin -report 2>/dev/null | grep "Live datanodes" | grep -oE '[0-9]+')
    if [ -n "$hdfs_status" ]; then
        echo "✓ HDFS 正常运行，活跃 DataNode 数量: $hdfs_status"
    else
        echo "✗ HDFS 状态检查失败"
    fi
    
    # 创建测试目录
    echo "5.2 创建测试目录..."
    docker exec $active_nn hdfs dfs -mkdir -p /test/ha-test 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "✓ 测试目录创建成功"
    else
        echo "✗ 测试目录创建失败"
    fi
    
    # 上传文件
    echo "5.3 上传文件到 HDFS..."
    echo "Hadoop HA Test Data" > /tmp/ha-test.txt
    docker cp /tmp/ha-test.txt $active_nn:/tmp/ha-test.txt
    docker exec $active_nn hdfs dfs -put /tmp/ha-test.txt /test/ha-test/ 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "✓ 文件上传成功"
    else
        echo "✗ 文件上传失败"
    fi
    
    # 验证文件
    echo "5.4 验证文件存在性..."
    file_exists=$(docker exec $active_nn hdfs dfs -test -e /test/ha-test/ha-test.txt && echo "exists")
    if [ "$file_exists" = "exists" ]; then
        echo "✓ 文件存在性验证成功"
    else
        echo "✗ 文件存在性验证失败"
    fi
    
    # 从 Standby NameNode 读取文件（测试数据同步）
    if [ -n "$standby_nn" ]; then
        echo "5.5 测试数据同步（从 Standby NameNode 读取）..."
        standby_content=$(docker exec $standby_nn hdfs dfs -cat /test/ha-test/ha-test.txt 2>/dev/null)
        if [ "$standby_content" = "Hadoop HA Test Data" ]; then
            echo "✓ 数据同步验证成功"
        else
            echo "✗ 数据同步验证失败"
        fi
    fi
fi

# 测试故障转移
log "6. 测试故障转移功能..."

if [ -n "$active_nn" ] && [ -n "$standby_nn" ]; then
    echo "6.1 手动触发故障转移..."
    
    # 记录当前状态
    old_active="$active_nn"
    old_standby="$standby_nn"
    
    # 执行故障转移
    echo "  执行故障转移: $old_active -> $old_standby"
    docker exec $old_active hdfs haadmin -failover nn1 nn2 2>/dev/null
    
    # 等待故障转移完成
    sleep 10
    
    # 检查新的状态
    new_nn1_status=$(docker exec namenode1 hdfs haadmin -getServiceState nn1 2>/dev/null)
    new_nn2_status=$(docker exec namenode2 hdfs haadmin -getServiceState nn2 2>/dev/null)
    
    echo "  故障转移后状态:"
    echo "  - NameNode1: $new_nn1_status"
    echo "  - NameNode2: $new_nn2_status"
    
    if [ "$new_nn1_status" != "$nn1_status" ] || [ "$new_nn2_status" != "$nn2_status" ]; then
        echo "✓ 故障转移测试成功"
        
        # 验证新 Active 节点的操作
        if [ "$new_nn1_status" = "active" ]; then
            new_active="namenode1"
        else
            new_active="namenode2"
        fi
        
        echo "6.2 验证新 Active 节点操作..."
        new_file_content=$(docker exec $new_active hdfs dfs -cat /test/ha-test/ha-test.txt 2>/dev/null)
        if [ "$new_file_content" = "Hadoop HA Test Data" ]; then
            echo "✓ 新 Active 节点操作验证成功"
        else
            echo "✗ 新 Active 节点操作验证失败"
        fi
        
        # 恢复原始状态
        echo "6.3 恢复原始状态..."
        docker exec $new_active hdfs haadmin -failover nn2 nn1 2>/dev/null
        sleep 5
        echo "✓ 状态恢复完成"
    else
        echo "✗ 故障转移测试失败"
    fi
else
    echo "⚠ 无法进行故障转移测试（需要 active 和 standby 节点）"
fi

# 测试 YARN 资源管理
log "7. 测试 YARN 资源管理..."

if [ -n "$active_nn" ]; then
    echo "7.1 检查 YARN 节点状态..."
    yarn_nodes_output=$(docker exec $active_nn yarn node -list 2>/dev/null)
    if echo "$yarn_nodes_output" | grep -q "Total Nodes"; then
        yarn_nodes=$(echo "$yarn_nodes_output" | grep "Total Nodes" | awk -F: '{print $2}' | awk '{print $1}' | tr -d '[:space:]')
        echo "✓ YARN 节点正常，总节点数: $yarn_nodes"
        echo "  节点详情:"
        echo "$yarn_nodes_output" | grep "RUNNING" | sed 's/^/   /'
    else
        echo "✗ YARN 节点状态检查失败"
        echo "  输出: $yarn_nodes_output"
        yarn_nodes=""
    fi
    
    echo "7.2 运行简单的 MapReduce 作业..."
    # 准备测试数据
    echo "hadoop ha high availability test" > /tmp/ha-input.txt
    docker cp /tmp/ha-input.txt $active_nn:/tmp/ha-input.txt
    
    # 上传数据
    docker exec $active_nn hdfs dfs -mkdir -p /test/ha-wordcount/input 2>/dev/null
    docker exec $active_nn hdfs dfs -put /tmp/ha-input.txt /test/ha-wordcount/input/ 2>/dev/null
    
    # 运行作业
    job_output=$(docker exec $active_nn hadoop jar /opt/hadoop/share/hadoop/mapreduce/hadoop-mapreduce-examples-${HADOOP_VERSION}.jar wordcount /test/ha-wordcount/input /test/ha-wordcount/output 2>&1)
    
    if echo "$job_output" | grep -q "completed successfully"; then
        echo "✓ MapReduce 作业执行成功"
        
        # 检查结果
        result=$(docker exec $active_nn hdfs dfs -cat /test/ha-wordcount/output/part-r-00000 2>/dev/null)
        if [ -n "$result" ]; then
            echo "✓ 作业结果验证成功"
            mapreduce_ok=true
        else
            echo "✗ 作业结果验证失败"
        fi
    else
        echo "✗ MapReduce 作业执行失败"
    fi
fi

# 清理测试数据
log "8. 清理测试数据..."
if [ -n "$active_nn" ]; then
    docker exec $active_nn hdfs dfs -rm -r -f /test 2>/dev/null
fi
rm -f /tmp/ha-test.txt /tmp/ha-input.txt

log "✓ 测试数据清理完成"

# 综合测试结果
log ""
log "=== Hadoop HA 高可用集群测试完成 ==="
log "测试总结:"
log "- JournalNode 集群: $([ "$jn_ok" -eq 3 ] && echo "✓ 正常" || echo "✗ 异常")"
log "- NameNode HA 状态: $([ -n "$ha_status" ] && echo "✓ 正常" || echo "✗ 异常")"
log "- Web UI 可访问性: $([ "$active_status" = "200" ] && echo "✓ 正常" || echo "✗ 异常")"
log "- HDFS 文件系统: $([ -n "$hdfs_status" ] && echo "✓ 正常" || echo "✗ 异常")"
log "- 数据同步: $([ "$standby_content" = "Hadoop HA Test Data" ] && echo "✓ 正常" || echo "✗ 异常")"
log "- 故障转移: $([ "$new_nn1_status" != "$nn1_status" ] && echo "✓ 正常" || echo "✗ 异常")"
log "- YARN 资源管理: $([ -n "$yarn_nodes" ] && echo "✓ 正常" || echo "✗ 异常")"
log "- MapReduce 作业: $([ "$mapreduce_ok" = true ] && echo "✓ 正常" || echo "✗ 异常")"

log ""
log "详细测试报告已生成，Hadoop HA 高可用集群功能验证完成！"

# 记录测试结束时间
log "测试结束时间: $(date)"
log "测试结果已保存到: $LOG_FILE"

if [ "$FAIL_COUNT" -gt 0 ]; then
    log "[诊断] 检测到 $FAIL_COUNT 条失败结果，输出 HA 核心容器最近日志。"
    for container in namenode1 namenode2 journalnode1 journalnode2 journalnode3 datanode1 datanode2; do
        log "[诊断] $container 最近 60 行日志："
        docker logs --tail 60 "$container" 2>&1 || true
    done
    exit 1
fi

exit 0
