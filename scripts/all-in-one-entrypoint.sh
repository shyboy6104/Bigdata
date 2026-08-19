#!/bin/bash

# ===============================================
# 5节点全栈集群统一启动脚本
# 作用：根据节点角色启动相应的大数据组件服务
# 原理：通过环境变量判断节点类型，启动对应的服务组合
# 节点类型：master, worker-1, worker-2, worker-3, infra
# 架构：5节点标准集群模式（不支持HA，专注于性能和稳定性）
# ===============================================

set -e

# ===============================================
# 环境配置文件读取
# ===============================================

if [ -f "/config/all-in-one/environment.conf" ]; then
    source /config/all-in-one/environment.conf
fi

# ===============================================
# 环境变量和路径设置
# ===============================================

export HADOOP_HOME=/opt/hadoop
export HIVE_HOME=/opt/hive
export HBASE_HOME=/opt/hbase
export ZOOKEEPER_HOME=/opt/zookeeper
export KAFKA_HOME=/opt/kafka
export SPARK_HOME=/opt/spark
export FLINK_HOME=/opt/flink
export FLUME_HOME=/opt/flume

export HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop
export HIVE_CONF_DIR=$HIVE_HOME/conf
export HBASE_CONF_DIR=$HBASE_HOME/conf
export ZOOKEEPER_CONF_DIR=$ZOOKEEPER_HOME/conf
export KAFKA_CONF_DIR=$KAFKA_HOME/config
export SPARK_CONF_DIR=$SPARK_HOME/conf
export FLINK_CONF_DIR=$FLINK_HOME/conf
export FLUME_CONF_DIR=$FLUME_HOME/conf

export PATH=$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$HIVE_HOME/bin:$HBASE_HOME/bin:$ZOOKEEPER_HOME/bin:$KAFKA_HOME/bin:$SPARK_HOME/bin:$FLINK_HOME/bin:$FLUME_HOME/bin

