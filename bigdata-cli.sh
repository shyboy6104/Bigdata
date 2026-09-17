#!/bin/bash
# BigData Platform CLI Management Tool
# Supports both single-component and multi-component Docker container management

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || {
    echo "[ERROR] Failed to enter project directory: $SCRIPT_DIR" >&2
    exit 1
}

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
COMPONENTS=("hadoop" "hadoop-ha" "zookeeper" "hbase" "hive" "kafka" "spark" "flink" "flume" "mysql")
SINGLE_COMPOSE_FILES=(
    "docker-compose.hadoop.yml"
    "docker-compose.hadoop-ha.yml"
    "docker-compose.zookeeper.yml"
    "docker-compose.hbase.yml"
    "docker-compose.hive.yml"
    "docker-compose.kafka.yml"
    "docker-compose.spark.yml"
    "docker-compose.flink.yml"
    "docker-compose.flume.yml"
    "docker-compose.mysql.yml"
)
MULTI_COMPOSE_FILE="docker-compose.5-node-cluster.yml"
SHARED_NETWORK_NAME="bigdata-net"
BASE_IMAGE_NAME="bigdata-base:latest"
BASE_DOCKERFILE="dockerfile.base"
COMPOSE_CMD=()

# Function definitions
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

check_dependencies() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker not installed or not in PATH"
        exit 1
    fi
    
    if docker compose version &> /dev/null; then
        COMPOSE_CMD=(docker compose)
    elif command -v docker-compose &> /dev/null; then
        COMPOSE_CMD=(docker-compose)
    else
        print_error "Docker Compose not installed or not in PATH"
        exit 1
    fi
}

# Ensure that independent component Compose projects can join the same network.
# This operation is idempotent: an existing network is retained unchanged.
ensure_shared_network() {
    local architecture=$1

    if [ "$architecture" != "single" ]; then
        return 0
    fi

    print_info "检查独立组件公共网络：$SHARED_NETWORK_NAME"

    if docker network inspect "$SHARED_NETWORK_NAME" >/dev/null 2>&1; then
        print_success "公共网络已存在：$SHARED_NETWORK_NAME"
        return 0
    fi

    print_info "公共网络不存在，正在创建：$SHARED_NETWORK_NAME"
    local network_output
    if network_output=$(docker network create "$SHARED_NETWORK_NAME" 2>&1); then
        print_success "公共网络创建成功：$SHARED_NETWORK_NAME"
        print_info "Docker返回的网络标识：$network_output"
        return 0
    fi

    print_error "公共网络创建失败：$SHARED_NETWORK_NAME"
    print_error "Docker返回信息：$network_output"
    return 1
}

get_compose_file() {
    local component=$1
    local architecture=$2
    
    if [ "$architecture" = "multi" ]; then
        echo "$MULTI_COMPOSE_FILE"
    else
        local index=0
        for comp in "${COMPONENTS[@]}"; do
            if [ "$comp" = "$component" ]; then
                echo "${SINGLE_COMPOSE_FILES[$index]}"
                return
            fi
            ((index++))
        done
        print_error "Unknown component: $component"
        exit 1
    fi
}

get_image_name() {
    local component=$1
    local architecture=$2
    
    if [ "$architecture" = "multi" ]; then
        echo "bigdata-all-in-one:latest"
    else
        # Hadoop HA使用相同的镜像，但不同的配置
        if [ "$component" = "hadoop-ha" ]; then
            echo "bigdata-hadoop:latest"
        else
            echo "bigdata-$component:latest"
        fi
    fi
}

get_dockerfile() {
    local component=$1
    local architecture=$2
    
    if [ "$architecture" = "multi" ]; then
        echo "dockerfile.all-in-one"
    else
        # Hadoop HA使用相同的Dockerfile，但不同的配置
        if [ "$component" = "hadoop-ha" ]; then
            echo "dockerfile.hadoop"
        else
            echo "dockerfile.$component"
        fi
    fi
}

