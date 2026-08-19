#!/bin/bash

set -u

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/test-common.sh"

test_init "MySQL 与 Hive Metastore 数据库测试" "test-mysql"

TEST_DB="test_db_$(date +%s)_$$"
TEST_VALUE="mysql-value-$(date +%s)-$$"

cleanup_database() {
    docker exec mysql mysql -uroot -proot \
        -e "DROP DATABASE IF EXISTS $TEST_DB;" >/dev/null 2>&1 || true
}

test_section "一、容器状态检查"
if ! test_container_running mysql; then
    test_detail "当前 MySQL 相关容器" "$(docker ps -a --filter name=mysql 2>&1)"
    test_finish "MySQL 测试提前结束：容器未运行"
    exit 1
fi

test_section "二、服务就绪检查"
MYSQL_READY=false
for attempt in $(seq 1 30); do
    PING_OUTPUT=$(docker exec mysql mysqladmin ping -uroot -proot 2>&1)
    if [ $? -eq 0 ] && echo "$PING_OUTPUT" | grep -qi 'alive'; then
        MYSQL_READY=true
        test_pass "MySQL 服务响应 mysqladmin ping"
        test_detail "mysqladmin 输出" "$PING_OUTPUT"
        break
    fi
    test_info "第 $attempt/30 次等待 MySQL 就绪。"
    sleep 2
done

if [ "$MYSQL_READY" != true ]; then
    test_fail "MySQL 在 60 秒内未就绪；请检查初始化、数据卷和密码配置"
    test_detail "最后一次 mysqladmin 输出" "$PING_OUTPUT"
fi

test_section "三、账户和元数据库检查"
ROOT_QUERY=$(docker exec mysql mysql -N -B -uroot -proot \
    -e "SELECT 'root-connection-ok';" 2>&1)
if [ $? -eq 0 ] && echo "$ROOT_QUERY" | grep -Fxq 'root-connection-ok'; then
    test_pass "root 用户能够连接并执行查询"
    test_detail "查询结果" "$ROOT_QUERY"
else
    test_fail "root 用户连接或查询失败；请检查 MYSQL_ROOT_PASSWORD"
    test_detail "MySQL 客户端输出" "$ROOT_QUERY"
fi

METASTORE_DB=$(docker exec mysql mysql -N -B -uroot -proot \
    -e "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='hive';" 2>&1)
if [ $? -eq 0 ] && echo "$METASTORE_DB" | grep -Fxq 'hive'; then
    test_pass "独立架构的 hive 元数据库存在"
else
    test_fail "独立架构的 hive 元数据库不存在；Hive Metastore 将无法保存元数据"
    test_detail "数据库检查输出" "$METASTORE_DB"
fi

HIVE_QUERY=$(docker exec mysql mysql -N -B -uhive -phive \
    -e "SELECT 'hive-connection-ok';" 2>&1)
if [ $? -eq 0 ] && echo "$HIVE_QUERY" | grep -Fxq 'hive-connection-ok'; then
    test_pass "hive 用户能够连接并执行查询"
    test_detail "查询结果" "$HIVE_QUERY"
else
    test_fail "hive 用户连接失败；请检查用户、密码和授权主机范围"
    test_detail "MySQL 客户端输出" "$HIVE_QUERY"
fi

test_section "四、数据库 CRUD"
test_info "使用本轮唯一数据库：$TEST_DB"
CREATE_DB=$(docker exec mysql mysql -uroot -proot \
    -e "CREATE DATABASE $TEST_DB;" 2>&1)
if [ $? -eq 0 ]; then
    test_pass "创建测试数据库"
else
    test_fail "创建测试数据库失败"
    test_detail "CREATE DATABASE 输出" "$CREATE_DB"
fi

CREATE_TABLE=$(docker exec mysql mysql -uroot -proot \
    -e "CREATE TABLE $TEST_DB.test_table (id INT PRIMARY KEY, value_text VARCHAR(100));" 2>&1)
if [ $? -eq 0 ]; then
    test_pass "创建测试表"
else
    test_fail "创建测试表失败；请检查数据库创建结果和用户权限"
    test_detail "CREATE TABLE 输出" "$CREATE_TABLE"
fi

INSERT_OUTPUT=$(docker exec mysql mysql -uroot -proot \
    -e "INSERT INTO $TEST_DB.test_table VALUES (1, '$TEST_VALUE');" 2>&1)
if [ $? -eq 0 ]; then
    test_pass "插入唯一测试数据"
else
    test_fail "插入测试数据失败；请检查表结构和 SQL 错误"
    test_detail "INSERT 输出" "$INSERT_OUTPUT"
fi

QUERY_OUTPUT=$(docker exec mysql mysql -N -B -uroot -proot \
    -e "SELECT value_text FROM $TEST_DB.test_table WHERE id=1;" 2>&1)
if [ $? -eq 0 ] && echo "$QUERY_OUTPUT" | grep -Fxq "$TEST_VALUE"; then
    test_pass "精确查询到本轮唯一测试数据"
    test_detail "SELECT 结果" "$QUERY_OUTPUT"
else
    test_fail "查询结果与写入值不一致；请检查 INSERT 是否提交成功"
    test_detail "SELECT 输出" "$QUERY_OUTPUT"
fi

test_section "五、测试资源清理"
DROP_OUTPUT=$(docker exec mysql mysql -uroot -proot \
    -e "DROP DATABASE $TEST_DB;" 2>&1)
if [ $? -eq 0 ]; then
    test_pass "删除测试数据库"
else
    test_fail "删除测试数据库失败；数据库 $TEST_DB 可能残留"
    test_detail "DROP DATABASE 输出" "$DROP_OUTPUT"
fi

if [ "$TEST_FAILED" -gt 0 ]; then
    test_section "失败诊断"
    test_detail "MySQL 进程列表" "$(docker exec mysql ps aux 2>&1)"
    test_container_logs mysql 120
fi

cleanup_database
test_finish "MySQL 与 Hive Metastore 数据库测试结果"
exit $?
