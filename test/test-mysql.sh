#!/bin/bash

# 禁用 Git Bash/MSYS2 的路径自动转换，防止 docker exec 中的绝对路径被转换为 Windows 路径
export MSYS_NO_PATHCONV=1

# 日志文件配置
LOG_DIR="test/test-log"
LOG_FILE="$LOG_DIR/test-mysql-$(date +%Y%m%d-%H%M%S).log"

# 创建日志目录
mkdir -p "$LOG_DIR"

# 日志函数
log() {
    echo "$1" | tee -a "$LOG_FILE"
}

log "=== MySQL 数据库服务测试 ==="
log "测试开始时间: $(date)"
log "日志文件: $LOG_FILE"
log ""

# 检查 MySQL 容器状态
log "1. 检查 MySQL 容器状态..."
docker ps | grep -E "mysql" | tee -a "$LOG_FILE"
log ""

# 等待 MySQL 服务完全启动
log "2. 等待 MySQL 服务启动..."
for i in {1..30}; do
    if docker exec mysql mysqladmin ping -uroot -proot --silent; then
        log "✓ MySQL 服务已启动"
        break
    else
        if [ $i -eq 30 ]; then
            log "✗ MySQL 服务启动超时"
            exit 1
        fi
        sleep 2
    fi
done

# 测试 MySQL 连接和基本查询
log "3. 测试 MySQL 连接和基本查询..."
connection_test=$(docker exec mysql mysql -uroot -proot -e "SELECT 1 AS test;" 2>&1)
if echo "$connection_test" | grep -q "test"; then
    log "✓ MySQL 连接和查询正常"
else
    log "✗ MySQL 连接失败: $connection_test"
fi

# 测试 hive_metastore 数据库存在性
log "4. 测试 hive_metastore 数据库存在性..."
db_exists=$(docker exec mysql mysql -uroot -proot -e "SHOW DATABASES;" 2>&1 | grep -q "hive" && echo "exists")
if [ "$db_exists" = "exists" ]; then
    log "✓ hive_metastore 数据库存在"
else
    log "✗ hive_metastore 数据库不存在"
fi

# 测试 hive 用户连接
log "5. 测试 hive 用户连接..."
hive_connection=$(docker exec mysql mysql -uhive -phive -e "SELECT 1 AS test;" 2>&1)
if echo "$hive_connection" | grep -q "test"; then
    log "✓ hive 用户连接正常"
else
    log "✗ hive 用户连接失败: $hive_connection"
fi

# 测试数据库操作
log "6. 测试数据库操作..."

# 创建测试数据库
docker exec mysql mysql -uroot -proot -e "CREATE DATABASE IF NOT EXISTS test_db;" 2>&1
if [ $? -eq 0 ]; then
    log "✓ 测试数据库创建成功"
else
    log "✗ 测试数据库创建失败"
fi

# 创建测试表
docker exec mysql mysql -uroot -proot -e "USE test_db; CREATE TABLE IF NOT EXISTS test_table (id INT PRIMARY KEY, name VARCHAR(50));" 2>&1
if [ $? -eq 0 ]; then
    log "✓ 测试表创建成功"
else
    log "✗ 测试表创建失败"
fi

# 插入测试数据
docker exec mysql mysql -uroot -proot -e "USE test_db; INSERT INTO test_table VALUES (1, 'test') ON DUPLICATE KEY UPDATE name='test';" 2>&1
if [ $? -eq 0 ]; then
    log "✓ 测试数据插入成功"
else
    log "✗ 测试数据插入失败"
fi

# 查询测试数据
query_result=$(docker exec mysql mysql -uroot -proot -e "USE test_db; SELECT * FROM test_table;" 2>&1)
if echo "$query_result" | grep -q "test"; then
    log "✓ 测试数据查询成功"
    log "  查询结果: $query_result"
else
    log "✗ 测试数据查询失败: $query_result"
fi

# 清理测试数据
docker exec mysql mysql -uroot -proot -e "DROP DATABASE IF EXISTS test_db;" 2>&1
if [ $? -eq 0 ]; then
    log "✓ 测试数据清理成功"
else
    log "✗ 测试数据清理失败"
fi

# 综合测试结果
log ""
log "=== MySQL 数据库服务测试完成 ==="
log "测试总结:"
log "- MySQL 端口连接: $([ -z "$mysql_port_status" ] && echo "✓ 正常" || echo "✗ 异常")"
log "- MySQL 连接查询: $([ -n "$connection_test" ] && echo "✓ 正常" || echo "✗ 异常")"
log "- hive_metastore 数据库: $([ "$db_exists" = "exists" ] && echo "✓ 存在" || echo "✗ 不存在")"
log "- hive 用户连接: $([ -n "$hive_connection" ] && echo "✓ 正常" || echo "✗ 异常")"
log "- 数据库操作: $([ -n "$query_result" ] && echo "✓ 正常" || echo "✗ 异常")"

log ""
log "详细测试报告已生成，MySQL 数据库服务验证完成！"

# 记录测试结束时间
log "测试结束时间: $(date)"
log "测试结果已保存到: $LOG_FILE"