validate_component() {
    local component=$1
    local architecture=$2
    
    # 多架构模式下的"all"组件是有效的
    if [ "$architecture" = "multi" ] && [ "$component" = "all" ]; then
        return 0
    fi
    
    for comp in "${COMPONENTS[@]}"; do
        if [ "$comp" = "$component" ]; then
            return 0
        fi
    done
    
    print_error "Invalid component: $component"
    echo "Available components: ${COMPONENTS[*]}"
    exit 1
}

validate_architecture() {
    local architecture=$1
    
    if [ "$architecture" != "single" ] && [ "$architecture" != "multi" ]; then
        print_error "Invalid architecture: $architecture"
        echo "Available architectures: single, multi"
        exit 1
    fi
}

# Image management commands
build_base_image() {
    if [ ! -f "$BASE_DOCKERFILE" ]; then
        print_error "基础镜像 Dockerfile 不存在：$BASE_DOCKERFILE"
        return 1
    fi

    print_info "正在构建基础镜像：$BASE_IMAGE_NAME"
    print_info "Dockerfile：$BASE_DOCKERFILE"

    if docker build -t "$BASE_IMAGE_NAME" -f "$BASE_DOCKERFILE" .; then
        print_success "基础镜像构建成功：$BASE_IMAGE_NAME"
        return 0
    fi

    print_error "基础镜像构建失败：$BASE_IMAGE_NAME"
    return 1
}

# 读取目标 Dockerfile 的直接父镜像。只有直接继承 bigdata-base:latest 的
# 组件才在这里检查基础镜像；例如 MySQL 使用官方镜像，HBase/Hive 则直接
# 继承 bigdata-hadoop:latest，应由各自的上游依赖检查与文档负责说明。
check_base_image_dependency() {
    local dockerfile=$1
    local parent_image

    parent_image=$(awk 'toupper($1) == "FROM" { print $2; exit }' "$dockerfile")
    if [ "$parent_image" != "$BASE_IMAGE_NAME" ]; then
        return 0
    fi

    print_info "检查组件构建依赖：$BASE_IMAGE_NAME"
    if docker image inspect "$BASE_IMAGE_NAME" >/dev/null 2>&1; then
        print_success "基础镜像已存在：$BASE_IMAGE_NAME"
        return 0
    fi

    print_error "缺少组件构建所需的基础镜像：$BASE_IMAGE_NAME"
    print_error "请先在镜像管理菜单选择 Build Base Image，或执行以下命令："
    echo "  Windows: .\\bigdata-cli.bat build-base"
    echo "  Linux/WSL: bash bigdata-cli.sh build-base"
    return 1
}

build_image() {
    local component=$1
    local architecture=$2
    
    validate_component "$component" "$architecture"
    validate_architecture "$architecture"
    
    local dockerfile=$(get_dockerfile "$component" "$architecture")
    local image_name=$(get_image_name "$component" "$architecture")
    
    if [ ! -f "$dockerfile" ]; then
        print_error "Dockerfile not found: $dockerfile"
        return 1
    fi

    if ! check_base_image_dependency "$dockerfile"; then
        print_error "已取消构建组件镜像：$image_name"
        return 1
    fi

    if ! ensure_shared_network "$architecture"; then
        print_error "Image build cancelled because the shared network is unavailable"
        return 1
    fi
    
    print_info "Building image: $image_name"
    
    if docker build -t "$image_name" -f "$dockerfile" .; then
        print_success "Image built successfully: $image_name"
        return 0
    else
        print_error "Image build failed"
        return 1
    fi
}

delete_image() {
    local component=$1
    local architecture=$2
    
    validate_component "$component" "$architecture"
    validate_architecture "$architecture"
    
    local image_name=$(get_image_name "$component" "$architecture")
    
    print_info "Deleting image: $image_name"
    
    if docker image rm "$image_name" 2>/dev/null; then
        print_success "Image deleted successfully: $image_name"
    else
        print_warning "Image not found or could not be deleted: $image_name"
    fi
}