export HADOOP_CLASSPATH=$HADOOP_HOME/etc/hadoop:$HADOOP_HOME/share/hadoop/common/lib/*:$HADOOP_HOME/share/hadoop/common/*:$HADOOP_HOME/share/hadoop/hdfs/lib/*:$HADOOP_HOME/share/hadoop/hdfs/*:$HADOOP_HOME/share/hadoop/mapreduce/lib/*:$HADOOP_HOME/share/hadoop/mapreduce/*:$HADOOP_HOME/share/hadoop/yarn/lib/*:$HADOOP_HOME/share/hadoop/yarn/*

# ===============================================
# 内存优化配置
# ===============================================

export HADOOP_HEAPSIZE=${HADOOP_HEAPSIZE:-512}
export HADOOP_NAMENODE_OPTS="${HADOOP_NAMENODE_OPTS:--Xmx512m}"
export HADOOP_DATANODE_OPTS="${HADOOP_DATANODE_OPTS:--Xmx256m}"
export YARN_RESOURCEMANAGER_HEAPSIZE=${YARN_RESOURCEMANAGER_HEAPSIZE:-512}
export YARN_NODEMANAGER_HEAPSIZE=${YARN_NODEMANAGER_HEAPSIZE:-512}

export HBASE_MASTER_OPTS="${HBASE_MASTER_OPTS:--Xmx512m}"
export HBASE_REGIONSERVER_OPTS="${HBASE_REGIONSERVER_OPTS:--Xmx1024m}"

export SERVER_JVMFLAGS="${SERVER_JVMFLAGS:--Xmx128m}"

export KAFKA_HEAP_OPTS="${KAFKA_HEAP_OPTS:--Xmx512m -Xms512m}"

export HIVE_METASTORE_HEAPSIZE=${HIVE_METASTORE_HEAPSIZE:-512}
export HIVE_SERVER2_HEAPSIZE=${HIVE_SERVER2_HEAPSIZE:-1024}

export SPARK_DAEMON_MEMORY=${SPARK_DAEMON_MEMORY:-512m}
export SPARK_DRIVER_MEMORY=${SPARK_DRIVER_MEMORY:-512m}
export SPARK_EXECUTOR_MEMORY=${SPARK_EXECUTOR_MEMORY:-512m}
export SPARK_WORKER_MEMORY=${SPARK_WORKER_MEMORY:-512m}

export JOBMANAGER_MEMORY_PROCESS_SIZE=${JOBMANAGER_MEMORY_PROCESS_SIZE:-512m}
export TASKMANAGER_MEMORY_PROCESS_SIZE=${TASKMANAGER_MEMORY_PROCESS_SIZE:-512m}

# ===============================================
# 节点角色判断
# ===============================================

NODE_TYPE=$(hostname)
echo "=========================================="
echo "  5节点大数据集群启动脚本"
echo "  当前节点: $NODE_TYPE"
echo "  启动时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=========================================="

# ===============================================
# 配置复制函数
# ===============================================

copy_configs() {
    local component=$1
    local config_dir=$2

    if [ -d "/config/all-in-one/$component" ]; then
        echo "复制 $component 配置文件到 $config_dir ..."
        cp -r /config/all-in-one/$component/* $config_dir/
    fi
}

copy_supervisor_config() {
    local config_name=$1
    local src="/config/all-in-one/supervisor/${config_name}"
    local dst="/etc/supervisor/conf.d/${config_name}"

    if [ -f "$src" ]; then
        echo "复制Supervisor配置: $config_name"
        cp "$src" "$dst"
    else
        echo "警告: Supervisor配置文件不存在: $src"
    fi
}

# Compose 是五节点资源预算的权威入口。这里把环境变量渲染到
# Apache Flink 实际读取的 YAML，entrypoint 中的值仅作为缺省值。
set_flink_config() {
    local key=$1
    local value=$2
    local file="$FLINK_CONF_DIR/flink-conf.yaml"

    if grep -q "^${key}:" "$file"; then
        sed -i "s|^${key}:.*|${key}: ${value}|" "$file"
    else
        echo "${key}: ${value}" >> "$file"
    fi
}

apply_runtime_memory_config() {
    case "$NODE_TYPE" in
        "master")
            set_flink_config "jobmanager.memory.process.size" "$JOBMANAGER_MEMORY_PROCESS_SIZE"
            ;;
        "worker-1" | "worker-2" | "worker-3")
            set_flink_config "taskmanager.memory.process.size" "$TASKMANAGER_MEMORY_PROCESS_SIZE"
            ;;
    esac
}

# ===============================================
# 等待服务可用函数
# ===============================================

wait_for_port() {
    local host=$1
    local port=$2
    local max_wait=${3:-60}
    local waited=0
    echo "等待 $host:$port 可用..."
    while true; do
        if bash -c "echo > /dev/tcp/$host/$port" 2>/dev/null; then
            echo "$host:$port 已可用 (等待了 ${waited}s)"
            return 0
        fi
        if [ "$host" = "localhost" ]; then
            local local_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
            if [ -n "$local_ip" ] && bash -c "echo > /dev/tcp/$local_ip/$port" 2>/dev/null; then
                echo "$local_ip:$port 已可用 (等待了 ${waited}s)"
                return 0
            fi
            if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
                echo "端口 $port 已在监听 (等待了 ${waited}s)"
                return 0
            fi
        fi
        sleep 1
        waited=$((waited + 1))
        if [ $waited -ge $max_wait ]; then
            echo "警告: $host:$port 在 ${max_wait}s 内未可用，继续启动..."
            return 0
        fi
    done
}

# ===============================================
# HBase前台启动脚本生成函数
# 作用：动态生成hbase-foreground.sh脚本
# 原理：HBase start命令会fork后台进程，supervisor无法跟踪
#       生成wrapper脚本让HBase在前台运行
# ===============================================

generate_hbase_foreground() {
    local script_path="/opt/scripts/hbase-foreground.sh"

    mkdir -p /opt/scripts

    cat > "$script_path" << 'HBASE_EOF'
#!/bin/bash
COMPONENT=$1
shift

/opt/hbase/bin/hbase --config /opt/hbase/conf $COMPONENT start &

HBASE_PID=$!
echo "HBase $COMPONENT started with PID $HBASE_PID"

while kill -0 $HBASE_PID 2>/dev/null; do
    sleep 5
done

echo "HBase $COMPONENT process $HBASE_PID has exited"
exit 1
HBASE_EOF

    chmod +x "$script_path"
    echo "HBase前台启动脚本已生成: $script_path"
}

generate_health_monitor() {
    local check_interval=${HEALTH_CHECK_INTERVAL:-30}
    local max_restart_count=${MAX_RESTART_COUNT:-5}
    local script_path="/opt/scripts/health-monitor.sh"

    mkdir -p /opt/scripts /tmp/health-monitor

    cat > "$script_path" << 'HEALTH_EOF'
#!/bin/bash
CHECK_INTERVAL=${HEALTH_CHECK_INTERVAL:-30}
MAX_RESTART_COUNT=${MAX_RESTART_COUNT:-5}
LOG_FILE="/var/log/health-monitor.log"
RESTART_RECORD_DIR="/tmp/health-monitor"

mkdir -p "$RESTART_RECORD_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

check_port() {
    local host=$1
    local port=$2
    bash -c "echo > /dev/tcp/$host/$port" 2>/dev/null
    return $?
}

check_process() {
    local process_name=$1
    pgrep -f "$process_name" > /dev/null 2>&1
    return $?
}

restart_supervisor_service() {
    local service_name=$1
    local record_file="$RESTART_RECORD_DIR/${service_name}.restarts"

    local restart_count=0
    if [ -f "$record_file" ]; then
        restart_count=$(cat "$record_file" 2>/dev/null || echo "0")
    fi

    if [ "$restart_count" -ge "$MAX_RESTART_COUNT" ]; then
        local first_restart_time=$(stat -c %Y "$record_file" 2>/dev/null || echo "0")
        local current_time=$(date +%s)
        local elapsed=$((current_time - first_restart_time))

        if [ "$elapsed" -lt 3600 ]; then
            log "警告: $service_name 已达到最大重启次数 ($MAX_RESTART_COUNT)，跳过自动恢复"
            return 1
        else
            log "$service_name 重置重启计数器（距首次重启已超过1小时）"
            echo "0" > "$record_file"
            restart_count=0
        fi
    fi

    log "尝试重启Supervisor服务: $service_name"
    supervisorctl restart "$service_name" >> "$LOG_FILE" 2>&1

    if [ $? -eq 0 ]; then
        restart_count=$((restart_count + 1))
        echo "$restart_count" > "$record_file"
        log "$service_name 重启成功 (累计重启: $restart_count)"
    else
        log "错误: $service_name 重启失败"
    fi
}

check_zookeeper() {
    if check_process "zookeeper" || check_port "localhost" 2181; then return 0; fi
    log "ZooKeeper服务异常，尝试恢复..."
    restart_supervisor_service "zookeeper"
}

check_hdfs_namenode() {
    if check_port "master" 9000 || check_port "localhost" 9000; then return 0; fi
    log "HDFS NameNode服务异常，尝试恢复..."
    restart_supervisor_service "namenode"
}

check_hdfs_datanode() {
    if check_port "localhost" 9866; then return 0; fi
    log "HDFS DataNode服务异常，尝试恢复..."
    restart_supervisor_service "datanode"
}

check_yarn_rm() {
    if check_port "master" 8032 || check_port "localhost" 8032; then return 0; fi
    log "YARN ResourceManager服务异常，尝试恢复..."
    restart_supervisor_service "resourcemanager"
}

check_yarn_nm() {
    if check_port "localhost" 8042; then return 0; fi
    log "YARN NodeManager服务异常，尝试恢复..."
    restart_supervisor_service "nodemanager"
}

check_kafka() {
    if check_port "localhost" 9092; then return 0; fi
    log "Kafka Broker服务异常，尝试恢复..."
    restart_supervisor_service "kafka-broker"
}

check_hbase_master() {
    if check_process "org.apache.hadoop.hbase.master.HMaster" || check_port "$(hostname)" 16000; then return 0; fi
    log "HBase Master服务异常，尝试恢复..."
    restart_supervisor_service "hbase-master"
}

check_hbase_regionserver() {
    if check_process "org.apache.hadoop.hbase.regionserver.HRegionServer" || check_port "$(hostname)" 16020; then return 0; fi
    log "HBase RegionServer服务异常，尝试恢复..."
    restart_supervisor_service "hbase-regionserver"
}

check_hive_metastore() {
    if check_port "localhost" 9083; then return 0; fi
    log "Hive Metastore服务异常，尝试恢复..."
    restart_supervisor_service "hive-metastore"
}

check_hive_server2() {
    if check_port "localhost" 10000; then return 0; fi
    log "Hive Server2服务异常，尝试恢复..."
    restart_supervisor_service "hive-server2"
}

check_mysql() {
    if check_port "localhost" 3306; then return 0; fi
    log "MySQL服务异常，尝试恢复..."
    restart_supervisor_service "mysql"
}

check_flink_jobmanager() {
    if check_port "localhost" 8081; then return 0; fi
    log "Flink JobManager服务异常，尝试恢复..."
    restart_supervisor_service "flink-jobmanager"
}

check_flink_taskmanager() {
    # Flink 1.14 的 TaskManager RPC 端口可动态分配，不能用固定 6122 判断。
    if check_process "org.apache.flink.runtime.taskexecutor.TaskManagerRunner"; then return 0; fi
    log "Flink TaskManager服务异常，尝试恢复..."
    restart_supervisor_service "flink-taskmanager"
}

check_spark_master() {
    if check_port "localhost" 8080; then return 0; fi
    log "Spark Master服务异常，尝试恢复..."
    restart_supervisor_service "spark-master"
}

check_spark_worker() {
    if check_port "localhost" 8081; then return 0; fi
    log "Spark Worker服务异常，尝试恢复..."
    restart_supervisor_service "spark-worker"
}

run_health_checks() {
    local node_type=$(hostname)
    log "--- 健康检查开始 (节点: $node_type) ---"

    case "$node_type" in
        "master")
            check_hdfs_namenode
            check_yarn_rm
            check_hbase_master
            check_hive_metastore
            check_hive_server2
            check_flink_jobmanager
            check_spark_master
            ;;
        "worker-1" | "worker-2" | "worker-3")
            check_zookeeper
            check_hdfs_datanode
            check_yarn_nm
            check_kafka
            check_hbase_regionserver
            check_flink_taskmanager
            check_spark_worker
            ;;
        "infra")
            check_mysql
            ;;
    esac

    log "--- 健康检查完成 ---"
}

log "健康监控服务启动 (检查间隔: ${CHECK_INTERVAL}s, 最大重启次数: ${MAX_RESTART_COUNT})"

while true; do
    run_health_checks
    sleep "$CHECK_INTERVAL"
done
HEALTH_EOF

    chmod +x "$script_path"
    echo "健康监控脚本已生成: $script_path"
}

# ===============================================
# Kafka数据清理函数
# 作用：清理Kafka残留数据，避免集群ID不匹配
# ===============================================

clean_kafka_data() {
    echo "检查Kafka数据目录..."
    if [ -d "/opt/kafka/data" ] && [ "$(ls -A /opt/kafka/data 2>/dev/null)" ]; then
        local meta_file=$(find /opt/kafka/data -name "meta.properties" 2>/dev/null | head -1)
        if [ -n "$meta_file" ]; then
            echo "检测到Kafka残留数据，清理meta.properties以避免集群ID冲突..."
            rm -f "$meta_file"
        fi
    fi
    mkdir -p /opt/kafka/data
}

# ===============================================
# MySQL初始化函数
# 作用：初始化MySQL并创建Hive用户和数据库
# ===============================================

init_mysql() {
    echo "初始化MySQL服务..."

    if [ ! -d "/var/lib/mysql/mysql" ]; then
        echo "首次启动，初始化MySQL数据目录..."
        mysqld --initialize-insecure --user=mysql --datadir=/var/lib/mysql
    fi

    mkdir -p /var/run/mysqld
    chown mysql:mysql /var/run/mysqld

    echo "启动MySQL临时实例进行初始化..."
    mysqld --user=mysql --datadir=/var/lib/mysql --skip-networking &
    local mysql_pid=$!

    local waited=0
    while ! mysqladmin ping --silent 2>/dev/null; do
        sleep 1
        waited=$((waited + 1))
        if [ $waited -ge 30 ]; then
            echo "警告: MySQL启动超时"
            kill $mysql_pid 2>/dev/null
            return 1
        fi
    done
    echo "MySQL临时实例已启动"

    echo "创建Hive用户和数据库..."
    mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS hive_metastore DEFAULT CHARACTER SET latin1 COLLATE latin1_swedish_ci;
CREATE USER IF NOT EXISTS 'hive'@'%' IDENTIFIED BY 'hive';
GRANT ALL PRIVILEGES ON hive_metastore.* TO 'hive'@'%';
CREATE USER IF NOT EXISTS 'hive'@'localhost' IDENTIFIED BY 'hive';
GRANT ALL PRIVILEGES ON hive_metastore.* TO 'hive'@'localhost';
FLUSH PRIVILEGES;
EOF

    echo "MySQL初始化完成，停止临时实例..."
    mysqladmin -u root shutdown 2>/dev/null
    local shutdown_wait=0
    while kill -0 $mysql_pid 2>/dev/null; do
        sleep 1
        shutdown_wait=$((shutdown_wait + 1))
        if [ $shutdown_wait -ge 15 ]; then
            echo "强制终止MySQL进程..."
            kill -9 $mysql_pid 2>/dev/null
            break
        fi
    done
    echo "MySQL临时实例已停止"
}

# ===============================================
# Hive Metastore Schema初始化
# 作用：使用schematool预先初始化Metastore数据库schema
#       避免DataNucleus在运行时自动创建schema导致死锁
# ===============================================

init_hive_schema() {
    set +e

    if [ "$NODE_TYPE" != "master" ]; then
        return 0
    fi

    echo "检查Hive Metastore Schema初始化状态..."

    local schema_ver=$($HIVE_HOME/bin/schematool -dbType mysql -info 2>&1 | grep "Metastore schema version" | awk '{print $NF}')
    if [ -n "$schema_ver" ] && [ "$schema_ver" != "Unknown" ]; then
        echo "Hive Metastore Schema已初始化 (版本: $schema_ver)"
        return 0
    fi

    echo "Hive Metastore Schema未初始化，执行schematool -initSchema..."
    $HIVE_HOME/bin/schematool -dbType mysql -initSchema 2>&1
    local rc=$?
    if [ $rc -eq 0 ]; then
        echo "Hive Metastore Schema初始化成功"
    else
        echo "警告: Hive Metastore Schema初始化失败 (rc=$rc)，将在运行时自动创建"
    fi
}

# ===============================================
# ZooKeeper数据初始化
# ===============================================

init_zookeeper() {
    mkdir -p /opt/zookeeper/data /opt/zookeeper/datalog

    if [ "$NODE_TYPE" = "infra" ]; then
        echo "4" > /opt/zookeeper/data/myid
    elif [ "$NODE_TYPE" != "master" ]; then
        local worker_num=$(echo "$NODE_TYPE" | sed 's/worker-//')
        echo "$worker_num" > /opt/zookeeper/data/myid
    fi
}

# ===============================================
# HDFS路径一致性检查函数
# 作用：确保DataNode能够正确找到NameNode的数据目录
# ===============================================

check_hdfs_path_consistency() {
    echo "检查HDFS路径一致性..."
    
    # 确保数据目录存在
    mkdir -p /opt/hadoop/data
    
    # 检查NameNode数据目录路径
    local namenode_actual_path="/opt/hadoop/data/namenode"
    local namenode_expected_path="/opt/hadoop/data/dfs/name"
    
    if [ "$NODE_TYPE" = "master" ]; then
        echo "检查master节点HDFS路径..."
        
        # 如果实际路径存在但期望路径不存在，创建符号链接
        if [ -d "$namenode_actual_path" ] && [ ! -e "$namenode_expected_path" ]; then
            echo "创建NameNode路径符号链接: $namenode_expected_path -> $namenode_actual_path"
            mkdir -p /opt/hadoop/data/dfs
            ln -sf "$namenode_actual_path" "$namenode_expected_path"
            echo "✅ NameNode路径符号链接创建完成"
        elif [ -L "$namenode_expected_path" ]; then
            echo "✅ NameNode路径符号链接已存在"
        elif [ -d "$namenode_expected_path" ]; then
            echo "✅ NameNode路径目录已存在"
        else
            echo "⚠️ NameNode路径不存在，将在HDFS初始化时创建"
        fi
    fi
    
    # 检查DataNode数据目录
    local datanode_path="/opt/hadoop/data/datanode"
    if [ "$NODE_TYPE" != "master" ] && [ "$NODE_TYPE" != "infra" ]; then
        echo "检查$NODE_TYPE节点DataNode路径..."
        
        if [ ! -d "$datanode_path" ]; then
            echo "创建DataNode数据目录: $datanode_path"
            mkdir -p "$datanode_path"
        else
            echo "✅ DataNode数据目录已存在: $datanode_path"
        fi
    fi
    
    echo "HDFS路径一致性检查完成"
}

# ===============================================
# 增强的HDFS初始化函数
# 作用：自动检测和修复集群ID不匹配问题
# ===============================================

init_hdfs_enhanced() {
    check_hdfs_path_consistency
    
    if [ "$NODE_TYPE" = "master" ]; then
        echo "检查HDFS NameNode初始化状态..."
        
        if [ ! -d "/opt/hadoop/data/namenode/current" ]; then
            echo "首次启动，格式化HDFS NameNode..."
            $HADOOP_HOME/bin/hdfs namenode -format -force -nonInteractive
            echo "✅ HDFS NameNode格式化完成"
            rm -f /opt/hadoop/data/namenode/in_use.lock /opt/hadoop/data/edits/in_use.lock 2>/dev/null
            rm -f /tmp/hadoop-*-namenode.pid 2>/dev/null
        else
            echo "✅ NameNode已格式化，无需重新格式化"
        fi
    fi
    
    mkdir -p /opt/hadoop/data
}

check_datanode_clusterid() {
    set +e
    echo "检查DataNode集群ID与NameNode是否一致..."
    
    check_hdfs_path_consistency
    
    wait_for_port "master" 9000 120
    
    local namenode_clusterid=""
    namenode_clusterid=$($HADOOP_HOME/bin/hdfs dfsadmin -report 2>/dev/null | grep "Cluster ID" | head -1 | awk '{print $NF}')
    
    if [ -z "$namenode_clusterid" ]; then
        echo "⚠️ 无法通过HDFS命令获取集群ID，尝试其他方式..."
        namenode_clusterid=$($HADOOP_HOME/bin/hdfs getconf -confKey dfs.namenode.name.dir 2>/dev/null)
    fi
    
    if [ -d "/opt/hadoop/data/datanode/current" ]; then
        local datanode_clusterid=""
        if [ -f "/opt/hadoop/data/datanode/current/VERSION" ]; then
            datanode_clusterid=$(grep "clusterID" /opt/hadoop/data/datanode/current/VERSION | cut -d'=' -f2)
            echo "本地DataNode集群ID: $datanode_clusterid"
        fi
        
        if [ -n "$datanode_clusterid" ]; then
            if [ -n "$namenode_clusterid" ] && [ "$namenode_clusterid" != "$datanode_clusterid" ]; then
                echo "⚠️ 检测到集群ID不匹配: NameNode($namenode_clusterid) != DataNode($datanode_clusterid)"
                echo "清理DataNode数据目录并重新初始化..."
                rm -rf /opt/hadoop/data/datanode/*
                echo "✅ DataNode数据清理完成"
            else
                echo "✅ 集群ID一致，DataNode可以正常启动"
            fi
        else
            echo "⚠️ DataNode VERSION文件中无集群ID，清理数据目录..."
            rm -rf /opt/hadoop/data/datanode/*
        fi
    else
        echo "✅ DataNode目录不存在，无需清理"
    fi
}

# ===============================================
# HBase初始化函数
# 作用：在HBase启动前检测并清理ZooKeeper和HDFS中的残留数据
# 原理：ZooKeeper中残留的/hbase节点会导致meta表分配信息混乱
#       使HBase Master无法完成初始化（hbase:meta is NOT online）
#       需要确保ZooKeeper和HDFS中的HBase数据一致
# 策略：检测HBase是否已完成首次初始化（meta表在线）
#       如果未完成初始化且存在残留数据，则彻底清理后重新初始化
# ===============================================

zk_cmd() {
    local zk_server=$1
    shift
    $ZOOKEEPER_HOME/bin/zkCli.sh -server "$zk_server" <<ZKEOF 2>/dev/null
$@
quit
ZKEOF
}

init_hbase_master() {
    set +e
    echo "检查HBase Master初始化状态..."
    
    if [ "$NODE_TYPE" != "master" ]; then
        return 0
    fi
    
    supervisorctl stop hbase-master 2>/dev/null || true
    sleep 3
    
    local hbase_initialized=false
    local zk_hbase_exists=false
    local hdfs_hbase_exists=false
    local local_hbase_exists=false
    
    local zk_ls_root=$(zk_cmd worker-1:2181 "ls /" 2>/dev/null | grep "^\[.*\]$" | tail -1)
    if echo "$zk_ls_root" | grep -q "hbase"; then
        zk_hbase_exists=true
        echo "检测到ZooKeeper中/hbase节点存在"
        
        local zk_ls_meta=$(zk_cmd worker-1:2181 "ls /hbase" 2>/dev/null | grep "^\[.*\]$" | tail -1)
        if echo "$zk_ls_meta" | grep -q "meta"; then
            hbase_initialized=true
            echo "检测到ZooKeeper中/hbase/meta节点存在，HBase可能已初始化"
        fi
    fi
    
    if $HADOOP_HOME/bin/hdfs dfs -test -d /hbase 2>/dev/null; then
        hdfs_hbase_exists=true
        echo "检测到HDFS上/hbase目录存在"
    fi
    
    if [ -d "/opt/hbase/data" ] && ls /opt/hbase/data/ 2>/dev/null | grep -q .; then
        local_hbase_exists=true
        echo "检测到本地HBase数据目录非空"
    fi
    
    if [ "$hbase_initialized" = true ]; then
        echo "✅ HBase已完成初始化，尝试正常启动"
        supervisorctl start hbase-master
        return 0
    fi
    
    if [ "$zk_hbase_exists" = true ] || [ "$hdfs_hbase_exists" = true ] || [ "$local_hbase_exists" = true ]; then
        echo "⚠️ 检测到HBase残留数据但meta表未初始化，需要彻底清理"
        echo "   原因：残留数据会导致meta表分配信息混乱，使HBase Master无法完成初始化"
        
        echo "1. 清理ZooKeeper中的/hbase节点..."
        for zk_server in worker-1:2181 worker-2:2181 worker-3:2181; do
            zk_cmd "$zk_server" "deleteall /hbase" 2>/dev/null || true
        done
        
        echo "2. 清理HDFS上的/hbase目录..."
        $HADOOP_HOME/bin/hdfs dfs -rm -r -skipTrash /hbase 2>/dev/null || true
        $HADOOP_HOME/bin/hdfs dfs -rm -r -skipTrash /tmp/hbase 2>/dev/null || true
        
        if $HADOOP_HOME/bin/hdfs dfs -test -d /hbase 2>/dev/null; then
            echo "HDFS常规删除失败，尝试通过NameNode直接删除..."
            $HADOOP_HOME/bin/hdfs dfs -rm -r -f -skipTrash /hbase 2>/dev/null || true
        fi
        
        if $HADOOP_HOME/bin/hdfs dfs -test -d /hbase 2>/dev/null; then
            echo "警告: HDFS /hbase目录仍存在，可能包含损坏的block"
            echo "尝试删除/hbase下的所有文件和目录..."
            $HADOOP_HOME/bin/hdfs dfs -ls /hbase 2>/dev/null | grep -oE '/hbase/[^ ]+' | while read path; do
                $HADOOP_HOME/bin/hdfs dfs -rm -r -skipTrash "$path" 2>/dev/null || true
            done
            $HADOOP_HOME/bin/hdfs dfs -rm -r -skipTrash /hbase 2>/dev/null || true
        fi
        
        echo "3. 清理Master节点本地HBase数据..."
        rm -rf /opt/hbase/data/* /opt/hbase/WALs/* /opt/hbase/oldWALs/* 2>/dev/null || true
        mkdir -p /opt/hbase/data /opt/hbase/WALs /opt/hbase/oldWALs
        
        echo "✅ HBase残留数据清理完成，将进行全新初始化"
    else
        echo "✅ 未检测到HBase残留数据，将进行全新初始化"
        mkdir -p /opt/hbase/data /opt/hbase/WALs /opt/hbase/oldWALs
    fi
    
    echo "启动HBase Master..."
    supervisorctl start hbase-master
}

init_hbase_regionserver() {
    set +e
    echo "检查HBase RegionServer初始化状态..."
    
    if [ "$NODE_TYPE" = "master" ] || [ "$NODE_TYPE" = "infra" ]; then
        return 0
    fi
    
    supervisorctl stop hbase-regionserver 2>/dev/null || true
    sleep 2
    
    local zk_hbase_exists=false
    local zk_ls_root=$(zk_cmd localhost:2181 "ls /" 2>/dev/null | grep "^\[.*\]$" | tail -1)
    if echo "$zk_ls_root" | grep -q "hbase"; then
        zk_hbase_exists=true
    fi
    
    if [ "$zk_hbase_exists" = false ]; then
        echo "⚠️ ZooKeeper中无/hbase节点，清理本地HBase数据..."
        rm -rf /opt/hbase/data/* /opt/hbase/WALs/* /opt/hbase/oldWALs/* 2>/dev/null || true
        mkdir -p /opt/hbase/data /opt/hbase/WALs /opt/hbase/oldWALs
        echo "✅ 本地HBase数据已清理"
    else
        echo "✅ ZooKeeper中存在/hbase节点，保留本地数据"
    fi
    
    echo "启动HBase RegionServer..."
    supervisorctl start hbase-regionserver
}

# ===============================================
# Kafka Broker配置动态生成
# ===============================================

configure_kafka() {
    local broker_id=$1
    local advertised_host=$2

    if [ -f "/opt/kafka/config/server.properties" ]; then
        sed -i "s/^broker.id=.*/broker.id=${broker_id}/" /opt/kafka/config/server.properties
        sed -i "s/^advertised.listeners=.*/advertised.listeners=PLAINTEXT:\/\/${advertised_host}:9092/" /opt/kafka/config/server.properties
    fi
}

