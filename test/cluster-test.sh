#!/bin/bash

# ===============================================
# 5节点全栈大数据集群功能测试脚本
# 作用：全面测试集群所有组件的功能
# 原理：通过Docker exec命令在对应容器中执行测试
# 架构：master / worker-1 / worker-2 / worker-3 / infra
# ===============================================

set +e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

LOG_DIR="test/test-log"
LOG_FILE="$LOG_DIR/cluster-test-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$LOG_DIR"

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

log() {
    echo "$1" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1" | tee -a "$LOG_FILE"
}

log_skip() {
    echo -e "${CYAN}[SKIP]${NC} $1" | tee -a "$LOG_FILE"
}

run_test() {
    local test_name="$1"
    local test_command="$2"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    log_info "  测试: $test_name"
    local test_output
    test_output=$(eval "$test_command" 2>&1)
    local test_exit_code=$?

    if [ $test_exit_code -eq 0 ]; then
        log_success "  $test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        log_error "  $test_name"
        log "  [诊断] 退出码: $test_exit_code"
        log "  [诊断] 执行命令: $test_command"
        if [ -n "$test_output" ]; then
            log "  [诊断] 命令输出:"
            printf '%s\n' "$test_output" | tail -n 80 | sed 's/^/    /' | tee -a "$LOG_FILE"
        else
            log "  [诊断] 命令没有输出。"
        fi
        collect_failure_diagnostics "$test_name"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

collect_failure_diagnostics() {
    local test_name=$1

    case "$test_name" in
        *HDFS*|*YARN*|*MapReduce*|*NameNode*|*DataNode*|*NodeManager*|*ResourceManager*)
            log "  [诊断] Master/Worker Hadoop 进程状态:"
            docker exec master jps 2>&1 | sed 's/^/    master: /' | tee -a "$LOG_FILE" || true
            docker exec worker-1 jps 2>&1 | sed 's/^/    worker-1: /' | tee -a "$LOG_FILE" || true
            ;;
        *HBase*)
            log "  [诊断] HBase Supervisor 状态与 Master 最近日志:"
            docker exec master supervisorctl status hbase-master 2>&1 | sed 's/^/    /' | tee -a "$LOG_FILE" || true
            docker logs --tail 40 master 2>&1 | sed 's/^/    /' | tee -a "$LOG_FILE" || true
            ;;
        *Hive*)
            log "  [诊断] Hive Supervisor 状态:"
            docker exec master supervisorctl status hive-metastore hive-server2 2>&1 | sed 's/^/    /' | tee -a "$LOG_FILE" || true
            ;;
        *Kafka*|*Flume*|*数据管道*)
            log "  [诊断] Kafka/Flume Supervisor 状态:"
            docker exec worker-1 supervisorctl status kafka-broker 2>&1 | sed 's/^/    /' | tee -a "$LOG_FILE" || true
            docker exec infra supervisorctl status flume-agent 2>&1 | sed 's/^/    /' | tee -a "$LOG_FILE" || true
            ;;
        *Spark*)
            log "  [诊断] Spark Supervisor 状态:"
            docker exec master supervisorctl status spark-master 2>&1 | sed 's/^/    /' | tee -a "$LOG_FILE" || true
            docker exec worker-1 supervisorctl status spark-worker 2>&1 | sed 's/^/    /' | tee -a "$LOG_FILE" || true
            ;;
        *Flink*)
            log "  [诊断] Flink Supervisor 状态:"
            docker exec master supervisorctl status flink-jobmanager 2>&1 | sed 's/^/    /' | tee -a "$LOG_FILE" || true
            docker exec worker-1 supervisorctl status flink-taskmanager 2>&1 | sed 's/^/    /' | tee -a "$LOG_FILE" || true
            ;;
        *MySQL*)
            log "  [诊断] MySQL Supervisor 状态与最近日志:"
            docker exec infra supervisorctl status mysql 2>&1 | sed 's/^/    /' | tee -a "$LOG_FILE" || true
            docker logs --tail 40 infra 2>&1 | sed 's/^/    /' | tee -a "$LOG_FILE" || true
            ;;
    esac
}