# Container lifecycle commands
start_containers() {
    local component=$1
    local architecture=$2
    
    validate_component "$component" "$architecture"
    validate_architecture "$architecture"
    
    local compose_file=$(get_compose_file "$component" "$architecture")
    
    if [ ! -f "$compose_file" ]; then
        print_error "Docker Compose file not found: $compose_file"
        return 1
    fi

    if ! ensure_shared_network "$architecture"; then
        print_error "Container startup cancelled because the shared network is unavailable"
        return 1
    fi
    
    print_info "Starting $architecture architecture $component containers"
    
    if "${COMPOSE_CMD[@]}" -f "$compose_file" up -d; then
        print_success "Containers started successfully"
        return 0
    else
        print_error "Container startup failed"
        return 1
    fi
}

stop_containers() {
    local component=$1
    local architecture=$2
    
    validate_component "$component" "$architecture"
    validate_architecture "$architecture"
    
    local compose_file=$(get_compose_file "$component" "$architecture")
    
    if [ ! -f "$compose_file" ]; then
        print_error "Docker Compose file not found: $compose_file"
        return 1
    fi
    
    print_info "Stopping $architecture architecture $component containers"
    
    if "${COMPOSE_CMD[@]}" -f "$compose_file" stop; then
        print_success "Containers stopped successfully"
    else
        print_warning "Container stop failed or containers not running"
    fi
}

destroy_containers() {
    local component=$1
    local architecture=$2
    
    validate_component "$component" "$architecture"
    validate_architecture "$architecture"
    
    local compose_file=$(get_compose_file "$component" "$architecture")
    
    if [ ! -f "$compose_file" ]; then
        print_error "Docker Compose file not found: $compose_file"
        return 1
    fi
    
    print_info "Destroying $architecture architecture $component containers"
    
    if "${COMPOSE_CMD[@]}" -f "$compose_file" down; then
        print_success "Containers destroyed successfully"
    else
        print_warning "Container destruction failed"
    fi
}

restart_containers() {
    local component=$1
    local architecture=$2
    
    print_info "Restarting $architecture architecture $component containers"
    
    stop_containers "$component" "$architecture"
    start_containers "$component" "$architecture"
}

clean_containers() {
    local component=$1
    local architecture=$2
    
    validate_component "$component" "$architecture"
    validate_architecture "$architecture"
    
    local compose_file=$(get_compose_file "$component" "$architecture")
    
    if [ ! -f "$compose_file" ]; then
        print_error "Docker Compose file not found: $compose_file"
        return 1
    fi
    
    print_info "Cleaning $architecture architecture $component containers and associated volumes"
    
    # 这里只清理所选 Compose 中声明的资源，不删除其他组件，也不清理系统级悬空卷。
    if "${COMPOSE_CMD[@]}" -f "$compose_file" down -v; then
        print_success "Component containers and associated volumes cleaned successfully"
    else
        print_warning "Cleanup failed"
        return 1
    fi
}

# 清理本项目的全部部署资源。
# 交互菜单中的“清理容器、网络和卷”是全局动作，因此不再要求选择架构或组件。
# 镜像、宿主机 bind mount 数据目录，以及其他 Docker 项目的资源不会被删除。
clean_all_project_resources() {
    local compose_file
    local cleanup_failed=false
    local compose_files=("${SINGLE_COMPOSE_FILES[@]}" "$MULTI_COMPOSE_FILE")

    print_info "开始清理本项目的全部容器、Compose 网络和关联卷"

    for compose_file in "${compose_files[@]}"; do
        if [ ! -f "$compose_file" ]; then
            print_warning "跳过不存在的 Compose 文件：$compose_file"
            continue
        fi

        print_info "正在清理：$compose_file"
        if "${COMPOSE_CMD[@]}" -f "$compose_file" down -v; then
            print_success "已完成：$compose_file"
        else
            print_error "清理失败：$compose_file"
            cleanup_failed=true
        fi
    done

    # 独立组件使用外部网络，Compose down 不会主动删除它；全项目清理时单独处理。
    if docker network inspect "$SHARED_NETWORK_NAME" >/dev/null 2>&1; then
        print_info "正在删除独立组件公共网络：$SHARED_NETWORK_NAME"
        if docker network rm "$SHARED_NETWORK_NAME" >/dev/null; then
            print_success "公共网络已删除：$SHARED_NETWORK_NAME"
        else
            print_error "公共网络删除失败：$SHARED_NETWORK_NAME"
            print_error "可能仍有本项目以外的容器连接到该网络，请执行 docker network inspect $SHARED_NETWORK_NAME 检查"
            cleanup_failed=true
        fi
    else
        print_info "公共网络不存在，无需删除：$SHARED_NETWORK_NAME"
    fi

    if [ "$cleanup_failed" = "true" ]; then
        print_error "全项目清理未完全成功，请根据上方失败环节继续排查"
        return 1
    fi

    print_success "本项目全部容器、网络和关联卷清理完成"
}

