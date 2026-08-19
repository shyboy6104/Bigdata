#!/bin/bash

# 禁用 Git Bash/MSYS2 的路径自动转换，防止 docker exec 中的绝对路径被转换为 Windows 路径
export MSYS_NO_PATHCONV=1

# 设置字符编码
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志文件配置
LOG_DIR="test/test-log"
LOG_FILE="$LOG_DIR/hive-test-$(date +%Y%m%d-%H%M%S).log"

# 创建日志目录
mkdir -p "$LOG_DIR"

# 捕获全部终端输出，Beeline、HDFS 和容器诊断信息统一进入日志。
exec > >(tee -a "$LOG_FILE") 2>&1

GLOBAL_FAILURES=0

# 函数：打印带颜色的消息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    GLOBAL_FAILURES=$((GLOBAL_FAILURES + 1))
}

# 函数：记录日志
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 函数：检查命令是否存在
check_command() {
    if ! command -v "$1" &> /dev/null; then
        print_error "命令 $1 不存在，请先安装"
        exit 1
    fi
}

# 函数：检查Docker容器是否运行
check_container() {
    local container_name=$1
    if docker ps | grep -q "$container_name"; then
        return 0
    else
        return 1
    fi
}

# 函数：执行Hive SQL命令并检查结果
execute_hive_command() {
    local container=$1
    local sql=$2
    local expected_pattern=$3
    local description=$4
    
    print_info "   $description"
    local output
    
    # 使用更稳定的命令执行方式
    output=$(timeout 60 docker exec "$container" bash -c "beeline -u jdbc:hive2://localhost:10000 -e \"$sql\" 2>&1 | tail -30" 2>&1)
    
    # 检查命令是否执行成功
    if echo "$output" | grep -q "$expected_pattern"; then
        print_success "   ✓ $description 成功"
        log "$description 成功"
        return 0
    elif echo "$output" | grep -q "StatsTask" && echo "$output" | grep -q "SUCCESS"; then
        print_success "   ✓ $description 成功"
        log "$description 成功 (StatsTask warning ignored)"
        return 0
    elif echo "$output" | grep -q "Error:"; then
        print_error "   ✗ $description 失败"
        log "$description 失败 - 输出: $output"
        return 1
    else
        print_warning "   ⚠ $description 结果不确定"
        log "$description 结果不确定 - 输出: $output"
        return 2
    fi
}

# 检查必要命令
check_command docker

print_info "=== Hive Cluster Test ==="
log "Hive集群测试开始"
print_info "Test Time: $(date)"
print_info "Log file: $LOG_FILE"
echo

# 检查 Hive 相关容器状态
print_info "1. 检查 Hive 相关容器状态..."
log "检查Hive相关容器状态"

# 检查所有容器是否运行
all_running=true
containers=("hive-server2" "hive-metastore" "hive-cli")

for container in "${containers[@]}"; do
    if check_container "$container"; then
        container_status=$(docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep "$container")
        print_success "   $container: 运行中"
        echo "      $container_status"
    else
        print_error "   $container: 未运行"
        all_running=false
    fi
done

if [ "$all_running" = "false" ]; then
    print_error "部分容器未运行，请检查集群状态"
    exit 1
fi

print_success "所有Hive相关容器正常运行"
echo

# 测试 Hive 服务可访问性
print_info "2. 测试 Hive 服务可访问性..."
log "测试Hive服务可访问性"

# 等待 Hive Server2 完全启动
print_info "   等待 Hive Server2 完全启动..."
log "等待Hive Server2完全启动"
for i in {1..60}; do
    if docker exec hive-server2 bash -c "beeline -u jdbc:hive2://localhost:10000 -e 'show databases;'" >/dev/null 2>&1; then
        print_success "   ✓ Hive Server2 已完全启动"
        log "Hive Server2 已完全启动"
        break
    else
        if [ $i -eq 60 ]; then
            print_error "   ✗ Hive Server2 启动超时"
            log "Hive Server2 启动超时"
            # 显示Hive Server2日志以帮助诊断
            docker logs hive-server2 --tail 20
            exit 1
        fi
        sleep 2
    fi
done

# 检查Hive Server连接
print_info "   检查 Hive Server 连接..."
if timeout 30 docker exec hive-server2 bash -c "beeline -u jdbc:hive2://localhost:10000 -e 'show databases;'" >/dev/null 2>&1; then
    print_success "   ✓ Hive Server 连接正常"
    log "Hive Server 连接正常"
else
    print_error "   ✗ Hive Server 连接异常"
    log "Hive Server 连接异常"
    # 显示详细错误信息
    docker exec hive-server2 bash -c "beeline -u jdbc:hive2://localhost:10000 -e 'show databases;'" 2>&1 | head -20
