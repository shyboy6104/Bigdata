#!/bin/bash
# BigData 平台 CLI 管理工具（中文版）
# 同时支持单组件与多组件（全栈集群）Docker 容器管理
# 功能与 bigdata-cli.sh 完全一致，仅将用户可见的提示、菜单、帮助、错误信息和注释汉化。

# 脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || {
    echo "[错误] 无法进入项目目录：$SCRIPT_DIR" >&2
    exit 1
}

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 配置
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

# 输出函数
print_info() {
    echo -e "${BLUE}[信息]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

print_error() {
    echo -e "${RED}[错误]${NC} $1"
}

check_dependencies() {
    if ! command -v docker &> /dev/null; then
        print_error "未安装 Docker，或不在 PATH 中"
        exit 1
    fi

    if docker compose version &> /dev/null; then
        COMPOSE_CMD=(docker compose)
    elif command -v docker-compose &> /dev/null; then
        COMPOSE_CMD=(docker-compose)
    else
        print_error "未安装 Docker Compose，或不在 PATH 中"
        exit 1
    fi
}

# 确保独立组件的 Compose 项目能加入同一个网络。
# 该操作是幂等的：已存在的网络保持不变。
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
        print_info "Docker 返回的网络标识：$network_output"
        return 0
    fi

    print_error "公共网络创建失败：$SHARED_NETWORK_NAME"
    print_error "Docker 返回信息：$network_output"
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
        print_error "未知组件：$component"
        exit 1
    fi
}

get_image_name() {
    local component=$1
    local architecture=$2

    if [ "$architecture" = "multi" ]; then
        echo "bigdata-all-in-one:latest"
    else
        # Hadoop HA 使用相同的镜像，但不同的配置
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
        # Hadoop HA 使用相同的 Dockerfile，但不同的配置
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

    print_error "无效组件：$component"
    echo "可用组件：${COMPONENTS[*]}"
    exit 1
}

validate_architecture() {
    local architecture=$1

    if [ "$architecture" != "single" ] && [ "$architecture" != "multi" ]; then
        print_error "无效架构：$architecture"
        echo "可用架构：single、multi"
        exit 1
    fi
}

# 镜像管理命令
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
    print_error "请先在镜像管理菜单选择「构建基础镜像」，或执行以下命令："
    echo "  Windows：.\\bigdata-cli-zh.bat build-base"
    echo "  Linux/WSL：bash bigdata-cli-zh.sh build-base"
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
        print_error "Dockerfile 不存在：$dockerfile"
        return 1
    fi

    if ! check_base_image_dependency "$dockerfile"; then
        print_error "已取消构建组件镜像：$image_name"
        return 1
    fi

    if ! ensure_shared_network "$architecture"; then
        print_error "公共网络不可用，已取消构建组件镜像"
        return 1
    fi

    print_info "正在构建镜像：$image_name"

    if docker build -t "$image_name" -f "$dockerfile" .; then
        print_success "镜像构建成功：$image_name"
        return 0
    else
        print_error "镜像构建失败"
        return 1
    fi
}

delete_image() {
    local component=$1
    local architecture=$2

    validate_component "$component" "$architecture"
    validate_architecture "$architecture"

    local image_name=$(get_image_name "$component" "$architecture")

    print_info "正在删除镜像：$image_name"

    if docker image rm "$image_name" 2>/dev/null; then
        print_success "镜像删除成功：$image_name"
    else
        print_warning "镜像不存在或无法删除：$image_name"
    fi
}

# 容器生命周期命令
start_containers() {
    local component=$1
    local architecture=$2

    validate_component "$component" "$architecture"
    validate_architecture "$architecture"

    local compose_file=$(get_compose_file "$component" "$architecture")

    if [ ! -f "$compose_file" ]; then
        print_error "Docker Compose 文件不存在：$compose_file"
        return 1
    fi

    if ! ensure_shared_network "$architecture"; then
        print_error "公共网络不可用，已取消启动容器"
        return 1
    fi

    print_info "正在启动 $architecture 架构的 $component 容器"

    if "${COMPOSE_CMD[@]}" -f "$compose_file" up -d; then
        print_success "容器启动成功"
        return 0
    else
        print_error "容器启动失败"
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
        print_error "Docker Compose 文件不存在：$compose_file"
        return 1
    fi

    print_info "正在停止 $architecture 架构的 $component 容器"

    if "${COMPOSE_CMD[@]}" -f "$compose_file" stop; then
        print_success "容器已停止"
    else
        print_warning "容器停止失败，或容器未在运行"
    fi
}

