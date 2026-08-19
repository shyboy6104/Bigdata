#!/bin/bash

set -u

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/test-common.sh"

test_init "Flink 独立集群测试" "test-flink"

test_section "一、容器状态检查"
containers_ready=true
for container in flink-jobmanager flink-taskmanager1 flink-taskmanager2; do
    if ! test_container_running "$container"; then
        containers_ready=false
    fi
done

if [ "$containers_ready" != true ]; then
    test_detail "当前 Flink 相关容器" "$(docker ps -a --filter name=flink 2>&1)"
    test_finish "Flink 测试提前结束：必要容器未运行"
    exit 1
fi

test_section "二、JobManager REST 与 Web UI"
OVERVIEW=$(curl -fsS http://localhost:18081/overview 2>&1)
if [ $? -eq 0 ] && echo "$OVERVIEW" | grep -q '"taskmanagers"'; then
    test_pass "JobManager REST API 可访问"
    test_detail "REST /overview" "$OVERVIEW"
else
    test_fail "JobManager REST API 不可访问；请检查 18081 端口映射和 JobManager 日志"
    test_detail "curl 输出" "$OVERVIEW"
fi

WEB_TITLE=$(curl -fsS http://localhost:18081 2>&1)
if [ $? -eq 0 ] && echo "$WEB_TITLE" | grep -q 'Flink Dashboard'; then
    test_pass "Flink Dashboard 页面可访问"
else
    test_fail "Flink Dashboard 页面内容不符合预期"
    test_detail "Web 页面输出前 20 行" "$(printf '%s\n' "$WEB_TITLE" | head -n 20)"
fi

REGISTERED=$(printf '%s\n' "$OVERVIEW" | sed -n 's/.*"taskmanagers":\([0-9][0-9]*\).*/\1/p')
if [ -n "$REGISTERED" ] && [ "$REGISTERED" -ge 2 ]; then
    test_pass "至少两个 TaskManager 已向 JobManager 注册"
    test_detail "已注册 TaskManager 数量" "$REGISTERED"
else
    test_fail "TaskManager 注册数量不足；期望至少 2，实际 ${REGISTERED:-无法解析}"
    test_detail "TaskManager REST 信息" "$(curl -sS http://localhost:18081/taskmanagers 2>&1)"
fi

test_section "三、Flink CLI 与版本"
VERSION_OUTPUT=$(docker exec flink-jobmanager /opt/flink/bin/flink --version 2>&1)
if [ $? -eq 0 ] && echo "$VERSION_OUTPUT" | grep -q 'Version'; then
    test_pass "Flink CLI 能够输出版本信息"
    test_detail "Flink 版本" "$VERSION_OUTPUT"
else
    test_fail "Flink CLI 版本命令失败；请检查 /opt/flink 安装目录"
    test_detail "版本命令输出" "$VERSION_OUTPUT"
fi

JOB_LIST=$(docker exec flink-jobmanager /opt/flink/bin/flink list -a 2>&1)
if [ $? -eq 0 ]; then
    test_pass "Flink CLI 能够连接集群并列出作业"
    test_detail "flink list -a" "$JOB_LIST"
else
    test_fail "Flink CLI 无法连接 JobManager"
    test_detail "flink list -a 输出" "$JOB_LIST"
fi

test_section "四、实际作业提交"
EXAMPLE_JAR=$(docker exec flink-jobmanager bash -c \
    "ls /opt/flink/examples/streaming/*WordCount*.jar 2>/dev/null | head -1" 2>&1)
if [ -z "$EXAMPLE_JAR" ]; then
    test_fail "未找到 Flink WordCount 示例 JAR；请核对发行包 examples 目录"
    test_detail "streaming 示例目录" "$(docker exec flink-jobmanager ls -la /opt/flink/examples/streaming 2>&1)"
else
    test_info "使用示例 JAR：$EXAMPLE_JAR"
    JOB_OUTPUT=$(docker exec flink-jobmanager /opt/flink/bin/flink run "$EXAMPLE_JAR" 2>&1)
    if [ $? -eq 0 ]; then
        test_pass "Flink WordCount 示例作业提交并执行成功"
        test_detail "作业提交输出末尾" "$(printf '%s\n' "$JOB_OUTPUT" | tail -n 40)"
    else
        test_fail "Flink WordCount 作业失败；请检查 Slot 数量、TaskManager 注册和作业异常"
        test_detail "作业提交输出末尾" "$(printf '%s\n' "$JOB_OUTPUT" | tail -n 80)"
    fi
fi

if [ "$TEST_FAILED" -gt 0 ]; then
    test_section "失败诊断"
    test_container_logs flink-jobmanager 100
    test_container_logs flink-taskmanager1 80
    test_container_logs flink-taskmanager2 80
fi

test_finish "Flink 独立集群测试结果"
exit $?