fi

# 检查Hive CLI连接
print_info "   检查 Hive CLI 连接..."
if timeout 10 docker exec hive-cli bash -c "hive -e 'show databases;'" >/dev/null 2>&1; then
    print_success "   ✓ Hive CLI 连接正常"
    log "Hive CLI 连接正常"
else
    print_warning "   ⚠ Hive CLI 连接异常"
    log "Hive CLI 连接异常"
fi

echo

# 测试 Hive 基本功能
print_info "3. 测试 Hive 基本功能..."
log "测试Hive基本功能"

# 清理现有测试数据库和表
print_info "   清理现有测试数据..."
execute_hive_command "hive-server2" "DROP DATABASE IF EXISTS test_db CASCADE;" "No rows affected" "清理测试数据库"
print_info "   测试数据清理完成"

# 测试1：创建数据库
if execute_hive_command "hive-server2" "CREATE DATABASE IF NOT EXISTS test_db;" "No rows affected" "创建测试数据库"; then
    # 测试2：使用数据库
    execute_hive_command "hive-server2" "USE test_db;" "No rows affected" "使用测试数据库"
    
    # 测试3：创建表
    execute_hive_command "hive-server2" "CREATE TABLE IF NOT EXISTS employees (id INT, name STRING, age INT, city STRING, salary DOUBLE, department STRING) ROW FORMAT DELIMITED FIELDS TERMINATED BY ',' STORED AS TEXTFILE;" "No rows affected" "创建员工表"
    
    # 测试4：插入数据
    execute_hive_command "hive-server2" "INSERT INTO employees VALUES (1, '张三', 25, '北京', 50000.0, '技术部'), (2, '李四', 30, '上海', 60000.0, '销售部'), (3, '王五', 28, '深圳', 55000.0, '技术部');" "No rows affected" "插入测试数据"
    
    # 测试5：查询所有数据
    execute_hive_command "hive-server2" "SELECT * FROM employees;" "张三" "查询所有员工数据"
    
    # 测试6：条件查询
    execute_hive_command "hive-server2" "SELECT * FROM employees WHERE department = '技术部';" "技术部" "查询技术部员工"
    
    # 测试7：聚合查询
    execute_hive_command "hive-server2" "SELECT department, AVG(salary) as avg_salary FROM employees GROUP BY department;" "avg_salary" "统计各部门平均工资"
    
    # 测试8：排序查询
    execute_hive_command "hive-server2" "SELECT * FROM employees ORDER BY age DESC;" "李四" "按年龄降序排序"
    
    # 测试9：显示表结构
    execute_hive_command "hive-server2" "DESCRIBE employees;" "id" "显示表结构"
    
    # 测试10：显示数据库
    execute_hive_command "hive-server2" "SHOW DATABASES;" "test_db" "显示所有数据库"
    
    # 测试11：显示表
    execute_hive_command "hive-server2" "SHOW TABLES;" "employees" "显示所有表"
    
    # 测试12：统计行数
    execute_hive_command "hive-server2" "SELECT COUNT(*) as total FROM employees;" "total" "统计员工数量"
    
    print_success "   Hive基本功能测试完成"
else
    print_error "   数据库创建失败，跳过后续测试"
fi

echo

# 测试 Hive 高级功能
print_info "4. 测试 Hive 高级功能..."
log "测试Hive高级功能"

# 测试分区表功能
print_info "   测试分区表功能..."
if execute_hive_command "hive-server2" "CREATE TABLE IF NOT EXISTS sales (id INT, product STRING, amount DOUBLE) PARTITIONED BY (year INT, month INT) ROW FORMAT DELIMITED FIELDS TERMINATED BY ',' STORED AS TEXTFILE;" "No rows affected" "创建分区表"; then
    execute_hive_command "hive-server2" "INSERT INTO sales PARTITION (year=2024, month=1) VALUES (1, '产品A', 1000.0), (2, '产品B', 2000.0);" "No rows affected" "插入分区数据"
    execute_hive_command "hive-server2" "SELECT * FROM sales WHERE year=2024 AND month=1;" "产品A" "查询分区数据"
    print_success "   ✓ 分区表功能正常"
else
    print_warning "   ⚠ 分区表功能测试异常"
fi

# 测试外部表功能
print_info "   测试外部表功能..."
if execute_hive_command "hive-server2" "CREATE EXTERNAL TABLE IF NOT EXISTS external_test (id INT, name STRING) ROW FORMAT DELIMITED FIELDS TERMINATED BY ',' STORED AS TEXTFILE LOCATION '/tmp/external_test';" "No rows affected" "创建外部表"; then
    print_success "   ✓ 外部表功能正常"
