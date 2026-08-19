#!/bin/bash

# Flume -> Kafka 严格集成测试
# 使用本轮唯一消息进行最多三次消费验证；失败时保存中文诊断日志。

set -u
export MSYS_NO_PATHCONV=1

LOG_DIR="test/test-log"
LOG_FILE="$LOG_DIR/test-flume-kafka-$(date +%Y%m%d-%H%M%S).log"
TEST_MESSAGE="flume-kafka-integration-$(date +%s)-$$"
TOPIC="flume-logs"

mkdir -p "$LOG_DIR"

log() {
    echo "$1" | tee -a "$LOG_FILE"
}

diagnose() {
    log ""
    log "[诊断] Flume Agent 进程："
    docker exec flume-kafka bash -c \
        "ps -eo pid,args | grep '[o]rg.apache.flume.node.Application'" \
        2>&1 | tee -a "$LOG_FILE" || true
    log "[诊断] Topic 分区、副本与 ISR："
    docker exec kafka1 /opt/kafka/bin/kafka-topics.sh \
        --describe --topic "$TOPIC" --bootstrap-server kafka1:9092 \
        2>&1 | tee -a "$LOG_FILE" || true
    log "[诊断] Topic 最新偏移量："
    docker exec kafka1 /opt/kafka/bin/kafka-run-class.sh kafka.tools.GetOffsetShell \
        --broker-list kafka1:9092 --topic "$TOPIC" --time -1 \
        2>&1 | tee -a "$LOG_FILE" || true
    log "[诊断] Flume 最近 100 行容器日志："
    docker logs --tail 100 flume-kafka 2>&1 | tee -a "$LOG_FILE" || true
}

log "=============================================="
log "Flume -> Kafka 严格集成测试"
log "测试时间：$(date '+%Y-%m-%d %H:%M:%S %z')"
log "测试 Topic：$TOPIC"
log "本轮唯一消息：$TEST_MESSAGE"
log "详细日志：$LOG_FILE"
log "=============================================="

log "[阶段 1/5] 检查 Flume 和 Kafka 三节点容器。"
for container in flume-kafka kafka1 kafka2 kafka3; do
    STATUS=$(docker inspect -f '状态={{.State.Status}}，运行中={{.State.Running}}，退出码={{.State.ExitCode}}' "$container" 2>&1)
    if [ $? -ne 0 ] || ! echo "$STATUS" | grep -q '运行中=true'; then
        log "[失败] 必要容器 $container 未运行。"
        log "[诊断] $STATUS"
        log "测试终止：请先启动完整 Kafka 集群和 Flume 容器。"
        exit 1
    fi
    log "[通过] $container 正在运行；$STATUS"
done

log ""
log "[阶段 2/5] 检查 Flume Agent 名称与配置链路。"
AGENT=$(docker exec flume-kafka bash -c \
    "ps -eo pid,args | grep '[o]rg.apache.flume.node.Application'" 2>&1)
if [ $? -ne 0 ] || ! echo "$AGENT" | grep -q -- '--name agent1'; then
    log "[失败] Flume 未以 agent1 启动，配置前缀与 Agent 名称可能不一致。"
    log "[诊断] 实际进程：$AGENT"
    diagnose
    exit 1
fi
log "[通过] Flume Agent 以 agent1 启动。"
log "[信息] 实际进程：$AGENT"