clean_all_volumes() {
    print_info "Cleaning all unused volumes in the system"
    
    local unused_volumes=$(docker volume ls -qf dangling=true)
    if [ -n "$unused_volumes" ]; then
        echo "$unused_volumes" | xargs -r docker volume rm
        print_success "All unused volumes cleaned: $(echo "$unused_volumes" | wc -l) volumes removed"
    else
        print_info "No unused volumes found in the system"
    fi
}

# Status and logs commands
show_status() {
    local component=$1
    local architecture=$2
    
    validate_component "$component" "$architecture"
    validate_architecture "$architecture"
    
    local compose_file=$(get_compose_file "$component" "$architecture")
    
    if [ ! -f "$compose_file" ]; then
        print_error "Docker Compose file not found: $compose_file"
        return 1
    fi
    
    echo -e "${BLUE}=== $architecture architecture $component container status ===${NC}"
    "${COMPOSE_CMD[@]}" -f "$compose_file" ps
}

show_logs() {
    local component=$1
    local architecture=$2
    local follow=$3
    
    validate_component "$component" "$architecture"
    validate_architecture "$architecture"
    
    local compose_file=$(get_compose_file "$component" "$architecture")
    
    if [ ! -f "$compose_file" ]; then
        print_error "Docker Compose file not found: $compose_file"
        return 1
    fi
    
    echo -e "${BLUE}=== $architecture architecture $component container logs ===${NC}"
    
    if [ "$follow" = "true" ]; then
        "${COMPOSE_CMD[@]}" -f "$compose_file" logs -f
    else
        "${COMPOSE_CMD[@]}" -f "$compose_file" logs
    fi
}

show_supervisor_status() {
    local component=$1
    local architecture=$2
    
    validate_component "$component" "$architecture"
    validate_architecture "$architecture"
    
    # Supervisor状态查看仅适用于多架构模式
    if [ "$architecture" != "multi" ]; then
        print_error "Supervisor status is only available for multi-architecture clusters"
        return 1
    fi
    
    local compose_file=$(get_compose_file "$component" "$architecture")
    
    if [ ! -f "$compose_file" ]; then
        print_error "Docker Compose file not found: $compose_file"
        return 1
    fi
    
    echo -e "${BLUE}=== Supervisor Status for $architecture architecture $component ===${NC}"
    echo ""
    
    # 获取多架构集群中的所有容器
    local containers=$("${COMPOSE_CMD[@]}" -f "$compose_file" ps -q)
    
    if [ -z "$containers" ]; then
        print_warning "No containers found for the cluster"
        return 1
    fi
    
    # 检查每个容器中的Supervisor状态
    for container in $containers; do
        local container_name=$(docker inspect --format='{{.Name}}' "$container" | sed 's/^\///')
        echo -e "${YELLOW}=== Container: $container_name ===${NC}"
        
        # 检查容器中是否运行Supervisor
        if docker exec "$container" ps aux | grep -q supervisor; then
            echo "Supervisor is running"
            
            # 查看Supervisor进程状态
            echo -e "${GREEN}--- Supervisor Process Status ---${NC}"
            docker exec "$container" supervisorctl status
            
            # 查看Supervisor配置的进程
            echo -e "${GREEN}--- Supervisor Configuration ---${NC}"
            docker exec "$container" supervisorctl avail
            
            # 查看Supervisor日志
            echo -e "${GREEN}--- Supervisor Logs (last 10 lines) ---${NC}"
            docker exec "$container" tail -n 10 /var/log/supervisor/supervisord.log 2>/dev/null || echo "No supervisor logs found"
        else
            echo "Supervisor is not running in this container"
        fi
        echo ""
    done
}