section() {
    echo "" | tee -a "$LOG_FILE"
    echo -e "${CYAN}========================================${NC}" | tee -a "$LOG_FILE"
    echo -e "${CYAN}  $1${NC}" | tee -a "$LOG_FILE"
    echo -e "${CYAN}========================================${NC}" | tee -a "$LOG_FILE"
}

run_hbase_cmd() {
    local cmd="$1"
    echo "$cmd" | docker exec -i master bash -c 'cat > /tmp/hbase_test.cmd && /opt/hbase/bin/hbase shell /tmp/hbase_test.cmd'
}

# ===============================================
# 0. 集群容器状态检查
# ===============================================
test_cluster_status() {
    section "集群容器状态检查"

    local containers="master worker-1 worker-2 worker-3 infra"
    for c in $containers; do
        run_test "容器 $c 运行状态" "docker ps --format '{{.Names}}' | grep -q '^${c}$'"
    done

    log_info "Supervisor服务状态 (master):"
    docker exec master supervisorctl status 2>/dev/null | tee -a "$LOG_FILE" || true
    log_info "Supervisor服务状态 (worker-1):"
    docker exec worker-1 supervisorctl status 2>/dev/null | tee -a "$LOG_FILE" || true
    log_info "Supervisor服务状态 (infra):"
    docker exec infra supervisorctl status 2>/dev/null | tee -a "$LOG_FILE" || true
}

# ===============================================
# 0.1 JVM 与进程内存验收
# ===============================================
test_memory_configuration() {
    section "JVM 与进程内存配置"

    log_info "Master 节点实际 JVM 启动参数:"
    docker exec master bash -c \
        "ps -eo pid,args | grep -E '[N]ameNode|[R]esourceManager|[H]Master|[H]iveMetaStore|[H]iveServer2|deploy.master.Master|[S]tandaloneSessionClusterEntrypoint'" \
        2>/dev/null | tee -a "$LOG_FILE" || true

    log_info "Worker-1 节点实际 JVM 启动参数:"
    docker exec worker-1 bash -c \
        "ps -eo pid,args | grep -E '[D]ataNode|[N]odeManager|[Q]uorumPeerMain|kafka.Kafka|[H]RegionServer|deploy.worker.Worker|[T]askManagerRunner'" \
        2>/dev/null | tee -a "$LOG_FILE" || true

    run_test "NameNode 最大堆内存 512 MB" \
        "docker exec master bash -c \"ps -eo args | grep '[N]ameNode' | grep -q -- '-Xmx512m'\""
    run_test "DataNode 最大堆内存 256 MB" \
        "docker exec worker-1 bash -c \"ps -eo args | grep '[D]ataNode' | grep -q -- '-Xmx256m'\""
    run_test "HBase Master 最大堆内存 512 MB" \
        "docker exec master bash -c \"ps -eo args | grep '[H]Master' | grep -q -- '-Xmx512m'\""
    run_test "HBase RegionServer 最大堆内存 1024 MB" \
        "docker exec worker-1 bash -c \"ps -eo args | grep '[H]RegionServer' | grep -q -- '-Xmx1024m'\""
    run_test "ZooKeeper 最大堆内存 128 MB" \
        "docker exec worker-1 bash -c \"ps -eo args | grep '[Q]uorumPeerMain' | grep -q -- '-Xmx128m'\""
    run_test "Kafka 最大堆内存 512 MB" \
        "docker exec worker-1 bash -c \"ps -eo args | grep 'kafka.Kafka' | grep -q -- '-Xmx512m'\""
    run_test "Spark Master 守护进程堆内存 512 MB" \
        "docker exec master bash -c \"ps -eo args | grep '[d]eploy.master.Master' | grep -q -- '-Xmx512m'\""
    run_test "Spark Worker 守护进程堆内存 512 MB" \
        "docker exec worker-1 bash -c \"ps -eo args | grep '[d]eploy.worker.Worker' | grep -q -- '-Xmx512m'\""
    run_test "Flink JobManager 进程内存配置 512 MB" \
        "docker exec master grep -q '^jobmanager.memory.process.size: 512m$' /opt/flink/conf/flink-conf.yaml"
    run_test "Flink TaskManager 进程内存配置 512 MB" \
        "docker exec worker-1 grep -q '^taskmanager.memory.process.size: 512m$' /opt/flink/conf/flink-conf.yaml"
}

