#!/bin/bash

export MSYS_NO_PATHCONV=1

LOG_DIR="test/test-log"
LOG_FILE="$LOG_DIR/test-hbase-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "$LOG_DIR"

# 捕获所有终端输出，确保 HBase Shell 原始结果、容器状态和错误信息进入日志。
exec > >(tee -a "$LOG_FILE") 2>&1

GLOBAL_FAILURES=0

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

check_command() {
    if ! command -v "$1" &> /dev/null; then
        print_error "命令 $1 不存在，请先安装后再运行测试"
        exit 1
    fi
}

check_container() {
    local container_name=$1
    if docker ps | grep -q "$container_name"; then
        return 0
    else
        return 1
    fi
}

run_hbase_shell() {
    local container=$1
    local command=$2
    timeout 30 docker exec "$container" bash -lc "hbase shell <<'HBASEEOF' 2>&1
$command
HBASEEOF"
}

execute_hbase_command() {
    local container=$1
    local command=$2
    local expected_pattern=$3
    local description=$4
    
    print_info "   $description"
    
    local output
    output=$(run_hbase_shell "$container" "$command")
    local exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        print_error "   ✗ $description（超时或命令错误）"
        log "$description 失败 - 退出码: $exit_code"
        return 1
    fi
    
    if echo "$output" | grep -q "$expected_pattern"; then
        print_success "   ✓ $description"
        log "$description 成功"
        return 0
    elif echo "$output" | grep -qi "error\|exception\|failed"; then
        print_error "   ✗ $description"
        log "$description 失败 - 输出: $(echo "$output" | tail -5)"
        return 1
    else
        print_warning "   ⚠ $description（结果不确定）"
        log "$description 结果不确定 - 输出: $(echo "$output" | tail -5)"
        return 2
    fi
}

check_command docker

log "=== HBase 集群测试 ==="
print_info "=== HBase 集群测试 ==="
print_info "测试时间: $(date)"
print_info "日志文件: $LOG_FILE"
log ""

print_info "1. 检查 HBase 容器状态..."
log "检查 HBase 容器状态"

all_running=true
containers=("hbase-master" "hbase-regionserver1" "hbase-regionserver2")

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
    print_error "部分容器未运行，请检查 Compose 状态和容器日志"
    exit 1
fi

print_success "所有 HBase 容器均在运行"
log ""

print_info "2. 测试 HBase 服务可访问性..."
log "测试 HBase 服务可访问性"

print_info "   检查 HBase Master Web UI..."
if curl -s http://localhost:16210/master-status >/dev/null 2>&1; then
    print_success "   ✓ HBase Master Web UI 可访问"
    log "HBase Master Web UI 可访问"
else
    print_error "   ✗ HBase Master Web UI 不可访问"
    log "HBase Master Web UI 不可访问"
fi

print_info "   检查 HBase Shell 连接..."
shell_output=$(run_hbase_shell "hbase-master" "version")
if echo "$shell_output" | grep -q "2.2.3"; then
    print_success "   ✓ HBase Shell 连接正常"
    log "HBase Shell 连接正常"
else
    print_error "   ✗ HBase Shell 连接异常"
    log "HBase Shell 连接异常"
fi

log ""

print_info "3. 测试 HBase 基本功能..."
log "测试 HBase 基本功能"

print_info "   清理可能残留的测试表..."
run_hbase_shell "hbase-master" "disable 'test_table'" >/dev/null 2>&1
run_hbase_shell "hbase-master" "drop 'test_table'" >/dev/null 2>&1
print_info "   测试表预清理完成"

if execute_hbase_command "hbase-master" "create 'test_table', 'cf1', 'cf2'" "Created table" "创建测试表"; then
    execute_hbase_command "hbase-master" "put 'test_table', 'row1', 'cf1:name', 'John'" "Took" "写入 row1 姓名"
    execute_hbase_command "hbase-master" "put 'test_table', 'row1', 'cf1:age', '25'" "Took" "写入 row1 年龄"
    execute_hbase_command "hbase-master" "put 'test_table', 'row2', 'cf1:name', 'Jane'" "Took" "写入 row2 姓名"
    
    execute_hbase_command "hbase-master" "scan 'test_table'" "row1" "扫描测试表数据"
    execute_hbase_command "hbase-master" "get 'test_table', 'row1'" "cf1:name" "读取指定行"
    
    execute_hbase_command "hbase-master" "describe 'test_table'" "test_table" "查看表结构"
    
    execute_hbase_command "hbase-master" "count 'test_table'" "row(s)" "统计表行数"
    
    execute_hbase_command "hbase-master" "list" "test_table" "列出所有表"
    
    print_success "   HBase 基本功能测试完成"