# Test command
test_component() {
    local component=$1
    local architecture=$2
    
    validate_component "$component" "$architecture"
    validate_architecture "$architecture"
    
    local compose_file=$(get_compose_file "$component" "$architecture")
    
    if [ ! -f "$compose_file" ]; then
        print_error "Docker Compose file not found: $compose_file"
        return 1
    fi
    
    print_info "Testing component: $component ($architecture architecture)"
    
    # 检查容器状态
    if "${COMPOSE_CMD[@]}" -f "$compose_file" ps | grep -q "Up"; then
        print_success "Component is running"
    else
        print_error "Component is not running"
        return 1
    fi
    
    # 多架构模式下的全栈测试
    if [ "$architecture" = "multi" ] && [ "$component" = "all" ]; then
        print_info "Running full-stack cluster test suite..."
        
        local cluster_test_script="test/cluster-test.sh"
        if [ ! -f "$cluster_test_script" ]; then
            print_error "Cluster test script not found: $cluster_test_script"
            return 1
        fi
        
        chmod +x "$cluster_test_script"
        
        if "$cluster_test_script"; then
            print_success "Full-stack cluster test completed successfully"
        else
            print_error "Full-stack cluster test failed"
            return 1
        fi
        return 0
    fi
    
    # 单架构模式下使用对应的测试脚本
    if [ "$architecture" = "single" ]; then
        local test_script="test/test-${component}.sh"
        
        if [ -f "$test_script" ]; then
            print_info "Running test script: $test_script"
            chmod +x "$test_script"
            
            if "$test_script"; then
                print_success "Component test completed successfully"
            else
                print_error "Component test failed"
                return 1
            fi
        else
            print_warning "Test script not found: $test_script"
            print_info "Performing basic connectivity test..."
            
            # 基本连接性测试：检查容器是否在运行
            local running_containers=$("${COMPOSE_CMD[@]}" -f "$compose_file" ps --services --filter "status=running" 2>/dev/null)
            if [ -n "$running_containers" ]; then
                print_success "Component containers are running: $running_containers"
            else
                print_error "No running containers found"
                return 1
            fi
        fi
    fi
    
    return 0
}

# List available components
list_components() {
    echo -e "${BLUE}=== Available Components ===${NC}"
    for component in "${COMPONENTS[@]}"; do
        echo "  - $component"
    done
    
    echo -e "\n${BLUE}=== Architecture Types ===${NC}"
    echo "  - single: Single-component independent clusters"
    echo "  - multi: 5-node full-stack cluster"
    
    echo -e "\n${BLUE}=== Usage Examples ===${NC}"
    echo "  Start Hadoop single-component cluster: $0 start hadoop"
    echo "  Start full-stack cluster: $0 --architecture multi start all"
    echo "  Check ZooKeeper status: $0 status zookeeper"
    echo "  Test Kafka component: $0 test kafka"
}