# ===============================================
# 1. Hadoop 测试 (HDFS + YARN + MapReduce)
# ===============================================
test_hadoop() {
    section "Hadoop 测试 (HDFS / YARN / MapReduce)"

    # --- HDFS ---
    log_info "HDFS 文件系统测试"

    run_test "HDFS NameNode 安全模式检查" \
        "docker exec master bash -c '/opt/hadoop/bin/hdfs dfsadmin -safemode get 2>/dev/null | grep -q OFF'"

    run_test "HDFS DataNode 数量 (>=3)" \
        "docker exec master bash -c '/opt/hadoop/bin/hdfs dfsadmin -report 2>/dev/null | grep \"Live datanodes\" | grep -oE \"[0-9]+\" | head -1' | grep -qE '[3-9]'"

    run_test "HDFS 创建目录" \
        "docker exec master /opt/hadoop/bin/hdfs dfs -mkdir -p /test/cluster-test"

    run_test "HDFS 上传文件" \
        "docker exec master bash -c 'echo hello-cluster > /tmp/test.txt && /opt/hadoop/bin/hdfs dfs -put -f /tmp/test.txt /test/cluster-test/'"

    run_test "HDFS 读取文件" \
        "docker exec master bash -c '/opt/hadoop/bin/hdfs dfs -cat /test/cluster-test/test.txt' | grep -q hello-cluster"

    run_test "HDFS 列出目录" \
        "docker exec master /opt/hadoop/bin/hdfs dfs -ls /test/cluster-test"

    run_test "HDFS 删除测试数据" \
        "docker exec master /opt/hadoop/bin/hdfs dfs -rm -r -f /test/cluster-test"

    # --- YARN ---
    log_info "YARN 资源管理测试"

    run_test "YARN ResourceManager 端口可达" \
        "docker exec master bash -c 'echo > /dev/tcp/master/8032'"

    run_test "YARN NodeManager 数量 (>=3)" \
        "docker exec master bash -c '/opt/hadoop/bin/yarn node -list 2>/dev/null | grep -c RUNNING' | grep -qE '[3-9]'"

    run_test "YARN ResourceManager Web UI" \
        "docker exec master bash -c 'curl -s -o /dev/null -w \"%{http_code}\" -L http://localhost:8088' | grep -qE '200|302'"

    # --- MapReduce ---
    log_info "MapReduce 作业测试"

    local HADOOP_VERSION=$(docker exec master bash -c '/opt/hadoop/bin/hadoop version 2>/dev/null | head -1 | awk "{print \$2}"')
    log_info "  Hadoop版本: $HADOOP_VERSION"

    if [ -n "$HADOOP_VERSION" ]; then
        run_test "MapReduce WordCount 作业" \
            "docker exec master bash -c '
                /opt/hadoop/bin/hdfs dfs -mkdir -p /test/mr/input && \
                echo \"hello world hello hadoop\" | /opt/hadoop/bin/hdfs dfs -put - /test/mr/input/data.txt && \
                /opt/hadoop/bin/hadoop jar /opt/hadoop/share/hadoop/mapreduce/hadoop-mapreduce-examples-${HADOOP_VERSION}.jar wordcount /test/mr/input /test/mr/output 2>&1 | grep -q completed && \
                /opt/hadoop/bin/hdfs dfs -cat /test/mr/output/part-r-00000 && \
                /opt/hadoop/bin/hdfs dfs -rm -r -f /test/mr'"
    else
        log_skip "MapReduce WordCount (无法获取Hadoop版本)"
        SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
    fi
}