destroy_containers() {
    local component=$1
    local architecture=$2

    validate_component "$component" "$architecture"
    validate_architecture "$architecture"

    local compose_file=$(get_compose_file "$component" "$architecture")

    if [ ! -f "$compose_file" ]; then
        print_error "Docker Compose 文件不存在：$compose_file"
        return 1
    fi

    print_info "正在销毁 $architecture 架构的 $component 容器"

    if "${COMPOSE_CMD[@]}" -f "$compose_file" down; then
        print_success "容器已销毁"
    else
        print_warning "容器销毁失败"
    fi
}

restart_containers() {
    local component=$1
    local architecture=$2

    print_info "正在重启 $architecture 架构的 $component 容器"

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
        print_error "Docker Compose 文件不存在：$compose_file"
        return 1
    fi

    print_info "正在清理 $architecture 架构的 $component 容器及关联卷"

    # 这里只清理所选 Compose 中声明的资源，不删除其他组件，也不清理系统级悬空卷。
    if "${COMPOSE_CMD[@]}" -f "$compose_file" down -v; then
        print_success "组件容器及关联卷已清理"
    else
        print_warning "清理失败"
        return 1
    fi
}

# 清理本项目的全部部署资源。
# 交互菜单中的「清理容器、网络和卷」是全局动作，因此不再要求选择架构或组件。
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
    print_info "正在清理系统内全部未使用的卷"

    local unused_volumes=$(docker volume ls -qf dangling=true)
    if [ -n "$unused_volumes" ]; then
        echo "$unused_volumes" | xargs -r docker volume rm
        print_success "全部未使用的卷已清理：共 $(echo "$unused_volumes" | wc -l) 个"
    else
        print_info "系统内未发现未使用的卷"
    fi
}

# 状态与日志命令
show_status() {
    local component=$1
    local architecture=$2

    validate_component "$component" "$architecture"
    validate_architecture "$architecture"

    local compose_file=$(get_compose_file "$component" "$architecture")

    if [ ! -f "$compose_file" ]; then
        print_error "Docker Compose 文件不存在：$compose_file"
        return 1
    fi

    echo -e "${BLUE}=== $architecture 架构 $component 容器状态 ===${NC}"
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
        print_error "Docker Compose 文件不存在：$compose_file"
        return 1
    fi

    echo -e "${BLUE}=== $architecture 架构 $component 容器日志 ===${NC}"

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

    # Supervisor 状态查看仅适用于多架构模式
    if [ "$architecture" != "multi" ]; then
        print_error "Supervisor 状态仅适用于多架构集群"
        return 1
    fi

    local compose_file=$(get_compose_file "$component" "$architecture")

    if [ ! -f "$compose_file" ]; then
        print_error "Docker Compose 文件不存在：$compose_file"
        return 1
    fi

    echo -e "${BLUE}=== $architecture 架构 $component 的 Supervisor 状态 ===${NC}"
    echo ""

    # 获取多架构集群中的所有容器
    local containers=$("${COMPOSE_CMD[@]}" -f "$compose_file" ps -q)

    if [ -z "$containers" ]; then
        print_warning "未找到该集群的容器"
        return 1
    fi

    # 检查每个容器中的 Supervisor 状态
    for container in $containers; do
        local container_name=$(docker inspect --format='{{.Name}}' "$container" | sed 's/^\///')
        echo -e "${YELLOW}=== 容器：$container_name ===${NC}"

        # 检查容器中是否运行 Supervisor
        if docker exec "$container" ps aux | grep -q supervisor; then
            echo "Supervisor 正在运行"

            # 查看 Supervisor 进程状态
            echo -e "${GREEN}--- Supervisor 进程状态 ---${NC}"
            docker exec "$container" supervisorctl status

            # 查看 Supervisor 配置的进程
            echo -e "${GREEN}--- Supervisor 可用配置 ---${NC}"
            docker exec "$container" supervisorctl avail

            # 查看 Supervisor 日志
            echo -e "${GREEN}--- Supervisor 日志（最后 10 行）---${NC}"
            docker exec "$container" tail -n 10 /var/log/supervisor/supervisord.log 2>/dev/null || echo "未找到 Supervisor 日志"
        else
            echo "该容器中未运行 Supervisor"
        fi
        echo ""
    done
}