# Help information
show_help() {
    echo "BigData Platform CLI Management Tool"
    echo ""
    echo "Usage Methods:"
    echo "  1. Interactive Mode (Recommended for beginners): Run script directly, select operations via menu"
    echo "  2. Command Line Mode: Use parameters and commands to execute operations directly"
    echo ""
    echo "Interactive Mode:"
    echo "  $0                      # Start interactive menu"
    echo ""
    echo "Command Line Mode:"
    echo "  $0 build-base"
    echo "  $0 [options] <command> <component>"
    echo ""
    echo "Options:"
    echo "  -a, --architecture <arch>    Architecture type: single(default) or multi"
    echo "  -h, --help                  Show this help message"
    echo ""
    echo "Commands:"
    echo "  build-base                  Build bigdata-base:latest"
    echo "  build <component>           Build Docker image"
    echo "  delete <component>          Delete Docker image"
    echo "  start <component>           Start containers"
    echo "  stop <component>            Stop containers"
    echo "  destroy <component>         Destroy containers"
    echo "  restart <component>         Restart containers"
    echo "  clean <component>           Clean containers, networks and volumes"
    echo "  status <component>          Show container status"
    echo "  logs <component> [-f]       Show container logs (-f for follow)"
    echo "  supervisor <component>      Show supervisor status (multi-architecture only)"
    echo "  test <component>            Test component functionality"
    echo "  list                        List available components"
    echo "  clean-volumes               Clean all unused volumes in the system"
    echo ""
    echo "Components: hadoop, hadoop-ha, zookeeper, hbase, hive, kafka, spark, flink, flume, mysql"
    echo ""
    echo "Examples:"
    echo "  $0                           # Start interactive menu"
    echo "  $0 build-base                # Build the shared base image"
    echo "  $0 start hadoop              # Start Hadoop single-component cluster"
    echo "  $0 -a multi start all        # Start full-stack cluster"
    echo "  $0 status zookeeper          # Check ZooKeeper status"
    echo "  $0 logs kafka -f             # Follow Kafka logs in real-time"
    echo "  $0 -a multi supervisor all   # Check supervisor status for full cluster"
}

# Interactive menu functions
show_main_menu() {
    echo -e "${BLUE}=== BigData Platform CLI Management Tool ===${NC}"
    echo ""
    echo "Select operation type:"
    echo "1. Image Management (Build/Delete images)"
    echo "2. Container Lifecycle Management (Start/Stop/Restart etc)"
    echo "3. Status Monitoring (View status/logs)"
    echo "4. Component Testing"
    echo "5. List Available Components"
    echo "6. Command Line Mode"
    echo "0. Exit"
    echo ""
    echo -n "Enter your choice (0-6): "
}

show_architecture_menu() {
    echo -e "${BLUE}=== Select Architecture ===${NC}"
    echo ""
    echo "1. Single-component Architecture (Each component runs independently)"
    echo "2. Multi-component Architecture (5-node full-stack cluster)"
    echo "0. Back to Main Menu"
    echo ""
    echo -n "Enter your choice (0-2): "
}

show_component_menu() {
    local architecture=$1
    echo -e "${BLUE}=== Select Component ===${NC}"
    echo ""
    
    if [ "$architecture" = "multi" ]; then
        echo "1. All Components (Full-stack cluster)"
        echo "0. Back to Architecture Selection"
        echo ""
        echo -n "Enter your choice (0-1): "
    else
        local index=1
        for component in "${COMPONENTS[@]}"; do
            echo "$index. $component"
            ((index++))
        done
        echo "0. Back to Architecture Selection"
        echo ""
        echo -n "Enter your choice (0-$((index-1))): "
    fi
}

show_image_management_menu() {
    echo -e "${BLUE}=== Image Management ===${NC}"
    echo ""
    echo "1. Build Base Image"
    echo "2. Build Component Image"
    echo "3. Delete Component Image"
    echo "0. Back to Main Menu"
    echo ""
    echo -n "Enter your choice (0-3): "
}

show_container_management_menu() {
    echo -e "${BLUE}=== Container Lifecycle Management ===${NC}"
    echo ""
    echo "1. Start Container"
    echo "2. Stop Container"
    echo "3. Destroy Container"
    echo "4. Restart Container"
    echo "5. Clean ALL Project Containers, Networks and Volumes"
    echo "6. Clean All Unused Volumes (System-wide)"
    echo "0. Back to Main Menu"
    echo ""
    echo -n "Enter your choice (0-6): "
}

show_status_menu() {
    echo -e "${BLUE}=== Status Monitoring ===${NC}"
    echo ""
    echo "1. View Container Status"
    echo "2. View Container Logs"
    echo "3. Follow Container Logs (Real-time)"
    echo "4. View Supervisor Status (Multi-architecture only)"
    echo "0. Back to Main Menu"
    echo ""
    echo -n "Enter your choice (0-4): "
}