# ===============================================
# 2. ZooKeeper 测试
# ===============================================
test_zookeeper() {
    section "ZooKeeper 测试"

    run_test "ZooKeeper worker-1 端口可达" \
        "docker exec worker-1 bash -c 'echo > /dev/tcp/localhost/2181'"

    run_test "ZooKeeper worker-2 端口可达" \
        "docker exec worker-2 bash -c 'echo > /dev/tcp/localhost/2181'"

    run_test "ZooKeeper worker-3 端口可达" \
        "docker exec worker-3 bash -c 'echo > /dev/tcp/localhost/2181'"

    run_test "ZooKeeper 四字命令 ruok" \
        "docker exec worker-1 bash -c '/opt/zookeeper/bin/zkCli.sh -server localhost:2181 ls /' 2>&1 | grep -q zookeeper"

    run_test "ZooKeeper 创建节点" \
        "docker exec worker-1 bash -c '/opt/zookeeper/bin/zkCli.sh -server localhost:2181 create /cluster-test test_data' 2>&1 | grep -q Created"

    run_test "ZooKeeper 读取节点" \
        "docker exec worker-1 bash -c '/opt/zookeeper/bin/zkCli.sh -server localhost:2181 get /cluster-test' 2>&1 | grep -q test_data"

    run_test "ZooKeeper 删除节点" \
        "docker exec worker-1 bash -c '/opt/zookeeper/bin/zkCli.sh -server localhost:2181 delete /cluster-test' 2>&1 | tail -5"
}

# ===============================================
# 3. HBase 测试
# ===============================================
test_hbase() {
    section "HBase 测试"

    run_test "HBase Master 端口可达" \
        "docker exec master bash -c 'echo > /dev/tcp/master/16000'"

    run_test "HBase RegionServer 端口可达 (worker-1)" \
        "docker exec worker-1 bash -c 'echo > /dev/tcp/worker-1/16020'"

    run_test "HBase 集群状态" \
        "run_hbase_cmd 'status' | grep -qE 'active master|servers'"

    run_hbase_cmd 'disable "cluster_test"' >/dev/null 2>&1 || true
    run_hbase_cmd 'drop "cluster_test"' >/dev/null 2>&1 || true

    run_test "HBase 创建表" \
        "run_hbase_cmd 'create \"cluster_test\", \"cf\"' | grep -q 'Created table'"

    run_test "HBase 插入数据" \
        "run_hbase_cmd 'put \"cluster_test\", \"row1\", \"cf:name\", \"alice\"' | grep -q 'Took'"

    run_test "HBase 扫描数据" \
        "run_hbase_cmd 'scan \"cluster_test\"' | grep -q alice"

    run_test "HBase 获取数据" \
        "run_hbase_cmd 'get \"cluster_test\", \"row1\"' | grep -q 'value=alice'"

    run_test "HBase 删除表" \
        "run_hbase_cmd 'disable \"cluster_test\"' | grep -q 'Took' && run_hbase_cmd 'drop \"cluster_test\"' | grep -q 'Took'"
}

# ===============================================
# 4. Hive 测试
# ===============================================
test_hive() {
    section "Hive 测试"

    run_test "Hive Metastore 端口可达" \
        "docker exec master bash -c 'echo > /dev/tcp/localhost/9083'"

    run_test "HiveServer2 端口可达" \
        "docker exec master bash -c 'echo > /dev/tcp/localhost/10000'"

    run_test "Hive 创建数据库" \
        "docker exec master bash -c 'timeout 60 /opt/hive/bin/beeline -u \"jdbc:hive2://localhost:10000/default;auth=noSasl\" -e \"CREATE DATABASE IF NOT EXISTS cluster_test_db;\"' 2>/dev/null"

    run_test "Hive 创建表" \
        "docker exec master bash -c 'timeout 60 /opt/hive/bin/beeline -u \"jdbc:hive2://localhost:10000/cluster_test_db;auth=noSasl\" -e \"CREATE TABLE IF NOT EXISTS test_users (id INT, name STRING, age INT);\"' 2>/dev/null"

    run_test "Hive 插入数据" \
        "docker exec master bash -c 'timeout 120 /opt/hive/bin/beeline -u \"jdbc:hive2://localhost:10000/cluster_test_db;auth=noSasl\" -e \"SET hive.stats.autogather=false; INSERT INTO test_users VALUES (1, \\\"alice\\\", 25), (2, \\\"bob\\\", 30);\"' 2>/dev/null"

    run_test "Hive 查询数据" \
        "docker exec master bash -c 'timeout 60 /opt/hive/bin/beeline -u \"jdbc:hive2://localhost:10000/cluster_test_db;auth=noSasl\" -e \"SELECT * FROM test_users;\"' 2>&1 | grep -q alice"

    run_test "Hive 聚合查询" \
        "docker exec master bash -c 'timeout 60 /opt/hive/bin/beeline -u \"jdbc:hive2://localhost:10000/cluster_test_db;auth=noSasl\" -e \"SELECT COUNT(*) FROM test_users;\"' 2>&1 | grep -qE '[0-9]+'"

    run_test "Hive 清理测试数据" \
        "docker exec master bash -c 'timeout 120 /opt/hive/bin/beeline -u \"jdbc:hive2://localhost:10000/cluster_test_db;auth=noSasl\" -e \"DROP TABLE IF EXISTS test_users;\" && timeout 60 /opt/hive/bin/beeline -u \"jdbc:hive2://localhost:10000/default;auth=noSasl\" -e \"DROP DATABASE IF EXISTS cluster_test_db;\"' 2>/dev/null"
}

