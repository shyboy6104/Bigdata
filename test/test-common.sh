#!/bin/bash

# 测试脚本公共日志与断言函数。
# 本文件只供其他 test-*.sh source，不作为独立测试执行。

TEST_TOTAL=${TEST_TOTAL:-0}
TEST_PASSED=${TEST_PASSED:-0}
TEST_FAILED=${TEST_FAILED:-0}
TEST_SKIPPED=${TEST_SKIPPED:-0}

test_init() {
    local test_title=$1
    local log_prefix=$2

    export MSYS_NO_PATHCONV=1
    LOG_DIR=${LOG_DIR:-test/test-log}
    mkdir -p "$LOG_DIR"
    LOG_FILE=${LOG_FILE:-$LOG_DIR/${log_prefix}-$(date +%Y%m%d-%H%M%S).log}

    # 从这里开始，脚本的标准输出和标准错误都进入同一日志；
    # 各测试无需再单独给每条 docker/curl 命令添加 tee。
    exec > >(tee -a "$LOG_FILE") 2>&1

    echo "=============================================="
    echo "$test_title"
    echo "开始时间：$(date '+%Y-%m-%d %H:%M:%S %z')"
    echo "日志文件：$LOG_FILE"
    echo "=============================================="
}

test_section() {
    echo ""
    echo "----------------------------------------------"
    echo "$1"
    echo "----------------------------------------------"
}

test_info() {
    echo "[信息] $1"
}

test_pass() {
    echo "[通过] $1"
    TEST_TOTAL=$((TEST_TOTAL + 1))
    TEST_PASSED=$((TEST_PASSED + 1))
}

test_fail() {
    echo "[失败] $1"
    TEST_TOTAL=$((TEST_TOTAL + 1))
    TEST_FAILED=$((TEST_FAILED + 1))
}

test_skip() {
    echo "[跳过] $1"
    TEST_TOTAL=$((TEST_TOTAL + 1))
    TEST_SKIPPED=$((TEST_SKIPPED + 1))
}

test_detail() {
    local title=$1
    local content=${2:-}
    echo "[详情] $title"
    if [ -n "$content" ]; then
        printf '%s\n' "$content"
    else
        echo "（无输出）"
    fi
}

test_assert_command() {
    local description=$1
    local failure_hint=$2
    shift 2

    test_info "执行：$description"
    local output
    output=$("$@" 2>&1)
    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        test_pass "$description"
        if [ -n "$output" ]; then
            test_detail "命令输出" "$output"
        fi
        return 0
    fi

    test_fail "$description；$failure_hint"
    test_detail "退出码" "$exit_code"
    test_detail "命令输出" "$output"
    return $exit_code
}

test_container_running() {
    local container=$1
    local output
    output=$(docker inspect -f '状态={{.State.Status}}，运行中={{.State.Running}}，退出码={{.State.ExitCode}}' "$container" 2>&1)
    if [ $? -eq 0 ] && echo "$output" | grep -q '运行中=true'; then
        test_pass "容器 $container 正在运行"
        test_detail "容器状态" "$output"
        return 0
    fi

    test_fail "容器 $container 未运行；请先检查 Compose 启动结果"
    test_detail "docker inspect $container" "$output"
    return 1
}

test_container_logs() {
    local container=$1
    local lines=${2:-80}
    test_detail "容器 $container 最近 $lines 行日志" "$(docker logs --tail "$lines" "$container" 2>&1)"
}

test_finish() {
    local conclusion=$1
    echo ""
    echo "=============================================="
    echo "$conclusion"
    echo "总测试数：$TEST_TOTAL"
    echo "通过：$TEST_PASSED"
    echo "失败：$TEST_FAILED"
    echo "跳过：$TEST_SKIPPED"
    echo "结束时间：$(date '+%Y-%m-%d %H:%M:%S %z')"
    echo "详细日志：$LOG_FILE"
    echo "=============================================="

    if [ "$TEST_FAILED" -gt 0 ]; then
        return 1
    fi
    return 0
}