get_component_by_index() {
    local index=$1
    if [ "$index" -eq $((${#COMPONENTS[@]} + 1)) ]; then
        echo "all"
    elif [ "$index" -ge 1 ] && [ "$index" -le ${#COMPONENTS[@]} ]; then
        echo "${COMPONENTS[$((index-1))]}"
    else
        echo ""
    fi
}

interactive_mode() {
    while true; do
        show_main_menu
        if ! read -r choice; then
            echo ""
            print_info "Input closed, exiting interactive mode"
            return 0
        fi
        choice="${choice%$'\r'}"
        
        case $choice in
            1) # Image Management
                interactive_image_management
                ;;
            2) # Container Management
                interactive_container_management
                ;;
            3) # Status Monitoring
                interactive_status_management
                ;;
            4) # Component Testing
                interactive_testing
                ;;
            5) # List Components
                list_components
                ;;
            6) # Command Line Mode
                show_help
                return
                ;;
            0) # Exit
                echo "Thank you for using BigData CLI Tool!"
                exit 0
                ;;
            *)
                print_error "Invalid choice, please try again"
                ;;
        esac
    done
}

interactive_image_management() {
    while true; do
        show_image_management_menu
        if ! read -r choice; then
            echo ""
            print_info "Input closed, returning to previous menu"
            return
        fi
        choice="${choice%$'\r'}"
        
        case $choice in
            1) # Build Base Image
                build_base_image
                ;;
            2) # Build Component Image
                if select_component_and_architecture; then
                    build_image "$selected_component" "$selected_architecture"
                fi
                ;;
            3) # Delete Component Image
                if select_component_and_architecture; then
                    delete_image "$selected_component" "$selected_architecture"
                fi
                ;;
            0) # Back
                return
                ;;
            *)
                print_error "Invalid choice, please try again"
                ;;
        esac
    done
}

interactive_container_management() {
    while true; do
        show_container_management_menu
        if ! read -r choice; then
            echo ""
            print_info "Input closed, returning to previous menu"
            return
        fi
        choice="${choice%$'\r'}"
        
        case $choice in
            1) # Start Containers
                if select_component_and_architecture; then
                    start_containers "$selected_component" "$selected_architecture"
                fi
                ;;
            2) # Stop Containers
                if select_component_and_architecture; then
                    stop_containers "$selected_component" "$selected_architecture"
                fi
                ;;
            4) # Restart Containers
                if select_component_and_architecture; then
                    restart_containers "$selected_component" "$selected_architecture"
                fi
                ;;
            3) # Destroy Containers
                if select_component_and_architecture; then
                    destroy_containers "$selected_component" "$selected_architecture"
                fi
                ;;
            5) # Clean all project containers, networks and volumes
                print_warning "该操作将删除本项目全部架构和组件的容器、Compose 网络及关联卷。"
                print_warning "Docker 镜像和宿主机目录映射中的数据不会被删除。确认继续？(y/N): "
                if ! read -r confirm; then
                    print_info "输入已关闭，全项目清理已取消"
                    return
                fi
                confirm="${confirm%$'\r'}"
                if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                    clean_all_project_resources
                else
                    print_info "全项目清理已取消"
                fi
                ;;
            6) # Clean All Volumes
                print_warning "This will clean ALL unused volumes in the system. Are you sure? (y/N): "
                if ! read -r confirm; then
                    print_info "Input closed, volume cleanup cancelled"
                    return
                fi
                confirm="${confirm%$'\r'}"
                if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                    clean_all_volumes
                else
                    print_info "Volume cleanup cancelled"
                fi
                ;;
            0) # Back
                return
                ;;
            *)
                print_error "Invalid choice, please try again"
                ;;
        esac
        
        echo ""
        echo "Press Enter to continue..."
        read -r || return
    done
}

