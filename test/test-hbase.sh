#!/bin/bash

export MSYS_NO_PATHCONV=1

LOG_DIR="test/test-log"
LOG_FILE="$LOG_DIR/test-hbase-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "$LOG_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
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
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        print_error "Command $1 not found, please install it first"
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
        print_error "   ✗ $description (timeout or error)"
        log "$description failed - exit code: $exit_code"
        return 1
    fi
    
    if echo "$output" | grep -q "$expected_pattern"; then
        print_success "   ✓ $description"
        log "$description success"
        return 0
    elif echo "$output" | grep -qi "error\|exception\|failed"; then
        print_error "   ✗ $description"
        log "$description failed - output: $(echo "$output" | tail -5)"
        return 1
    else
        print_warning "   ⚠ $description (uncertain)"
        log "$description uncertain - output: $(echo "$output" | tail -5)"
        return 2
    fi
}

check_command docker

log "=== HBase Cluster Test ==="
print_info "=== HBase Cluster Test ==="
print_info "Test Time: $(date)"
print_info "Log file: $LOG_FILE"
log ""

print_info "1. Checking HBase container status..."
log "Checking HBase container status"

all_running=true
containers=("hbase-master" "hbase-regionserver1" "hbase-regionserver2")

for container in "${containers[@]}"; do
    if check_container "$container"; then
        container_status=$(docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep "$container")
        print_success "   $container: Running"
        echo "      $container_status"
    else
        print_error "   $container: Not running"
        all_running=false
    fi
done

if [ "$all_running" = "false" ]; then
    print_error "Some containers are not running, please check cluster status"
    exit 1
fi

print_success "All HBase containers are running"
log ""

print_info "2. Testing HBase service accessibility..."
log "Testing HBase service accessibility"

print_info "   Checking HBase Master Web UI..."
if curl -s http://localhost:16210/master-status >/dev/null 2>&1; then
    print_success "   ✓ HBase Master Web UI accessible"
    log "HBase Master Web UI accessible"
else
    print_error "   ✗ HBase Master Web UI not accessible"
    log "HBase Master Web UI not accessible"
fi

print_info "   Checking HBase Shell connection..."
shell_output=$(run_hbase_shell "hbase-master" "version")
if echo "$shell_output" | grep -q "2.2.3"; then
    print_success "   ✓ HBase Shell connection normal"
    log "HBase Shell connection normal"
else
    print_error "   ✗ HBase Shell connection abnormal"
    log "HBase Shell connection abnormal"
fi

log ""

print_info "3. Testing HBase basic functions..."
log "Testing HBase basic functions"

print_info "   Cleaning up existing test tables..."
run_hbase_shell "hbase-master" "disable 'test_table'" >/dev/null 2>&1
run_hbase_shell "hbase-master" "drop 'test_table'" >/dev/null 2>&1
print_info "   Test table cleanup done"

if execute_hbase_command "hbase-master" "create 'test_table', 'cf1', 'cf2'" "Created table" "Create test table"; then
    execute_hbase_command "hbase-master" "put 'test_table', 'row1', 'cf1:name', 'John'" "Took" "Insert data row1"
    execute_hbase_command "hbase-master" "put 'test_table', 'row1', 'cf1:age', '25'" "Took" "Insert data row1-age"
    execute_hbase_command "hbase-master" "put 'test_table', 'row2', 'cf1:name', 'Jane'" "Took" "Insert data row2"
    
    execute_hbase_command "hbase-master" "scan 'test_table'" "row1" "Scan table data"
    execute_hbase_command "hbase-master" "get 'test_table', 'row1'" "cf1:name" "Get specific row"
    
    execute_hbase_command "hbase-master" "describe 'test_table'" "test_table" "Describe table"
    
    execute_hbase_command "hbase-master" "count 'test_table'" "row(s)" "Count table rows"
    
    execute_hbase_command "hbase-master" "list" "test_table" "List all tables"
    
    print_success "   HBase basic function test completed"
else
    print_error "   Table creation failed, skipping subsequent tests"