# 测试命令
test_component() {
    local component=$1
    local architecture=$2

    validate_component "$component" "$architecture"
    validate_architecture "$architecture"

    local compose_file=$(get_compose_file "$component" "$architecture")

    if [ ! -f "$compose_file" ]; then
        print_error "Docker Compose 文件不存在：$compose_file"
        return 1
    fi

    print_info "正在测试组件：$component（$architecture 架构）"

    # 检查容器状态
    if "${COMPOSE_CMD[@]}" -f "$compose_file" ps | grep -q "Up"; then
        print_success "组件正在运行"
    else
        print_error "组件未运行"
        return 1
    fi

    # 多架构模式下的全栈测试
    if [ "$architecture" = "multi" ] && [ "$component" = "all" ]; then
        print_info "正在运行全栈集群测试套件..."

        local cluster_test_script="test/cluster-test.sh"
        if [ ! -f "$cluster_test_script" ]; then
            print_error "集群测试脚本不存在：$cluster_test_script"
            return 1
        fi

        chmod +x "$cluster_test_script"

        if "$cluster_test_script"; then
            print_success "全栈集群测试已完成"
        else
            print_error "全栈集群测试失败"
            return 1
        fi
        return 0
    fi

    # 单架构模式下使用对应的测试脚本
    if [ "$architecture" = "single" ]; then
        local test_script="test/test-${component}.sh"

        if [ -f "$test_script" ]; then
            print_info "正在运行测试脚本：$test_script"
            chmod +x "$test_script"

            if "$test_script"; then
                print_success "组件测试已完成"
            else
                print_error "组件测试失败"
                return 1
            fi
        else
            print_warning "测试脚本不存在：$test_script"
            print_info "执行基本连通性测试..."

            # 基本连通性测试：检查容器是否在运行
            local running_containers=$("${COMPOSE_CMD[@]}" -f "$compose_file" ps --services --filter "status=running" 2>/dev/null)
            if [ -n "$running_containers" ]; then
                print_success "组件容器正在运行：$running_containers"
            else
                print_error "未找到运行中的容器"
                return 1
            fi
        fi
    fi

    return 0
}

# 列出可用组件
list_components() {
    echo -e "${BLUE}=== 可用组件 ===${NC}"
    for component in "${COMPONENTS[@]}"; do
        echo "  - $component"
    done

    echo -e "\n${BLUE}=== 架构类型 ===${NC}"
    echo "  - single：单组件独立集群"
    echo "  - multi：5 节点全栈集群"

    echo -e "\n${BLUE}=== 用法示例 ===${NC}"
    echo "  启动 Hadoop 单组件集群：$0 start hadoop"
    echo "  启动全栈集群：$0 --architecture multi start all"
    echo "  查看 ZooKeeper 状态：$0 status zookeeper"
    echo "  测试 Kafka 组件：$0 test kafka"
}

# 帮助信息
show_help() {
    echo "BigData 平台 CLI 管理工具（中文版）"
    echo ""
    echo "使用方式："
    echo "  1. 交互模式（推荐新手）：直接运行脚本，通过菜单选择操作"
    echo "  2. 命令行模式：使用参数和命令直接执行操作"
    echo ""
    echo "交互模式："
    echo "  $0                      # 启动交互菜单"
    echo ""
    echo "命令行模式："
    echo "  $0 build-base"
    echo "  $0 [选项] <命令> <组件>"
    echo ""
    echo "选项："
    echo "  -a, --architecture <arch>    架构类型：single（默认）或 multi"
    echo "  -h, --help                  显示本帮助信息"
    echo ""
    echo "命令："
    echo "  build-base                  构建 bigdata-base:latest"
    echo "  build <component>           构建 Docker 镜像"
    echo "  delete <component>          删除 Docker 镜像"
    echo "  start <component>           启动容器"
    echo "  stop <component>            停止容器"
    echo "  destroy <component>         销毁容器"
    echo "  restart <component>         重启容器"
    echo "  clean <component>           清理容器、网络和卷"
    echo "  status <component>          查看容器状态"
    echo "  logs <component> [-f]       查看容器日志（-f 实时跟随）"
    echo "  supervisor <component>      查看 Supervisor 状态（仅多架构）"
    echo "  test <component>            测试组件功能"
    echo "  list                        列出可用组件"
    echo "  clean-volumes               清理系统内全部未使用的卷"
    echo ""
    echo "组件：hadoop, hadoop-ha, zookeeper, hbase, hive, kafka, spark, flink, flume, mysql"
    echo ""
    echo "示例："
    echo "  $0                           # 启动交互菜单"
    echo "  $0 build-base                # 构建共享基础镜像"
    echo "  $0 start hadoop              # 启动 Hadoop 单组件集群"
    echo "  $0 -a multi start all        # 启动全栈集群"
    echo "  $0 status zookeeper          # 查看 ZooKeeper 状态"
    echo "  $0 logs kafka -f             # 实时跟随 Kafka 日志"
    echo "  $0 -a multi supervisor all   # 查看全栈集群的 Supervisor 状态"
}