CONFIG_RESULT=$(docker exec flume-kafka bash -c "
    grep -q '^agent1.sources = log-source' /opt/flume/conf/flume-kafka.conf &&
    grep -q '^agent1.channels = memory-channel' /opt/flume/conf/flume-kafka.conf &&
    grep -q '^agent1.sinks = kafka-sink' /opt/flume/conf/flume-kafka.conf &&
    grep -q '^agent1.sources.log-source.channels = memory-channel' /opt/flume/conf/flume-kafka.conf &&
    grep -q '^agent1.sinks.kafka-sink.channel = memory-channel' /opt/flume/conf/flume-kafka.conf
" 2>&1)
if [ $? -ne 0 ]; then
    log "[失败] agent1 的 Source、Channel、Sink 或绑定关系不完整。"
    log "[诊断] $CONFIG_RESULT"
    diagnose
    exit 1
fi
log "[通过] Source -> Channel -> Kafka Sink 配置链路完整。"

log ""
log "[阶段 3/5] 检查并准备 Kafka Topic。"
TOPIC_LIST=$(docker exec kafka1 /opt/kafka/bin/kafka-topics.sh \
    --list --bootstrap-server kafka1:9092 2>&1)
if [ $? -ne 0 ]; then
    log "[失败] 无法从 kafka1 获取 Topic 列表。"
    log "[诊断] $TOPIC_LIST"
    diagnose
    exit 1
fi

if echo "$TOPIC_LIST" | grep -Fxq "$TOPIC"; then
    log "[通过] Topic $TOPIC 已存在。"
else
    log "[信息] Topic $TOPIC 不存在，开始创建 3 分区、3 副本 Topic。"
    CREATE_RESULT=$(docker exec kafka1 /opt/kafka/bin/kafka-topics.sh \
        --create --topic "$TOPIC" --partitions 3 --replication-factor 3 \
        --bootstrap-server kafka1:9092 2>&1)
    if [ $? -ne 0 ]; then
        log "[失败] Topic 创建失败，可能是 Broker 数量不足或 Kafka 集群未就绪。"
        log "[诊断] $CREATE_RESULT"
        diagnose
        exit 1
    fi
    log "[通过] Topic 创建成功：$CREATE_RESULT"
fi

TOPIC_DETAIL=$(docker exec kafka1 /opt/kafka/bin/kafka-topics.sh \
    --describe --topic "$TOPIC" --bootstrap-server kafka1:9092 2>&1)
if [ $? -ne 0 ]; then
    log "[失败] Topic 已准备但无法读取详情。"
    log "[诊断] $TOPIC_DETAIL"
    diagnose
    exit 1
fi
log "[信息] Topic 详情："
printf '%s\n' "$TOPIC_DETAIL" | tee -a "$LOG_FILE"

log ""
log "[阶段 4/5] 将唯一消息写入 Flume 监控文件。"
WRITE_RESULT=$(docker exec flume-kafka bash -c \
    "test -w /var/log/application/application.log && printf '%s\\n' '$TEST_MESSAGE' >> /var/log/application/application.log" 2>&1)
if [ $? -ne 0 ]; then
    log "[失败] 无法写入应用日志；请检查 /var/log/application 挂载和权限。"
    log "[诊断] $WRITE_RESULT"
    diagnose
    exit 1
fi
log "[通过] 唯一消息已经写入 Source 文件。"

SOURCE_TAIL=$(docker exec flume-kafka tail -n 5 /var/log/application/application.log 2>&1)
if ! echo "$SOURCE_TAIL" | grep -Fq "$TEST_MESSAGE"; then
    log "[失败] 写入命令成功，但 Source 文件末尾未找到唯一消息，可能存在挂载路径不一致。"
    log "[诊断] 应用日志末尾：$SOURCE_TAIL"
    diagnose
    exit 1
fi
log "[通过] 已从 Source 文件回读并确认唯一消息。"

log ""
log "[阶段 5/5] 从 Kafka 消费并匹配本轮唯一消息。"
for attempt in 1 2 3; do
    log "[信息] 第 $attempt/3 次消费验证，每次最多等待 10 秒。"
    CONSUMED=$(docker exec kafka1 timeout 10 \
        /opt/kafka/bin/kafka-console-consumer.sh \
        --topic "$TOPIC" --from-beginning \
        --bootstrap-server kafka1:9092 2>&1 || true)

    if echo "$CONSUMED" | grep -Fq "$TEST_MESSAGE"; then
        log "[通过] 第 $attempt 次验证消费到本轮唯一消息。"
        log "测试结论：Flume Exec Source、Memory Channel、Kafka Sink 和 Kafka 消费链路全部正常。"
        exit 0
    fi

    log "[未匹配] 本次消费者输出中没有唯一消息；等待 5 秒后重试。"
    log "[信息] 本次共读取 $(printf '%s\n' "$CONSUMED" | wc -l | tr -d ' ') 行输出。"
    sleep 5
done

log "[失败] 三次消费均未匹配本轮唯一消息。"
log "[定位提示] Source 文件已确认写入，因此重点检查 Flume Channel 事务、Kafka Sink 连接和 Topic 偏移量。"
log "[诊断] 最后一次消费者输出末尾："
printf '%s\n' "$CONSUMED" | tail -n 30 | tee -a "$LOG_FILE"
diagnose
exit 1