# ===============================================
# 服务启动顺序控制函数
# 作用：按照依赖关系顺序启动服务
# ===============================================

start_services_sequentially() {
    local node_type=$1
    
    set +e
    
    echo "开始按依赖顺序启动服务 (节点: $node_type)..."
    
    case "$node_type" in
        "master")
            echo "1. 清理残留pid文件..."
            rm -f /tmp/hadoop-*-namenode.pid /tmp/hadoop-*-resourcemanager.pid 2>/dev/null
            
            echo "2. 启动Hadoop基础服务..."
            supervisorctl start namenode
            wait_for_port "localhost" 9000 120
            
            echo "3. 启动YARN资源管理..."
            supervisorctl start resourcemanager
            wait_for_port "localhost" 8032 60
            
            echo "3.5. 等待HDFS安全模式退出..."
            local safemode_wait=0
            local safemode_max=180
            while [ $safemode_wait -lt $safemode_max ]; do
                local safemode_status=$($HADOOP_HOME/bin/hdfs dfsadmin -safemode get 2>/dev/null | grep -o "ON\|OFF" | head -1)
                if [ "$safemode_status" = "OFF" ]; then
                    echo "HDFS安全模式已退出 (等待了 ${safemode_wait}s)"
                    break
                fi
                local dn_count=$($HADOOP_HOME/bin/hdfs dfsadmin -report 2>/dev/null | grep "Live datanodes" | grep -o "[0-9]*" | head -1)
                if [ -n "$dn_count" ] && [ "$dn_count" -ge 3 ]; then
                    echo "检测到 $dn_count 个DataNode已上线，主动离开安全模式..."
                    $HADOOP_HOME/bin/hdfs dfsadmin -safemode leave 2>/dev/null
                    sleep 3
                fi
                echo "HDFS仍在安全模式中... (${safemode_wait}s)"
                sleep 5
                safemode_wait=$((safemode_wait + 5))
            done
            if [ $safemode_wait -ge $safemode_max ]; then
                echo "警告: HDFS安全模式等待超时，强制离开安全模式..."
                $HADOOP_HOME/bin/hdfs dfsadmin -safemode leave 2>/dev/null
            fi
            
            echo "4. 等待MySQL就绪 (infra节点)..."
            wait_for_port "infra" 3306 120
            
            echo "4. 初始化Hive Metastore Schema..."
            init_hive_schema
            
            echo "4.5. 启动Hive Metastore..."
            supervisorctl start hive-metastore
            wait_for_port "localhost" 9083 90
            
            echo "5. 启动Hive Server2..."
            supervisorctl start hive-server2
            wait_for_port "localhost" 10000 90
            
            echo "6. 等待ZooKeeper集群就绪..."
            wait_for_port "worker-1" 2181 120
            wait_for_port "worker-2" 2181 60
            wait_for_port "worker-3" 2181 60
            
            echo "7. 检查HBase数据一致性并启动HBase Master..."
            init_hbase_master
            wait_for_port "localhost" 16000 90
            
            echo "8. 启动Spark Master..."
            mkdir -p /opt/spark/data/event-logs
            supervisorctl start spark-master
            wait_for_port "localhost" 8080 30
            
            echo "9. 启动Flink JobManager..."
            mkdir -p /opt/flink/checkpoints /opt/flink/savepoints
            supervisorctl start flink-jobmanager
            wait_for_port "localhost" 8081 30
            
            echo "10. 启动健康监控服务..."
            supervisorctl start health-monitor
            
            echo "✅ Master节点所有服务启动完成"
            ;;
            
        "worker-1" | "worker-2" | "worker-3")
            echo "1. 清理残留pid文件..."
            rm -f /tmp/hadoop-*-datanode.pid /tmp/hadoop-*-nodemanager.pid /tmp/zookeeper*.pid 2>/dev/null
            
            echo "2. 启动ZooKeeper (分布式协调基础)..."
            supervisorctl start zookeeper
            wait_for_port "localhost" 2181 60
            
            echo "2. 等待HDFS NameNode就绪..."
            wait_for_port "master" 9000 120
            
            echo "3. 检查DataNode集群ID一致性..."
            check_datanode_clusterid
            
            echo "4. 启动HDFS DataNode..."
            supervisorctl start datanode
            wait_for_port "localhost" 9866 60
            
            echo "5. 启动YARN NodeManager..."
            supervisorctl start nodemanager
            wait_for_port "localhost" 8042 30
            
            echo "6. 启动Kafka Broker..."
            supervisorctl start kafka-broker
            wait_for_port "localhost" 9092 30
            
            echo "7. 等待ZooKeeper集群稳定..."
            wait_for_port "worker-1" 2181 30
            wait_for_port "worker-2" 2181 30
            wait_for_port "worker-3" 2181 30
            
            echo "8. 检查HBase RegionServer数据一致性并启动..."
            init_hbase_regionserver
            wait_for_port "localhost" 16020 60
            
            echo "10. 启动Spark Worker..."
            supervisorctl start spark-worker
            wait_for_port "localhost" 8081 30
            
            echo "11. 启动Flink TaskManager..."
            supervisorctl start flink-taskmanager
            wait_for_port "localhost" 6122 30
            
            echo "12. 启动健康监控服务..."
            supervisorctl start health-monitor
            
            echo "✅ Worker节点所有服务启动完成"
            ;;
            
        "infra")
            echo "1. 启动MySQL服务..."
            supervisorctl start mysql
            wait_for_port "localhost" 3306 60
            
            echo "2. 启动Flume Agent..."
            supervisorctl start flume-agent
            
            echo "3. 启动健康监控服务..."
            supervisorctl start health-monitor
            
            echo "✅ Infra节点所有服务启动完成"
            ;;
    esac
}