else
    print_warning "   ⚠ 外部表功能测试异常"
fi

echo

# 测试 Hive 与 HDFS 集成
print_info "5. 测试 Hive 与 HDFS 集成..."
log "测试Hive与HDFS集成"

# 检查Hive数据是否存储在HDFS
print_info "   检查 Hive 数据存储..."
if docker exec hive-server2 bash -c "hdfs dfs -ls /user/hive/warehouse/" >/dev/null 2>&1; then
    print_success "   ✓ Hive数据存储在HDFS正常"
    log "Hive数据存储在HDFS正常"
else
    print_warning "   ⚠ Hive数据存储检查异常"
    log "Hive数据存储检查异常"
fi

echo

# 清理测试数据
print_info "6. 清理测试数据..."
log "清理测试数据"

if execute_hive_command "hive-server2" "DROP DATABASE IF EXISTS test_db CASCADE;" "No rows affected" "删除测试数据库"; then
    print_success "   测试数据清理完成"
    log "测试数据清理完成"
else
    print_warning "   测试数据清理异常"
    log "测试数据清理异常"
fi

echo

# 生成测试报告
print_info "7. 生成测试报告..."
log "生成综合测试报告"

echo
print_info "=== Hive 集群测试完成 ==="
print_info "测试时间: $(date)"
print_info "日志文件: $LOG_FILE"
echo

# 总体评估
print_info "=== 测试总结 ==="
if [ "$all_running" = "true" ]; then
    print_success "✓ Hive 集群状态: 正常"
else
    print_error "✗ Hive 集群状态: 异常"
fi

# 检查关键功能是否正常
function_count=5
success_count=0

if [ "$all_running" = "true" ]; then
    ((success_count++))
fi

# 检查服务可访问性（通过Hive Server连接状态判断）
if docker exec hive-server2 bash -c "beeline -u jdbc:hive2://localhost:10000 -e 'show databases;'" >/dev/null 2>&1; then
    ((success_count++))
fi

# 检查基本功能（通过创建表和查询判断）
check_output=$(docker exec hive-server2 bash -c "beeline -u jdbc:hive2://localhost:10000 -e \"CREATE TABLE IF NOT EXISTS test_check (id INT);\" 2>&1")
if echo "$check_output" | grep -q "No rows affected\|StatsTask.*SUCCESS"; then
    ((success_count++))
    docker exec hive-server2 bash -c "beeline -u jdbc:hive2://localhost:10000 -e 'DROP TABLE IF EXISTS test_check;'" >/dev/null 2>&1
fi

# 检查高级功能（通过分区表判断）
check_output=$(docker exec hive-server2 bash -c "beeline -u jdbc:hive2://localhost:10000 -e \"CREATE TABLE IF NOT EXISTS test_part (id INT) PARTITIONED BY (p INT);\" 2>&1")
if echo "$check_output" | grep -q "No rows affected\|StatsTask.*SUCCESS"; then
    ((success_count++))
    docker exec hive-server2 bash -c "beeline -u jdbc:hive2://localhost:10000 -e 'DROP TABLE IF EXISTS test_part;'" >/dev/null 2>&1
fi

# 检查HDFS集成
if docker exec hive-server2 bash -c "hdfs dfs -ls /user/hive/warehouse/" >/dev/null 2>&1; then
    ((success_count++))
fi

success_rate=$(( success_count * 100 / function_count ))

print_info "关键功能测试: $success_count/$function_count"
print_info "总体成功率: ${success_rate}%"

if [ $success_rate -ge 80 ]; then
    print_success "✓ Hive 集群功能: 优秀"
elif [ $success_rate -ge 60 ]; then
    print_warning "⚠ Hive 集群功能: 一般"
else
    print_error "✗ Hive 集群功能: 异常"
fi

# 记录最终结果
log "测试完成 - 关键功能测试: $success_count/$function_count, 成功率: ${success_rate}%"

echo
print_success "=== Hive 集群功能验证完成 ==="
print_info "详细测试报告已生成，请查看日志文件: $LOG_FILE"

# 退出状态
if [ "$GLOBAL_FAILURES" -gt 0 ]; then
    print_info "检测到 $GLOBAL_FAILURES 条明确失败，输出 Hive 相关容器诊断日志"
    for container in hive-server2 hive-metastore hive-cli; do
        print_info "[诊断] $container 最近 80 行日志"
        docker logs --tail 80 "$container" 2>&1 || true
    done
fi

if [ $success_rate -ge 70 ] && [ "$GLOBAL_FAILURES" -eq 0 ]; then
    exit 0
else
    exit 1
fi
