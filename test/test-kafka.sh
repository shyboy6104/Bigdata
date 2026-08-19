#!/bin/bash

set -u

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/test-common.sh"

test_init "Kafka 三节点集群测试" "test-kafka"

TOPIC="test-topic-$(date +%s)-$$"
TEST_MESSAGE="kafka-message-$(date +%s)-$$"

cleanup_topic() {
    docker exec kafka1 /opt/kafka/bin/kafka-topics.sh \
        --delete --topic "$TOPIC" --bootstrap-server kafka1:9092 \
        >/dev/null 2>&1 || true
}

test_section "一、容器与依赖检查"
containers_ready=true
for container in zoo1 zoo2 zoo3 kafka1 kafka2 kafka3; do
    if ! test_container_running "$container"; then
        containers_ready=false
    fi
done

if [ "$containers_ready" != true ]; then
    test_detail "当前 Kafka/ZooKeeper 容器" "$(docker ps -a --filter name=kafka --filter name=zoo 2>&1)"
    test_finish "Kafka 测试提前结束：必要容器未运行"
    exit 1
fi

test_section "二、Broker 就绪与集群元数据"
BROKER_READY=false
for attempt in $(seq 1 30); do
    TOPIC_LIST=$(docker exec kafka1 /opt/kafka/bin/kafka-topics.sh \
        --list --bootstrap-server kafka1:9092 2>&1)
    if [ $? -eq 0 ]; then
        BROKER_READY=true
        test_pass "Kafka Broker API 已就绪"
        test_detail "当前 Topic 列表" "$TOPIC_LIST"
        break
    fi
    test_info "第 $attempt/30 次等待 Kafka Broker 就绪。"
    sleep 2
done

if [ "$BROKER_READY" != true ]; then
    test_fail "等待 Kafka Broker API 超时；请检查 ZooKeeper 连接、Cluster ID 和 Broker 日志"
    test_detail "最后一次 Topic 列表命令输出" "$TOPIC_LIST"
fi

test_section "三、Topic、分区、副本与 ISR"
test_info "创建本轮唯一 Topic：$TOPIC"
CREATE_OUTPUT=$(docker exec kafka1 /opt/kafka/bin/kafka-topics.sh \
    --create --topic "$TOPIC" --partitions 3 --replication-factor 3 \
    --bootstrap-server kafka1:9092 2>&1)
if [ $? -eq 0 ]; then
    test_pass "创建 3 分区、3 副本测试 Topic"
    test_detail "创建结果" "$CREATE_OUTPUT"
else
    test_fail "测试 Topic 创建失败；可能是 Broker 未就绪或可用 Broker 少于 3"
    test_detail "创建命令输出" "$CREATE_OUTPUT"
fi

DESCRIBE_OUTPUT=$(docker exec kafka1 /opt/kafka/bin/kafka-topics.sh \
    --describe --topic "$TOPIC" --bootstrap-server kafka1:9092 2>&1)
if [ $? -eq 0 ]; then
    test_pass "能够读取测试 Topic 详情"
    test_detail "Topic 详情" "$DESCRIBE_OUTPUT"
else
    test_fail "无法读取测试 Topic 详情"
    test_detail "describe 命令输出" "$DESCRIBE_OUTPUT"
fi

if echo "$DESCRIBE_OUTPUT" | grep -q 'PartitionCount: 3' && \
   echo "$DESCRIBE_OUTPUT" | grep -q 'ReplicationFactor: 3'; then
    test_pass "Topic 分区数和副本因子均符合预期"
else
    test_fail "Topic 分区或副本配置错误；期望 3 分区、3 副本"
fi

if echo "$DESCRIBE_OUTPUT" | awk -F'Isr: ' '
    /Partition:/ {count++; n=split($2,a,","); if (n < 3) bad=1}
    END {exit !(count == 3 && bad != 1)}'; then
    test_pass "三个分区均有三个同步副本（ISR）"
else
    test_fail "至少一个分区的 ISR 不完整；请检查 Broker 存活和副本同步"
fi

test_section "四、消息生产与精确消费"
test_info "生产本轮唯一消息：$TEST_MESSAGE"
PRODUCE_OUTPUT=$(docker exec kafka1 bash -c \
    "printf '%s\\n' '$TEST_MESSAGE' | /opt/kafka/bin/kafka-console-producer.sh --broker-list kafka1:9092 --topic '$TOPIC'" 2>&1)
if [ $? -eq 0 ]; then
    test_pass "Kafka Producer 写入消息成功"
    test_detail "Producer 输出" "$PRODUCE_OUTPUT"
else
    test_fail "Kafka Producer 写入失败；请检查 Leader、ACL 和 Broker 连接"
    test_detail "Producer 输出" "$PRODUCE_OUTPUT"
fi

CONSUME_OUTPUT=$(docker exec kafka1 timeout 20 \
    /opt/kafka/bin/kafka-console-consumer.sh \
    --topic "$TOPIC" --from-beginning --max-messages 1 \
    --bootstrap-server kafka1:9092 2>&1)
if [ $? -eq 0 ] && echo "$CONSUME_OUTPUT" | grep -Fxq "$TEST_MESSAGE"; then
    test_pass "Kafka Consumer 精确消费到本轮唯一消息"
    test_detail "Consumer 输出" "$CONSUME_OUTPUT"
else
    test_fail "Kafka Consumer 未消费到本轮唯一消息；请检查 Topic 偏移量和消息写入结果"
    test_detail "Consumer 输出" "$CONSUME_OUTPUT"
    test_detail "Topic 最新偏移量" "$(docker exec kafka1 /opt/kafka/bin/kafka-run-class.sh kafka.tools.GetOffsetShell --broker-list kafka1:9092 --topic "$TOPIC" --time -1 2>&1)"
fi

test_section "五、测试资源清理"
DELETE_OUTPUT=$(docker exec kafka1 /opt/kafka/bin/kafka-topics.sh \
    --delete --topic "$TOPIC" --bootstrap-server kafka1:9092 2>&1)
if [ $? -eq 0 ]; then
    test_pass "测试 Topic 删除请求提交成功"
    test_detail "删除结果" "$DELETE_OUTPUT"
else
    test_fail "测试 Topic 删除失败；Topic 可能残留"
    test_detail "删除命令输出" "$DELETE_OUTPUT"
fi

if [ "$TEST_FAILED" -gt 0 ]; then
    test_section "失败诊断"
    for container in kafka1 kafka2 kafka3; do
        test_container_logs "$container" 80
    done
fi

cleanup_topic
test_finish "Kafka 三节点集群测试结果"
exit $?