# ===============================================
# 增强的服务等待函数
# 作用：更智能地等待服务就绪，包含健康检查
# ===============================================

wait_for_service_healthy() {
    local service_name=$1
    local check_command=$2
    local max_wait=${3:-60}
    local waited=0
    
    echo "等待服务 $service_name 健康状态..."
    
    while true; do
        # 检查服务进程状态
        if supervisorctl status "$service_name" | grep -q "RUNNING"; then
            # 执行健康检查命令
            if eval "$check_command"; then
                echo "✅ 服务 $service_name 已健康 (等待了 ${waited}s)"
                return 0
            fi
        fi
        
        sleep 5
        waited=$((waited + 5))
        
        if [ $waited -ge $max_wait ]; then
            echo "⚠️ 警告: 服务 $service_name 在 ${max_wait}s 内未达到健康状态"
            return 1
        fi
        
        echo "服务 $service_name 仍在启动中... (${waited}s)"
    done
}

# ===============================================
# 主执行逻辑
# ===============================================

main() {
    echo "开始启动5节点全栈集群服务..."

    if [ -d "/config/all-in-one" ]; then
        mkdir -p $HADOOP_CONF_DIR $HIVE_CONF_DIR $HBASE_CONF_DIR \
                 $ZOOKEEPER_CONF_DIR $KAFKA_CONF_DIR $SPARK_CONF_DIR \
                 $FLINK_CONF_DIR $FLUME_CONF_DIR
    fi

    # 复制配置文件和初始化
    case "$NODE_TYPE" in
        "master")
            copy_configs "hadoop-master" "$HADOOP_CONF_DIR"
            copy_configs "hive" "$HIVE_CONF_DIR"
            copy_configs "hbase-master" "$HBASE_CONF_DIR"
            copy_configs "spark-master" "$SPARK_CONF_DIR"
            copy_configs "flink-master" "$FLINK_CONF_DIR"
            copy_supervisor_config "master-services.conf"
            generate_hbase_foreground
            generate_health_monitor
            init_hdfs_enhanced  # 使用增强的HDFS初始化函数
            ;;
        "worker-1" | "worker-2" | "worker-3")
            copy_configs "hadoop-worker" "$HADOOP_CONF_DIR"
            copy_configs "hbase-worker" "$HBASE_CONF_DIR"
            copy_configs "zookeeper" "$ZOOKEEPER_CONF_DIR"
            copy_configs "kafka" "$KAFKA_CONF_DIR"
            copy_configs "spark-worker" "$SPARK_CONF_DIR"
            copy_configs "flink-worker" "$FLINK_CONF_DIR"
            copy_supervisor_config "worker-services.conf"
            generate_hbase_foreground
            generate_health_monitor
            init_zookeeper
            local worker_num=$(echo "$NODE_TYPE" | sed 's/worker-//')
            clean_kafka_data
            configure_kafka "$worker_num" "$NODE_TYPE"
            ;;
        "infra")
            copy_configs "hadoop-worker" "$HADOOP_CONF_DIR"
            copy_configs "hive" "$HIVE_CONF_DIR"
            copy_configs "flume" "$FLUME_CONF_DIR"
            if [ -f "/config/all-in-one/mysql/my.cnf" ]; then
                echo "复制MySQL配置到系统目录..."
                cp /config/all-in-one/mysql/my.cnf /etc/mysql/my.cnf
                if [ -d "/etc/mysql/mysql.conf.d" ]; then
                    cp /config/all-in-one/mysql/my.cnf /etc/mysql/mysql.conf.d/custom.cnf
                fi
                if [ -d "/etc/mysql/conf.d" ]; then
                    cp /config/all-in-one/mysql/my.cnf /etc/mysql/conf.d/custom.cnf
                fi
            fi
            copy_supervisor_config "infra-services.conf"
            generate_health_monitor
            init_mysql
            ;;
        *)
            echo "未知节点类型: $NODE_TYPE"
            echo "支持的节点类型: master, worker-1, worker-2, worker-3, infra"
            exit 1
            ;;
    esac

    apply_runtime_memory_config

    echo "启动Supervisor进程管理器..."
    /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
    
    sleep 5
    
    start_services_sequentially "$NODE_TYPE"
    
    echo "✅ 集群启动流程完成，所有服务已按依赖顺序启动"
    echo "集群状态监控中..."
    
    while true; do
        if ! kill -0 $(cat /var/run/supervisord.pid 2>/dev/null) 2>/dev/null; then
            echo "⚠️ supervisord进程已退出，重新启动..."
            /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
            sleep 5
            start_services_sequentially "$NODE_TYPE"
        fi
        sleep 30
    done
}

# 执行主函数
main "$@"
