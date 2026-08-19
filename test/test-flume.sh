#!/bin/bash

# Flume 独立组件测试
# 目标：逐环节检查 容器 -> Agent -> 配置 -> Kafka Topic -> 日志采集 -> 消息消费。
# 失败时输出对应环节、可能原因和诊断信息，便于课堂排错。

set -u
export MSYS_NO_PATHCONV=1

LOG_DIR="test/test-log"
LOG_FILE="$LOG_DIR/test-flume-$(date +%Y%m%d-%H%M%S).log"
TOPIC="flume-logs"
TEST_MESSAGE="flume-component-$(date +%s)-$$"
PASS=0
FAIL=0

mkdir -p "$LOG_DIR"

log() {
    echo "$1" | tee -a "$LOG_FILE"
}

log_info() {
    log "[信息] $1"
}

log_pass() {
    log "[通过] $1"
    PASS=$((PASS + 1))
}

log_fail() {
    log "[失败] $1"
    FAIL=$((FAIL + 1))
}

log_output() {
    local title=$1
    local content=${2:-}
    log "[诊断] $title"
    if [ -n "$content" ]; then
        printf '%s\n' "$content" | tee -a "$LOG_FILE"
    else
        log "（无输出）"
    fi
}

check_container() {
    local container=$1
    local output

    log_info "检查容器 $container 是否存在并处于运行状态。"
    output=$(docker inspect -f '状态={{.State.Status}}，运行中={{.State.Running}}，退出码={{.State.ExitCode}}' "$container" 2>&1)
    if [ $? -eq 0 ] && echo "$output" | grep -q '运行中=true'; then
        log_pass "容器 $container 正在运行。"
        return 0
    fi

    log_fail "容器 $container 未运行；后续链路无法依赖该容器。"
    log_output "docker inspect $container" "$output"
    return 1
}

log "=============================================="
log "Flume 独立组件测试"
log "测试时间：$(date '+%Y-%m-%d %H:%M:%S %z')"
log "测试 Topic：$TOPIC"
log "本轮唯一消息：$TEST_MESSAGE"
log "日志文件：$LOG_FILE"
log "=============================================="

log ""
log "一、容器与依赖检查"
container_ready=true
for container in flume-kafka kafka1 kafka2 kafka3; do
    if ! check_container "$container"; then
        container_ready=false
    fi
done

if [ "$container_ready" != true ]; then
    log_output "当前相关容器列表" "$(docker ps -a --filter name=flume --filter name=kafka 2>&1)"
    log ""
    log "测试提前结束：至少一个必要容器未运行，请先启动 Kafka 三节点和 Flume。"
    log "结果汇总：通过 $PASS，失败 $FAIL。"
    exit 1
fi

log ""
log "二、Flume Agent 进程检查"
AGENT_PROCESS=$(docker exec flume-kafka bash -c \
    "ps -eo pid,args | grep '[o]rg.apache.flume.node.Application'" 2>&1)
if [ $? -eq 0 ] && [ -n "$AGENT_PROCESS" ]; then
    log_pass "Flume Agent Java 进程存在。"
    log_output "Agent 实际启动命令" "$AGENT_PROCESS"
else
    log_fail "未找到 Flume Agent Java 进程；可能是入口脚本启动失败或进程已经退出。"
    log_output "进程检查输出" "$AGENT_PROCESS"
    log_output "Flume 容器最近 80 行日志" "$(docker logs --tail 80 flume-kafka 2>&1)"
fi

if echo "$AGENT_PROCESS" | grep -q -- '--name agent1'; then
    log_pass "Agent 启动参数使用统一名称 agent1。"
else
    log_fail "Agent 进程未使用 --name agent1，配置前缀可能与启动参数不一致。"
fi