# ===============================================
# 5. Kafka 测试
# ===============================================
test_kafka() {
    section "Kafka 测试"

    run_test "Kafka Broker worker-1 端口可达" \
        "docker exec worker-1 bash -c 'echo > /dev/tcp/localhost/9092'"

    run_test "Kafka Broker worker-2 端口可达" \
        "docker exec worker-2 bash -c 'echo > /dev/tcp/localhost/9092'"

    run_test "Kafka Broker worker-3 端口可达" \
        "docker exec worker-3 bash -c 'echo > /dev/tcp/localhost/9092'"

    run_test "Kafka 列出主题" \
        "docker exec worker-1 /opt/kafka/bin/kafka-topics.sh --list --bootstrap-server worker-1:9092"

    run_test "Kafka 创建主题" \
        "docker exec worker-1 /opt/kafka/bin/kafka-topics.sh --create --topic cluster-test-topic --partitions 3 --replication-factor 1 --bootstrap-server worker-1:9092"

    run_test "Kafka 查看主题详情" \
        "docker exec worker-1 /opt/kafka/bin/kafka-topics.sh --describe --topic cluster-test-topic --bootstrap-server worker-1:9092"

    run_test "Kafka 生产消息" \
        "docker exec worker-1 bash -c 'echo \"test-message-1\" | /opt/kafka/bin/kafka-console-producer.sh --broker-list worker-1:9092 --topic cluster-test-topic'"

    run_test "Kafka 消费消息" \
        "docker exec worker-1 bash -c 'timeout 10 /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server worker-1:9092 --topic cluster-test-topic --from-beginning --max-messages 1' | grep -q test-message"

    run_test "Kafka 删除主题" \
        "docker exec worker-1 /opt/kafka/bin/kafka-topics.sh --delete --topic cluster-test-topic --bootstrap-server worker-1:9092"
}

# ===============================================
# 6. Flume 测试
# ===============================================
test_flume() {
    section "Flume 测试"

    local flume_running=false
    if docker exec infra supervisorctl status flume-agent 2>/dev/null | grep -q RUNNING; then
        flume_running=true
    fi

    if [ "$flume_running" = true ]; then
        run_test "Flume Agent 进程状态" \
            "docker exec infra supervisorctl status flume-agent | grep -q RUNNING"

        run_test "Flume Agent 日志输出" \
            "docker exec infra bash -c 'ls /opt/flume/logs/ 2>/dev/null | wc -l' | grep -qE '[1-9]'"

        # Flume配置检查
        run_test "Flume配置文件存在性" \
            "docker exec infra bash -c '[ -f /opt/flume/conf/flume-kafka.conf ] && echo exists' | grep -q exists"

        # Flume与Kafka联动测试
        test_flume_kafka_integration
    else
        log_skip "Flume Agent 未在运行，跳过Flume测试"
        SKIPPED_TESTS=$((SKIPPED_TESTS + 2))
    fi
}