else
    print_error "   测试表创建失败，跳过后续数据操作"
fi

log ""

print_info "4. 测试 HBase 集群状态..."
log "测试 HBase 集群状态"

print_info "   检查 RegionServer 状态..."
region_servers=$(run_hbase_shell "hbase-master" "status" 2>/dev/null | grep -oE '[0-9]+ servers' | head -1 | grep -oE '[0-9]+')
if [ -n "$region_servers" ] && [ "$region_servers" -ge 2 ]; then
    print_success "   ✓ RegionServer 数量正常: $region_servers"
    log "RegionServer 数量正常: $region_servers"
else
    print_error "   ✗ RegionServer 数量异常: ${region_servers:-0}"
    log "RegionServer 数量异常: ${region_servers:-0}"
fi

print_info "   检查测试表 Region 信息..."
table_status=$(run_hbase_shell "hbase-master" "status 'detailed'" 2>/dev/null | grep -A 5 'test_table' | head -3)
if echo "$table_status" | grep -q "test_table"; then
    print_success "   ✓ 能够读取测试表 Region 信息"
    log "能够读取测试表 Region 信息"
else
    print_warning "   ⚠ 未从详细状态中读取到测试表 Region 信息"
    log "未读取到测试表 Region 信息"
fi

log ""

print_info "5. 清理测试数据..."
log "清理测试数据"

disable_output=$(run_hbase_shell "hbase-master" "disable 'test_table'" 2>/dev/null)
drop_output=$(run_hbase_shell "hbase-master" "drop 'test_table'" 2>/dev/null)

if echo "$drop_output" | grep -q "Took"; then
    print_success "   测试数据清理完成"
    log "测试数据清理完成"
else
    print_warning "   测试数据清理结果不确定"
    log "测试数据清理结果不确定"
fi

log ""

print_info "6. 生成测试报告..."
log "生成测试报告"

log ""
print_info "=== HBase 集群测试完成 ==="
print_info "测试时间: $(date)"
print_info "日志文件: $LOG_FILE"
log ""

print_info "=== 测试汇总 ==="
if [ "$all_running" = "true" ]; then
    print_success "✓ HBase 集群容器状态: 正常"
else
    print_error "✗ HBase 集群容器状态: 异常"
fi

function_count=4
success_count=0

if [ "$all_running" = "true" ]; then
    ((success_count++))
    echo "容器状态: 正常"
fi

if curl -s http://localhost:16210/master-status >/dev/null 2>&1; then
    ((success_count++))
    echo "服务可访问性: 正常"
fi

check_output=$(run_hbase_shell "hbase-master" "create 'test_check_table', 'cf1'" 2>/dev/null)
if echo "$check_output" | grep -q "Created table"; then
    ((success_count++))
    echo "基本功能: 正常"
    run_hbase_shell "hbase-master" "disable 'test_check_table'" >/dev/null 2>&1
    run_hbase_shell "hbase-master" "drop 'test_check_table'" >/dev/null 2>&1
fi

region_servers=$(run_hbase_shell "hbase-master" "status" 2>/dev/null | grep -oE '[0-9]+ servers' | head -1 | grep -oE '[0-9]+')
if [ -n "$region_servers" ] && [ "$region_servers" -ge 2 ]; then
    ((success_count++))
    echo "集群状态: 正常"
fi

success_rate=$(( success_count * 100 / function_count ))

print_info "关键功能测试: $success_count/$function_count"
print_info "总体成功率: ${success_rate}%"

if [ $success_rate -ge 80 ]; then
    print_success "✓ HBase 集群功能: 正常"
elif [ $success_rate -ge 60 ]; then
    print_warning "⚠ HBase 集群功能: 部分可用"
else
    print_error "✗ HBase 集群功能: 异常"
fi

log "测试完成 - 关键功能: $success_count/$function_count，成功率: ${success_rate}%"

log ""
print_success "=== HBase 集群功能验证完成 ==="
print_info "详细测试报告已生成，请查看日志文件: $LOG_FILE"

log "测试结束时间: $(date)"
log "测试结果保存到: $LOG_FILE"

if [ "$GLOBAL_FAILURES" -gt 0 ]; then
    print_info "检测到 $GLOBAL_FAILURES 条明确失败，输出 HBase 容器诊断日志"
    for container in hbase-master hbase-regionserver1 hbase-regionserver2; do
        print_info "[诊断] $container 最近 80 行日志"
        docker logs --tail 80 "$container" 2>&1 || true
    done
fi

if [ $success_rate -ge 70 ] && [ "$GLOBAL_FAILURES" -eq 0 ]; then
    exit 0
else
    exit 1
fi