log ""
log "三、Flume 配置文件检查"
CONFIG_CHECK=$(docker exec flume-kafka bash -c "
    test -r /opt/flume/conf/flume-kafka.conf &&
    grep -q '^agent1.sources = log-source' /opt/flume/conf/flume-kafka.conf &&
    grep -q '^agent1.channels = memory-channel' /opt/flume/conf/flume-kafka.conf &&
    grep -q '^agent1.sinks = kafka-sink' /opt/flume/conf/flume-kafka.conf &&
    grep -q '^agent1.sources.log-source.channels = memory-channel' /opt/flume/conf/flume-kafka.conf &&
    grep -q '^agent1.sinks.kafka-sink.channel = memory-channel' /opt/flume/conf/flume-kafka.conf
" 2>&1)
if [ $? -eq 0 ]; then
    log_pass "agent1 的 Source、Channel、Sink 及绑定关系完整。"
else
    log_fail "Flume 配置文件缺少 agent1 组件或绑定关系。"
    log_output "配置检查命令输出" "$CONFIG_CHECK"
    log_output "配置文件中的 agent1 字段" "$(docker exec flume-kafka grep -n '^agent1\.' /opt/flume/conf/flume-kafka.conf 2>&1)"
fi

KAFKA_TARGET=$(docker exec flume-kafka grep \
    '^agent1.sinks.kafka-sink.brokerList' /opt/flume/conf/flume-kafka.conf 2>&1)
if echo "$KAFKA_TARGET" | grep -q 'kafka1:9092,kafka2:9092,kafka3:9092'; then
    log_pass "Kafka Sink 指向三个教学 Broker。"
else
    log_fail "Kafka Sink 的 Broker 列表与三节点架构不一致。"
    log_output "实际 Broker 配置" "$KAFKA_TARGET"
fi

log ""
log "四、Kafka Topic 检查"
TOPIC_LIST=$(docker exec kafka1 /opt/kafka/bin/kafka-topics.sh \
    --list --bootstrap-server kafka1:9092 2>&1)
if [ $? -ne 0 ]; then
    log_fail "无法连接 kafka1:9092 获取 Topic 列表。"
    log_output "Kafka Topic 列表命令输出" "$TOPIC_LIST"
elif echo "$TOPIC_LIST" | grep -Fxq "$TOPIC"; then
    log_pass "Kafka Topic $TOPIC 已存在。"
else
    log_info "Topic $TOPIC 不存在，尝试创建 3 分区、3 副本 Topic。"
    CREATE_OUTPUT=$(docker exec kafka1 /opt/kafka/bin/kafka-topics.sh \
        --create --topic "$TOPIC" --partitions 3 --replication-factor 3 \
        --bootstrap-server kafka1:9092 2>&1)
    if [ $? -eq 0 ]; then
        log_pass "Kafka Topic $TOPIC 创建成功。"
        log_output "Topic 创建结果" "$CREATE_OUTPUT"
    else
        log_fail "Kafka Topic $TOPIC 创建失败；请检查 Broker 数量、ISR 和 Kafka 日志。"
        log_output "Topic 创建命令输出" "$CREATE_OUTPUT"
    fi
fi

TOPIC_DETAIL=$(docker exec kafka1 /opt/kafka/bin/kafka-topics.sh \
    --describe --topic "$TOPIC" --bootstrap-server kafka1:9092 2>&1)
if [ $? -eq 0 ]; then
    log_pass "能够读取 Topic $TOPIC 的分区和副本信息。"
    log_output "Topic 详情" "$TOPIC_DETAIL"
else
    log_fail "无法读取 Topic $TOPIC 详情，消息测试可能无法进行。"
    log_output "Topic 详情命令输出" "$TOPIC_DETAIL"
fi

log ""
log "五、日志写入与 Flume 采集检查"
WRITE_OUTPUT=$(docker exec flume-kafka bash -c \
    "test -w /var/log/application/application.log && printf '%s\\n' '$TEST_MESSAGE' >> /var/log/application/application.log" 2>&1)
if [ $? -eq 0 ]; then
    log_pass "唯一测试消息已写入 Flume 监控的应用日志。"
else
    log_fail "无法写入 /var/log/application/application.log；请检查目录挂载和文件权限。"
    log_output "日志写入命令输出" "$WRITE_OUTPUT"
fi

log_info "等待 8 秒，让 Exec Source、Memory Channel 和 Kafka Sink 完成传输。"
sleep 8

SOURCE_TAIL=$(docker exec flume-kafka tail -n 5 /var/log/application/application.log 2>&1)
if echo "$SOURCE_TAIL" | grep -Fq "$TEST_MESSAGE"; then
    log_pass "在 Source 监控文件末尾确认了本轮唯一消息。"
else
    log_fail "Source 文件中未找到本轮消息，日志写入或挂载路径可能不一致。"
    log_output "应用日志末尾内容" "$SOURCE_TAIL"
fi

log ""
log "六、Kafka 消费结果检查"
CONSUMED=$(docker exec kafka1 timeout 15 \
    /opt/kafka/bin/kafka-console-consumer.sh \
    --topic "$TOPIC" --from-beginning \
    --bootstrap-server kafka1:9092 2>&1 || true)

if echo "$CONSUMED" | grep -Fq "$TEST_MESSAGE"; then
    log_pass "从 Kafka 消费到本轮唯一消息，Flume 端到端链路正常。"
else
    log_fail "Kafka 中未消费到本轮唯一消息；失败环节可能是 Source 读取、Channel 事务或 Kafka Sink 写入。"
    log_output "消费者输出末尾" "$(printf '%s\n' "$CONSUMED" | tail -n 30)"
    log_output "Kafka Topic 最新偏移量" "$(docker exec kafka1 /opt/kafka/bin/kafka-run-class.sh kafka.tools.GetOffsetShell --broker-list kafka1:9092 --topic "$TOPIC" --time -1 2>&1)"
    log_output "Flume 容器最近 100 行日志" "$(docker logs --tail 100 flume-kafka 2>&1)"
fi

log ""
log "=============================================="
log "Flume 测试结果汇总"
log "通过：$PASS"
log "失败：$FAIL"
log "详细日志：$LOG_FILE"
log "=============================================="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