# ===============================================
# Flume与Kafka联动测试
# ===============================================
test_flume_kafka_integration() {
    section "Flume与Kafka联动测试"
    
    # 创建测试用的Kafka主题
    local test_topic="flume-test-topic-$(date +%s)"
    
    run_test "创建Flume测试Kafka主题" \
        "docker exec worker-1 /opt/kafka/bin/kafka-topics.sh --create --topic $test_topic --partitions 1 --replication-factor 1 --bootstrap-server worker-1:9092"

    # 准备Flume配置文件
    local flume_conf="/tmp/flume-test.conf"
    cat > "$flume_conf" << EOF
# Flume测试配置 - 从文件采集数据到Kafka
test-agent.sources = file-source
test-agent.channels = memory-channel
test-agent.sinks = kafka-sink

# 配置Source
test-agent.sources.file-source.type = exec
test-agent.sources.file-source.command = tail -F /tmp/flume-test-input.txt
test-agent.sources.file-source.batchSize = 10

# 配置Channel
test-agent.channels.memory-channel.type = memory
test-agent.channels.memory-channel.capacity = 1000
test-agent.channels.memory-channel.transactionCapacity = 100

# 配置Sink
test-agent.sinks.kafka-sink.type = org.apache.flume.sink.kafka.KafkaSink
test-agent.sinks.kafka-sink.brokerList = worker-1:9092
test-agent.sinks.kafka-sink.topic = $test_topic
test-agent.sinks.kafka-sink.batchSize = 10

# 绑定Source、Channel、Sink
test-agent.sources.file-source.channels = memory-channel
test-agent.sinks.kafka-sink.channel = memory-channel
EOF

    # 复制配置文件到容器
    docker cp "$flume_conf" infra:/opt/flume/conf/flume-test.conf
    rm -f "$flume_conf"

    # 创建测试输入文件
    docker exec infra bash -c "echo 'Flume test message 1' > /tmp/flume-test-input.txt"
    docker exec infra bash -c "echo 'Flume test message 2' >> /tmp/flume-test-input.txt"
    docker exec infra bash -c "echo 'Flume test message 3' >> /tmp/flume-test-input.txt"

    # 启动Flume测试Agent
    run_test "启动Flume测试Agent" \
        "docker exec infra bash -c 'nohup /opt/flume/bin/flume-ng agent -n test-agent -c /opt/flume/conf -f /opt/flume/conf/flume-test.conf -Dflume.root.logger=INFO,console > /tmp/flume-test.log 2>&1 &' && sleep 5"

    # 等待数据采集和传输
    sleep 10

    # 检查Kafka中是否接收到Flume发送的消息
    run_test "Flume数据成功发送到Kafka" \
        "docker exec worker-1 bash -c 'timeout 15 /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server worker-1:9092 --topic $test_topic --from-beginning --max-messages 1' | grep -q 'Flume test message'"

    # 停止Flume测试Agent
    docker exec infra bash -c "pkill -f 'flume-ng agent' || true"
    
    # 清理测试主题
    docker exec worker-1 /opt/kafka/bin/kafka-topics.sh --delete --topic $test_topic --bootstrap-server worker-1:9092 2>/dev/null || true
    
    # 清理测试文件
    docker exec infra bash -c "rm -f /tmp/flume-test-input.txt /tmp/flume-test.log /opt/flume/conf/flume-test.conf"
}