fi

log ""

print_info "4. Testing HBase cluster status..."
log "Testing HBase cluster status"

print_info "   Checking RegionServer status..."
region_servers=$(run_hbase_shell "hbase-master" "status" 2>/dev/null | grep -oE '[0-9]+ servers' | head -1 | grep -oE '[0-9]+')
if [ -n "$region_servers" ] && [ "$region_servers" -ge 2 ]; then
    print_success "   ✓ RegionServer count normal: $region_servers"
    log "RegionServer count normal: $region_servers"
else
    print_error "   ✗ RegionServer count abnormal: ${region_servers:-0}"
    log "RegionServer count abnormal: ${region_servers:-0}"
fi

print_info "   Checking table distribution..."
table_status=$(run_hbase_shell "hbase-master" "status 'detailed'" 2>/dev/null | grep -A 5 'test_table' | head -3)
if echo "$table_status" | grep -q "test_table"; then
    print_success "   ✓ Table distribution normal"
    log "Table distribution normal"
else
    print_warning "   ⚠ Table distribution abnormal"
    log "Table distribution abnormal"
fi

log ""

print_info "5. Cleaning up test data..."
log "Cleaning up test data"

disable_output=$(run_hbase_shell "hbase-master" "disable 'test_table'" 2>/dev/null)
drop_output=$(run_hbase_shell "hbase-master" "drop 'test_table'" 2>/dev/null)

if echo "$drop_output" | grep -q "Took"; then
    print_success "   Test data cleanup completed"
    log "Test data cleanup completed"
else
    print_warning "   Test data cleanup uncertain"
    log "Test data cleanup uncertain"
fi

log ""

print_info "6. Generating test report..."
log "Generating test report"

log ""
print_info "=== HBase Cluster Test Completed ==="
print_info "Test Time: $(date)"
print_info "Log file: $LOG_FILE"
log ""

print_info "=== Test Summary ==="
if [ "$all_running" = "true" ]; then
    print_success "✓ HBase cluster status: Normal"
else
    print_error "✗ HBase cluster status: Abnormal"
fi

function_count=4
success_count=0

if [ "$all_running" = "true" ]; then
    ((success_count++))
    echo "Container status: Normal"
fi

if curl -s http://localhost:16210/master-status >/dev/null 2>&1; then
    ((success_count++))
    echo "Service accessibility: Normal"
fi

check_output=$(run_hbase_shell "hbase-master" "create 'test_check_table', 'cf1'" 2>/dev/null)
if echo "$check_output" | grep -q "Created table"; then
    ((success_count++))
    echo "Basic functions: Normal"
    run_hbase_shell "hbase-master" "disable 'test_check_table'" >/dev/null 2>&1
    run_hbase_shell "hbase-master" "drop 'test_check_table'" >/dev/null 2>&1
fi

region_servers=$(run_hbase_shell "hbase-master" "status" 2>/dev/null | grep -oE '[0-9]+ servers' | head -1 | grep -oE '[0-9]+')
if [ -n "$region_servers" ] && [ "$region_servers" -ge 2 ]; then
    ((success_count++))
    echo "Cluster status: Normal"
fi

success_rate=$(( success_count * 100 / function_count ))

print_info "Key function tests: $success_count/$function_count"
print_info "Overall success rate: ${success_rate}%"

if [ $success_rate -ge 80 ]; then
    print_success "✓ HBase cluster functions: Excellent"
elif [ $success_rate -ge 60 ]; then
    print_warning "⚠ HBase cluster functions: Fair"
else
    print_error "✗ HBase cluster functions: Abnormal"
fi

log "Test completed - Key function tests: $success_count/$function_count, success rate: ${success_rate}%"

log ""
print_success "=== HBase Cluster Function Verification Completed ==="
print_info "Detailed test report generated, please check log file: $LOG_FILE"

log "Test end time: $(date)"
log "Test results saved to: $LOG_FILE"

if [ $success_rate -ge 70 ]; then
    exit 0
else
    exit 1
fi