# 交互菜单函数
show_main_menu() {
    echo -e "${BLUE}=== BigData 平台 CLI 管理工具 ===${NC}"
    echo ""
    echo "请选择操作类型："
    echo "1. 镜像管理（构建/删除镜像）"
    echo "2. 容器生命周期管理（启动/停止/重启等）"
    echo "3. 状态监控（查看状态/日志）"
    echo "4. 组件测试"
    echo "5. 列出可用组件"
    echo "6. 命令行模式（查看帮助）"
    echo "0. 退出"
    echo ""
    echo -n "请输入选项（0-6）："
}

show_architecture_menu() {
    echo -e "${BLUE}=== 选择架构 ===${NC}"
    echo ""
    echo "1. 单组件架构（各组件独立运行）"
    echo "2. 多组件架构（5 节点全栈集群）"
    echo "0. 返回主菜单"
    echo ""
    echo -n "请输入选项（0-2）："
}

show_component_menu() {
    local architecture=$1
    echo -e "${BLUE}=== 选择组件 ===${NC}"
    echo ""

    if [ "$architecture" = "multi" ]; then
        echo "1. 全部组件（全栈集群）"
        echo "0. 返回架构选择"
        echo ""
        echo -n "请输入选项（0-1）："
    else
        local index=1
        for component in "${COMPONENTS[@]}"; do
            echo "$index. $component"
            ((index++))
        done
        echo "0. 返回架构选择"
        echo ""
        echo -n "请输入选项（0-$((index-1))）："
    fi
}

show_image_management_menu() {
    echo -e "${BLUE}=== 镜像管理 ===${NC}"
    echo ""
    echo "1. 构建基础镜像"
    echo "2. 构建组件镜像"
    echo "3. 删除组件镜像"
    echo "0. 返回主菜单"
    echo ""
    echo -n "请输入选项（0-3）："
}

show_container_management_menu() {
    echo -e "${BLUE}=== 容器生命周期管理 ===${NC}"
    echo ""
    echo "1. 启动容器"
    echo "2. 停止容器"
    echo "3. 销毁容器"
    echo "4. 重启容器"
    echo "5. 清理本项目全部容器、网络和卷"
    echo "6. 清理系统内全部未使用的卷"
    echo "0. 返回主菜单"
    echo ""
    echo -n "请输入选项（0-6）："
}

show_status_menu() {
    echo -e "${BLUE}=== 状态监控 ===${NC}"
    echo ""
    echo "1. 查看容器状态"
    echo "2. 查看容器日志"
    echo "3. 实时跟随容器日志"
    echo "4. 查看 Supervisor 状态（仅多架构）"
    echo "0. 返回主菜单"
    echo ""
    echo -n "请输入选项（0-4）："
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
            print_info "输入已关闭，退出交互模式"
            return 0
        fi
        choice="${choice%$'\r'}"

        case $choice in
            1) # 镜像管理
                interactive_image_management
                ;;
            2) # 容器管理
                interactive_container_management
                ;;
            3) # 状态监控
                interactive_status_management
                ;;
            4) # 组件测试
                interactive_testing
                ;;
            5) # 列出组件
                list_components
                ;;
            6) # 命令行模式
                show_help
                return
                ;;
            0) # 退出
                echo "感谢使用 BigData CLI 工具！"
                exit 0
                ;;
            *)
                print_error "无效选项，请重新输入"
                ;;
        esac
    done
}