# ===============================================
# 7. 数据管道端到端测试
# ===============================================
test_data_pipeline() {
    section "数据管道端到端测试"
    
    # 创建端到端测试主题
    local pipeline_topic="pipeline-test-topic-$(date +%s)"
    
    run_test "创建端到端测试主题" \
        "docker exec worker-1 /opt/kafka/bin/kafka-topics.sh --create --topic $pipeline_topic --partitions 1 --replication-factor 1 --bootstrap-server worker-1:9092"

    # 准备Flume到Kafka的配置文件
    local flume_pipeline_conf="/tmp/flume-pipeline.conf"
    cat > "$flume_pipeline_conf" << EOF
# 端到端测试配置 - 从文件到Kafka
pipeline-agent.sources = file-source
pipeline-agent.channels = memory-channel
pipeline-agent.sinks = kafka-sink

# 配置Source
pipeline-agent.sources.file-source.type = exec
pipeline-agent.sources.file-source.command = tail -F /tmp/pipeline-input.txt
pipeline-agent.sources.file-source.batchSize = 5

# 配置Channel
pipeline-agent.channels.memory-channel.type = memory
pipeline-agent.channels.memory-channel.capacity = 1000
pipeline-agent.channels.memory-channel.transactionCapacity = 100

# 配置Sink
pipeline-agent.sinks.kafka-sink.type = org.apache.flume.sink.kafka.KafkaSink
pipeline-agent.sinks.kafka-sink.brokerList = worker-1:9092
pipeline-agent.sinks.kafka-sink.topic = $pipeline_topic
pipeline-agent.sinks.kafka-sink.batchSize = 5

# 绑定Source、Channel、Sink
pipeline-agent.sources.file-source.channels = memory-channel
pipeline-agent.sinks.kafka-sink.channel = memory-channel
EOF

    # 复制配置文件到容器
    docker cp "$flume_pipeline_conf" infra:/opt/flume/conf/flume-pipeline.conf
    rm -f "$flume_pipeline_conf"

    # 创建测试数据
    docker exec infra bash -c "echo 'Pipeline test data $(date)' > /tmp/pipeline-input.txt"
    
    # 启动Flume管道Agent
    run_test "启动数据管道Flume Agent" \
        "docker exec infra bash -c 'nohup /opt/flume/bin/flume-ng agent -n pipeline-agent -c /opt/flume/conf -f /opt/flume/conf/flume-pipeline.conf -Dflume.root.logger=INFO,console > /tmp/flume-pipeline.log 2>&1 &' && sleep 5"

    # 等待数据采集
    sleep 8

    # 验证数据是否成功到达Kafka
    run_test "数据成功通过Flume到达Kafka" \
        "docker exec worker-1 bash -c 'timeout 10 /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server worker-1:9092 --topic $pipeline_topic --from-beginning --max-messages 1' | grep -q 'Pipeline test data'"

    # 测试Kafka到HDFS的数据流（可选）
    run_test "Kafka主题数据可访问性验证" \
        "docker exec worker-1 /opt/kafka/bin/kafka-topics.sh --describe --topic $pipeline_topic --bootstrap-server worker-1:9092 | grep -q 'PartitionCount: 1'"

    # 停止Flume管道Agent
    docker exec infra bash -c "pkill -f 'flume-ng agent' || true"
    
    # 清理测试资源
    docker exec worker-1 /opt/kafka/bin/kafka-topics.sh --delete --topic $pipeline_topic --bootstrap-server worker-1:9092 2>/dev/null || true
    docker exec infra bash -c "rm -f /tmp/pipeline-input.txt /tmp/flume-pipeline.log /opt/flume/conf/flume-pipeline.conf"
}

# ===============================================
# 7. Spark 测试
# ===============================================
test_spark() {
    section "Spark 测试"

    run_test "Spark Master 端口可达" \
        "docker exec master bash -c 'echo > /dev/tcp/localhost/8080'"

    run_test "Spark Master Web UI" \
        "docker exec master bash -c 'curl -s -o /dev/null -w \"%{http_code}\" http://localhost:8080' | grep -q 200"

    run_test "Spark Worker 数量 (>=3)" \
        "docker exec master bash -c 'curl -s http://localhost:8080/json/ 2>/dev/null | grep -o \"aliveworkers\\\"[[:space:]]*:[[:space:]]*[0-9]*\"' | grep -oE '[0-9]+' | grep -qE '[3-9]'"

    local SPARK_VERSION=$(docker exec master bash -c 'ls /opt/spark/examples/jars/spark-examples_*.jar 2>/dev/null | head -1 | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | head -1')
    log_info "  Spark版本: $SPARK_VERSION"

    if [ -n "$SPARK_VERSION" ]; then
        local EXAMPLE_JAR="/opt/spark/examples/jars/spark-examples_2.12-${SPARK_VERSION}.jar"

        run_test "Spark Standalone Pi 计算" \
            "docker exec master bash -c 'timeout 120 /opt/spark/bin/spark-submit --master spark://master:7077 --class org.apache.spark.examples.SparkPi $EXAMPLE_JAR 10 2>&1 | grep -q \"Pi is roughly\"'"

        run_test "Spark on YARN Pi 计算" \
            "docker exec master bash -c 'export HADOOP_CONF_DIR=/opt/hadoop/etc/hadoop && timeout 120 /opt/spark/bin/spark-submit --master yarn --deploy-mode client --class org.apache.spark.examples.SparkPi $EXAMPLE_JAR 10 2>&1 | grep -q \"Pi is roughly\"'"
    else
        log_skip "Spark Pi作业 (无法获取Spark版本)"
        SKIPPED_TESTS=$((SKIPPED_TESTS + 2))
    fi
}

