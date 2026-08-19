#!/bin/bash

set -u

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/test-common.sh"

test_init "Hadoop 标准集群测试" "test-hadoop"

TEST_ID="$(date +%s)-$$"
TEST_ROOT="/test/hadoop-$TEST_ID"
INPUT_TEXT="hello world hello hadoop"

cleanup_hdfs() {
    docker exec namenode hdfs dfs -rm -r -f "$TEST_ROOT" >/dev/null 2>&1 || true
}

test_section "一、容器状态检查"
containers_ready=true
for container in namenode datanode1 datanode2; do
    if ! test_container_running "$container"; then
        containers_ready=false
    fi
done

if [ "$containers_ready" != true ]; then
    test_detail "当前 Hadoop 相关容器" "$(docker ps -a --filter name=namenode --filter name=datanode 2>&1)"
    test_finish "Hadoop 测试提前结束：必要容器未运行"
    exit 1
fi

test_section "二、Web 服务与 HDFS 状态"
NN_HTTP=$(curl -sS -o /dev/null -w '%{http_code}' http://localhost:19870 2>&1)
if [ "$NN_HTTP" = "200" ]; then
    test_pass "NameNode Web UI 可访问"
else
    test_fail "NameNode Web UI 不可访问；期望 HTTP 200，实际 $NN_HTTP"
fi

RM_HTTP=$(curl -sS -L -o /dev/null -w '%{http_code}' http://localhost:18088 2>&1)
if [ "$RM_HTTP" = "200" ]; then
    test_pass "ResourceManager Web UI 可访问"
else
    test_fail "ResourceManager Web UI 不可访问；期望 HTTP 200，实际 $RM_HTTP"
fi

HDFS_REPORT=$(docker exec namenode hdfs dfsadmin -report 2>&1)
if [ $? -eq 0 ]; then
    test_pass "能够读取 HDFS 集群报告"
    test_detail "HDFS 报告摘要" "$(printf '%s\n' "$HDFS_REPORT" | grep -E 'Configured Capacity|Present Capacity|DFS Used|Live datanodes|Name:')"
else
    test_fail "hdfs dfsadmin -report 执行失败；请检查 NameNode RPC 和 DataNode 注册"
    test_detail "HDFS 报告输出" "$HDFS_REPORT"
fi

LIVE_DN=$(printf '%s\n' "$HDFS_REPORT" | sed -n 's/Live datanodes (\([0-9][0-9]*\)):.*/\1/p')
if [ -n "$LIVE_DN" ] && [ "$LIVE_DN" -ge 2 ]; then
    test_pass "至少两个 DataNode 处于存活状态"
    test_detail "存活 DataNode 数量" "$LIVE_DN"
else
    test_fail "DataNode 注册数量不足；期望至少 2，实际 ${LIVE_DN:-无法解析}"
fi

SAFE_MODE=$(docker exec namenode hdfs dfsadmin -safemode get 2>&1)
if [ $? -eq 0 ] && echo "$SAFE_MODE" | grep -qi 'OFF'; then
    test_pass "NameNode 已退出安全模式"
    test_detail "安全模式状态" "$SAFE_MODE"
else
    test_fail "NameNode 仍处于安全模式或状态查询失败；写操作将被拒绝"
    test_detail "安全模式输出" "$SAFE_MODE"
fi

test_section "三、HDFS 写入、读取与内容校验"
MKDIR_OUTPUT=$(docker exec namenode hdfs dfs -mkdir -p "$TEST_ROOT/input" 2>&1)
if [ $? -eq 0 ]; then
    test_pass "创建本轮 HDFS 测试目录"
else
    test_fail "HDFS 目录创建失败；请检查安全模式和权限配置"
    test_detail "mkdir 输出" "$MKDIR_OUTPUT"
fi

PUT_OUTPUT=$(docker exec namenode bash -c \
    "printf '%s\\n' '$INPUT_TEXT' | hdfs dfs -put - '$TEST_ROOT/input/data.txt'" 2>&1)
if [ $? -eq 0 ]; then
    test_pass "通过标准输入上传测试文件到 HDFS"
else
    test_fail "HDFS 文件上传失败；请检查目录、权限和 DataNode 可用性"
    test_detail "put 输出" "$PUT_OUTPUT"
fi

CAT_OUTPUT=$(docker exec namenode hdfs dfs -cat "$TEST_ROOT/input/data.txt" 2>&1)
if [ $? -eq 0 ] && echo "$CAT_OUTPUT" | grep -Fxq "$INPUT_TEXT"; then
    test_pass "HDFS 文件内容与写入内容完全一致"
    test_detail "文件内容" "$CAT_OUTPUT"
else
    test_fail "HDFS 文件读取失败或内容不一致"
    test_detail "cat 输出" "$CAT_OUTPUT"
fi

FILE_STATUS=$(docker exec namenode hdfs dfs -stat \
    '路径=%n，长度=%b，副本数=%r，块大小=%o' "$TEST_ROOT/input/data.txt" 2>&1)
if [ $? -eq 0 ]; then
    test_pass "能够读取 HDFS 文件元数据"
    test_detail "文件元数据" "$FILE_STATUS"
else
    test_fail "无法读取 HDFS 文件元数据"
    test_detail "stat 输出" "$FILE_STATUS"
fi

test_section "四、YARN 节点与应用管理"
YARN_NODES=$(docker exec namenode yarn node -list 2>&1)
if [ $? -eq 0 ] && echo "$YARN_NODES" | grep -q 'Total Nodes'; then
    test_pass "ResourceManager 能够列出 NodeManager"
    test_detail "YARN 节点列表" "$YARN_NODES"
else
    test_fail "YARN 节点列表查询失败；请检查 ResourceManager 和 NodeManager 日志"
    test_detail "yarn node -list 输出" "$YARN_NODES"
fi

RUNNING_NM=$(printf '%s\n' "$YARN_NODES" | grep -c 'RUNNING' || true)
if [ "$RUNNING_NM" -ge 2 ]; then
    test_pass "至少两个 NodeManager 处于 RUNNING 状态"
    test_detail "RUNNING NodeManager 数量" "$RUNNING_NM"
else
    test_fail "RUNNING NodeManager 数量不足；期望至少 2，实际 $RUNNING_NM"
fi

YARN_APPS=$(docker exec namenode yarn application -list 2>&1)
if [ $? -eq 0 ] && echo "$YARN_APPS" | grep -q 'Total number of applications'; then
    test_pass "YARN 应用管理命令可用"
    test_detail "当前应用列表" "$YARN_APPS"
else
    test_fail "YARN 应用管理命令失败"
    test_detail "yarn application -list 输出" "$YARN_APPS"
fi

test_section "五、MapReduce WordCount"
EXAMPLE_JAR=$(docker exec namenode bash -c \
    "ls /opt/hadoop/share/hadoop/mapreduce/hadoop-mapreduce-examples-*.jar | head -1" 2>&1)
if [ -z "$EXAMPLE_JAR" ]; then
    test_fail "未找到 Hadoop MapReduce 示例 JAR"
    test_detail "MapReduce 目录" "$(docker exec namenode ls -la /opt/hadoop/share/hadoop/mapreduce 2>&1)"
else
    test_info "使用示例 JAR：$EXAMPLE_JAR"
    MR_OUTPUT=$(docker exec namenode hadoop jar "$EXAMPLE_JAR" wordcount \
        "$TEST_ROOT/input" "$TEST_ROOT/output" 2>&1)
    if [ $? -eq 0 ] && echo "$MR_OUTPUT" | grep -q 'completed successfully'; then
        test_pass "MapReduce WordCount 作业执行成功"
        test_detail "作业输出末尾" "$(printf '%s\n' "$MR_OUTPUT" | tail -n 50)"
    else
        test_fail "MapReduce WordCount 作业失败；请检查 YARN Container 和聚合日志"
        test_detail "作业输出末尾" "$(printf '%s\n' "$MR_OUTPUT" | tail -n 100)"
    fi

    MR_RESULT=$(docker exec namenode hdfs dfs -cat "$TEST_ROOT/output/part-r-00000" 2>&1)
    if [ $? -eq 0 ] && echo "$MR_RESULT" | grep -q $'hello\t2' && echo "$MR_RESULT" | grep -q $'hadoop\t1'; then
        test_pass "WordCount 输出内容正确"
        test_detail "WordCount 结果" "$MR_RESULT"
    else
        test_fail "WordCount 输出缺少预期计数 hello=2、hadoop=1"
        test_detail "WordCount 结果" "$MR_RESULT"
    fi
fi

test_section "六、测试资源清理"
CLEAN_OUTPUT=$(docker exec namenode hdfs dfs -rm -r -f "$TEST_ROOT" 2>&1)
if [ $? -eq 0 ]; then
    test_pass "删除本轮 HDFS 测试目录"
    test_detail "清理输出" "$CLEAN_OUTPUT"
else
    test_fail "HDFS 测试目录清理失败；可能残留 $TEST_ROOT"
    test_detail "清理输出" "$CLEAN_OUTPUT"
fi

if [ "$TEST_FAILED" -gt 0 ]; then
    test_section "失败诊断"
    test_detail "NameNode Java 进程" "$(docker exec namenode jps 2>&1)"
    test_container_logs namenode 120
    test_container_logs datanode1 80
    test_container_logs datanode2 80
fi

cleanup_hdfs
test_finish "Hadoop 标准集群测试结果"
exit $?