interactive_image_management() {
    while true; do
        show_image_management_menu
        if ! read -r choice; then
            echo ""
            print_info "输入已关闭，返回上级菜单"
            return
        fi
        choice="${choice%$'\r'}"

        case $choice in
            1) # 构建基础镜像
                build_base_image
                ;;
            2) # 构建组件镜像
                if select_component_and_architecture; then
                    build_image "$selected_component" "$selected_architecture"
                fi
                ;;
            3) # 删除组件镜像
                if select_component_and_architecture; then
                    delete_image "$selected_component" "$selected_architecture"
                fi
                ;;
            0) # 返回
                return
                ;;
            *)
                print_error "无效选项，请重新输入"
                ;;
        esac
    done
}

interactive_container_management() {
    while true; do
        show_container_management_menu
        if ! read -r choice; then
            echo ""
            print_info "输入已关闭，返回上级菜单"
            return
        fi
        choice="${choice%$'\r'}"

        case $choice in
            1) # 启动容器
                if select_component_and_architecture; then
                    start_containers "$selected_component" "$selected_architecture"
                fi
                ;;
            2) # 停止容器
                if select_component_and_architecture; then
                    stop_containers "$selected_component" "$selected_architecture"
                fi
                ;;
            4) # 重启容器
                if select_component_and_architecture; then
                    restart_containers "$selected_component" "$selected_architecture"
                fi
                ;;
            3) # 销毁容器
                if select_component_and_architecture; then
                    destroy_containers "$selected_component" "$selected_architecture"
                fi
                ;;
            5) # 清理本项目全部容器、网络和卷
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
            6) # 清理系统内全部未使用的卷
                print_warning "该操作将清理系统内全部未使用的卷。确认继续？(y/N): "
                if ! read -r confirm; then
                    print_info "输入已关闭，卷清理已取消"
                    return
                fi
                confirm="${confirm%$'\r'}"
                if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                    clean_all_volumes
                else
                    print_info "卷清理已取消"
                fi
                ;;
            0) # 返回
                return
                ;;
            *)
                print_error "无效选项，请重新输入"
                ;;
        esac

        echo ""
        echo "按回车键继续..."
        read -r || return
    done
}

interactive_status_management() {
    while true; do
        show_status_menu
        if ! read -r choice; then
            echo ""
            print_info "输入已关闭，返回上级菜单"
            return
        fi
        choice="${choice%$'\r'}"

        case $choice in
            1) # 查看状态
                if select_component_and_architecture; then
                    show_status "$selected_component" "$selected_architecture"
                fi
                ;;
            2) # 查看日志
                if select_component_and_architecture; then
                    show_logs "$selected_component" "$selected_architecture" "false"
                fi
                ;;
            3) # 跟随日志
                if select_component_and_architecture; then
                    show_logs "$selected_component" "$selected_architecture" "true"
                fi
                ;;
            4) # Supervisor 状态
                if select_component_and_architecture; then
                    show_supervisor_status "$selected_component" "$selected_architecture"
                fi
                ;;
            0) # 返回
                break
                ;;
            *)
                print_error "无效选项，请重新输入"
                ;;
        esac

        echo ""
        echo "按回车键继续..."
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
            print_info "输入已关闭，取消选择"
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
                print_error "无效架构选项，请重新输入"
                ;;
        esac
    done

    # 根据架构选择组件
    while true; do
        show_component_menu "$selected_architecture"
        if ! read -r component_choice; then
            echo ""
            print_info "输入已关闭，取消选择"
            return 1
        fi
        component_choice="${component_choice%$'\r'}"

        if [ "$component_choice" = "0" ]; then
            # 返回架构选择
            return 1
        fi

        if [ "$selected_architecture" = "multi" ]; then
            # 多架构模式下只有"全部组件"选项
            if [ "$component_choice" = "1" ]; then
                selected_component="all"
                break
            else
                print_error "无效选项，请重新输入"
            fi
        else
            # 单架构模式下选择具体组件
            selected_component=$(get_component_by_index "$component_choice")
            if [ -n "$selected_component" ]; then
                break
            else
                print_error "无效组件选项，请重新输入"
            fi
        fi
    done

    return 0
}

# 主函数
main() {
    # 检查依赖
    check_dependencies

    # 默认架构
    local architecture="single"
    local command=""
    local component=""
    local follow_logs=false

    # 未提供参数时启动交互模式
    if [ $# -eq 0 ]; then
        interactive_mode
        return
    fi

    # 解析参数
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
                print_error "未知参数：$1"
                show_help
                exit 1
                ;;
        esac
    done

    # 校验架构
    validate_architecture "$architecture"

    # 执行命令
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
            print_error "未知命令：$command"
            show_help
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"