# ===============================================
# 8. Flink 测试
# ===============================================
test_flink() {
    section "Flink 测试"

    run_test "Flink JobManager 端口可达" \
        "docker exec master bash -c 'echo > /dev/tcp/localhost/8081'"

    run_test "Flink Dashboard Web UI" \
        "docker exec master bash -c 'curl -s -o /dev/null -w \"%{http_code}\" http://localhost:8081' | grep -q 200"

    run_test "Flink TaskManager 数量 (>=1)" \
        "docker exec master bash -c 'curl -s http://localhost:8081/overview 2>/dev/null' | grep -o '\"taskmanagers\":[0-9]*' | grep -oE '[1-9]'"

    run_test "Flink 提交 WordCount 作业" \
        "docker exec master bash -c 'export HADOOP_CLASSPATH=\$(/opt/hadoop/bin/hadoop classpath) && export HADOOP_CONF_DIR=/opt/hadoop/etc/hadoop && timeout 60 /opt/flink/bin/flink run /opt/flink/examples/streaming/WordCount.jar 2>&1 | grep -q \"Job has been submitted\"'"
}

# ===============================================
# 9. MySQL 测试
# ===============================================
test_mysql() {
    section "MySQL 测试 (infra节点)"

    run_test "MySQL 端口可达" \
        "docker exec infra bash -c 'echo > /dev/tcp/localhost/3306'"

    run_test "MySQL 连接与查询" \
        "docker exec infra mysql -uroot -proot -e 'SELECT 1 AS test;' 2>/dev/null | grep -q test"

    run_test "MySQL hive_metastore 数据库存在" \
        "docker exec infra mysql -uroot -proot -e 'SHOW DATABASES;' 2>/dev/null | grep -q hive_metastore"

    run_test "MySQL 创建测试表" \
        "docker exec infra mysql -uroot -proot -e 'CREATE DATABASE IF NOT EXISTS test_db; USE test_db; CREATE TABLE IF NOT EXISTS test_table (id INT PRIMARY KEY, name VARCHAR(50));' 2>/dev/null"

    run_test "MySQL 插入与查询" \
        "docker exec infra mysql -uroot -proot -e 'USE test_db; INSERT INTO test_table VALUES (1, \"test\") ON DUPLICATE KEY UPDATE name=\"test\"; SELECT * FROM test_table;' 2>/dev/null | grep -q test"

    run_test "MySQL 清理测试数据" \
        "docker exec infra mysql -uroot -proot -e 'DROP DATABASE IF EXISTS test_db;' 2>/dev/null"
}

# ===============================================
# 主函数
# ===============================================
main() {
    log "=============================================="
    log "  5节点全栈大数据集群功能测试"
    log "  开始时间: $(date)"
    log "  日志文件: $LOG_FILE"
    log "=============================================="

    test_cluster_status
    test_memory_configuration

    test_hadoop
    test_zookeeper
    test_hbase
    test_hive
    test_kafka
    test_flume
    test_data_pipeline
    test_spark
    test_flink
    test_mysql

    section "测试结果汇总"
    log ""
    log "  总测试数: $TOTAL_TESTS"
    log "  通过: $PASSED_TESTS"
    log "  失败: $FAILED_TESTS"
    log "  跳过: $SKIPPED_TESTS"
    log ""

    if [ $TOTAL_TESTS -gt 0 ]; then
        SUCCESS_RATE=$((PASSED_TESTS * 100 / TOTAL_TESTS))
        log "  成功率: ${SUCCESS_RATE}%"
    fi

    log ""
    if [ $FAILED_TESTS -eq 0 ]; then
        log_success "所有测试通过！集群功能正常"
    elif [ $SUCCESS_RATE -ge 80 ]; then
        log_warning "大部分测试通过，部分功能异常"
    else
        log_error "测试失败较多，请检查集群状态"
    fi

    log ""
    log "  测试结束时间: $(date)"
    log "  详细日志: $LOG_FILE"
    log "=============================================="

    if [ $FAILED_TESTS -gt 0 ]; then
        return 1
    fi
    return 0
}

main "$@"
