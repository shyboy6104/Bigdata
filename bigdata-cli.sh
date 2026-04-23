#!/bin/bash
# BigData Platform CLI Management Tool
# Supports both single-component and multi-component Docker container management

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
    
    if ! command -v docker-compose &> /dev/null; then
        print_error "Docker Compose not installed or not in PATH"
        exit 1
    fi
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
    
    print_info "Starting $architecture architecture $component containers"
    
    if docker-compose -f "$compose_file" up -d; then
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
    
    if docker-compose -f "$compose_file" stop; then
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
    
    if docker-compose -f "$compose_file" down; then
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
    
    print_info "Cleaning $architecture architecture $component containers, networks and volumes"
    
    # 停止并删除容器、网络和关联的卷
    if docker-compose -f "$compose_file" down -v --remove-orphans; then
        print_success "Containers, networks and volumes cleaned successfully"
        
        # 额外清理：删除未使用的卷（可选，更彻底）
        print_info "Cleaning unused volumes..."
        local unused_volumes=$(docker volume ls -qf dangling=true)
        if [ -n "$unused_volumes" ]; then
            echo "$unused_volumes" | xargs -r docker volume rm
            print_success "Unused volumes cleaned"
        else
            print_info "No unused volumes found"
        fi
    else
        print_warning "Cleanup failed"
    fi
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
    docker-compose -f "$compose_file" ps
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
        docker-compose -f "$compose_file" logs -f
    else
        docker-compose -f "$compose_file" logs
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
    local containers=$(docker-compose -f "$compose_file" ps -q)
    
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
    if docker-compose -f "$compose_file" ps | grep -q "Up"; then
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
            local running_containers=$(docker-compose -f "$compose_file" ps --services --filter "status=running" 2>/dev/null)
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
    echo "  $0 [options] <command> <component>"
    echo ""
    echo "Options:"
    echo "  -a, --architecture <arch>    Architecture type: single(default) or multi"
    echo "  -h, --help                  Show this help message"
    echo ""
    echo "Commands:"
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
    echo "  $0 start hadoop              # Start Hadoop single-component cluster"
    echo "  $0 -a multi start all        # Start full-stack cluster"
    echo "  $0 status zookeeper          # Check ZooKeeper status"
    echo "  $0 logs kafka -f             # Follow Kafka logs in real-time"
    echo "  $0 supervisor all            # Check supervisor status for full cluster"
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
    echo "1. Build Image"
    echo "2. Delete Image"
    echo "0. Back to Main Menu"
    echo ""
    echo -n "Enter your choice (0-2): "
}

show_container_management_menu() {
    echo -e "${BLUE}=== Container Lifecycle Management ===${NC}"
    echo ""
    echo "1. Start Container"
    echo "2. Stop Container"
    echo "3. Destroy Container"
    echo "4. Restart Container"
    echo "5. Clean Containers, Networks and Volumes"
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
        read choice
        
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
        read choice
        
        case $choice in
            1) # Build Image
                if select_component_and_architecture; then
                    build_image "$selected_component" "$selected_architecture"
                fi
                ;;
            2) # Delete Image
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
        read choice
        
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
            5) # Clean Containers
                if select_component_and_architecture; then
                    clean_containers "$selected_component" "$selected_architecture"
                fi
                ;;
            6) # Clean All Volumes
                print_warning "This will clean ALL unused volumes in the system. Are you sure? (y/N): "
                read confirm
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
        read
    done
}

interactive_status_management() {
    while true; do
        show_status_menu
        read choice
        
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
        read
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
        read arch_choice
        
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
        read component_choice
        
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