interactive_status_management() {
    while true; do
        show_status_menu
        if ! read -r choice; then
            echo ""
            print_info "Input closed, returning to previous menu"
            return
        fi
        choice="${choice%$'\r'}"
        
        case $choice in
            1) # View Status
                if select_component_and_architecture; then
                    show_status "$selected_component" "$selected_architecture"
                fi
                ;;
            2) # View Logs
                if select_component_and_architecture; then
                    show_logs "$selected_component" "$selected_architecture" "false"
                fi
                ;;
            3) # Follow Logs
                if select_component_and_architecture; then
                    show_logs "$selected_component" "$selected_architecture" "true"
                fi
                ;;
            4) # Supervisor Status
                if select_component_and_architecture; then
                    show_supervisor_status "$selected_component" "$selected_architecture"
                fi
                ;;
            0) # Back
                break
                ;;
            *)
                print_error "Invalid choice, please try again"
                ;;
        esac
        
        echo ""
        echo "Press Enter to continue..."
        read -r || return
    done
}

interactive_testing() {
    if select_component_and_architecture; then
        test_component "$selected_component" "$selected_architecture"
    fi
}

select_component_and_architecture() {
    # 先选择架构
    while true; do
        show_architecture_menu
        if ! read -r arch_choice; then
            echo ""
            print_info "Input closed, cancelling selection"
            return 1
        fi
        arch_choice="${arch_choice%$'\r'}"
        
        case $arch_choice in
            1)
                selected_architecture="single"
                break
                ;;
            2)
                selected_architecture="multi"
                break
                ;;
            0)
                return 1
                ;;
            *)
                print_error "Invalid architecture choice, please try again"
                ;;
        esac
    done
    
    # 根据架构选择组件
    while true; do
        show_component_menu "$selected_architecture"
        if ! read -r component_choice; then
            echo ""
            print_info "Input closed, cancelling selection"
            return 1
        fi
        component_choice="${component_choice%$'\r'}"
        
        if [ "$component_choice" = "0" ]; then
            # 返回架构选择
            return 1
        fi
        
        if [ "$selected_architecture" = "multi" ]; then
            # 多架构模式下只有"所有组件"选项
            if [ "$component_choice" = "1" ]; then
                selected_component="all"
                break
            else
                print_error "Invalid choice, please try again"
            fi
        else
            # 单架构模式下选择具体组件
            selected_component=$(get_component_by_index "$component_choice")
            if [ -n "$selected_component" ]; then
                break
            else
                print_error "Invalid component choice, please try again"
            fi
        fi
    done
    
    return 0
}

# Main function
main() {
    # Check dependencies
    check_dependencies
    
    # Default architecture
    local architecture="single"
    local command=""
    local component=""
    local follow_logs=false
    
    # If no arguments provided, start interactive mode
    if [ $# -eq 0 ]; then
        interactive_mode
        return
    fi
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -a|--architecture)
                architecture="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -f)
                follow_logs=true
                shift
                ;;
            build|delete|start|stop|destroy|restart|clean|status|logs|supervisor|test|list)
                command="$1"
                if [ "$1" != "list" ]; then
                    component="$2"
                    shift 2
                else
                    shift
                fi
                ;;
            build-base)
                command="build-base"
                shift
                ;;
            clean-volumes)
                command="clean-volumes"
                shift
                ;;
            *)
                print_error "Unknown parameter: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Validate architecture
    validate_architecture "$architecture"
    
    # Execute command
    case $command in
        build-base)
            build_base_image
            ;;
        build)
            build_image "$component" "$architecture"
            ;;
        delete)
            delete_image "$component" "$architecture"
            ;;
        start)
            start_containers "$component" "$architecture"
            ;;
        stop)
            stop_containers "$component" "$architecture"
            ;;
        destroy)
            destroy_containers "$component" "$architecture"
            ;;
        restart)
            restart_containers "$component" "$architecture"
            ;;
        clean)
            clean_containers "$component" "$architecture"
            ;;
        status)
        show_status "$component" "$architecture"
        ;;
    logs)
        show_logs "$component" "$architecture" "$follow_logs"
        ;;
    supervisor)
        show_supervisor_status "$component" "$architecture"
        ;;
    test)
        test_component "$component" "$architecture"
        ;;
    list)
        list_components
        ;;
    clean-volumes)
        clean_all_volumes
        ;;
    "")
        show_help
        ;;
    *)
        print_error "Unknown command: $command"
        show_help
        exit 1
        ;;
esac
}

# Run main function
main "$@"
