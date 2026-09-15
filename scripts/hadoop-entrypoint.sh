#!/bin/bash

# ===============================================
# Hadoop标准集群启动脚本
# 作用：根据容器角色启动相应的Hadoop服务
# 原理：通过命令行参数识别容器角色，执行对应的服务启动流程
# 适用场景：标准Hadoop集群（非HA模式）
# ===============================================

# 记录由本入口脚本负责管理的服务。收到 Docker 的停止信号时，将按启动顺序的
# 反方向逐个停止，避免 Java 进程被强制结束后留下 PID 文件。
STARTED_DAEMONS=()

# 返回某个 Hadoop 服务使用的 PID 文件路径。
# Hadoop 默认规则是：$HADOOP_PID_DIR/hadoop-$HADOOP_IDENT_STRING-$daemon.pid。
daemon_pid_file() {
    local daemon_name="$1"
    local pid_dir="${HADOOP_PID_DIR:-/tmp}"
    local ident_string="${HADOOP_IDENT_STRING:-${USER:-root}}"
    printf '%s/hadoop-%s-%s.pid' "$pid_dir" "$ident_string" "$daemon_name"
}

# 不能只用 kill -0 判断服务是否存活：容器重启后 PID 可能被 SSH 等其他进程
# 复用。除了确认 PID 存在，还必须检查 /proc/<pid>/cmdline 中是否包含 Hadoop
# 为该服务设置的 -Dproc_<daemon> 标记。
daemon_is_running() {
    local daemon_name="$1"
    local pid_file
    local daemon_pid

    pid_file="$(daemon_pid_file "$daemon_name")"
    [ -f "$pid_file" ] || return 1

    daemon_pid="$(cat "$pid_file" 2>/dev/null || true)"
    case "$daemon_pid" in
        ''|*[!0-9]*) return 1 ;;
    esac

    kill -0 "$daemon_pid" 2>/dev/null || return 1
    [ -r "/proc/$daemon_pid/cmdline" ] || return 1

    tr '\0' ' ' < "/proc/$daemon_pid/cmdline" \
        | grep -Fq -- "-Dproc_${daemon_name}"
}

# 仅删除确认无效的 PID 文件：
#   1. 文件内容不是有效数字；
#   2. PID 已不存在；
#   3. PID 已被其他进程复用。
# 如果对应 Hadoop 服务确实仍在运行，则保留 PID 文件。
cleanup_stale_pid_file() {
    local daemon_name="$1"
    local pid_file
    local old_pid

    pid_file="$(daemon_pid_file "$daemon_name")"
    [ -f "$pid_file" ] || return 0

    if daemon_is_running "$daemon_name"; then
        return 0
    fi

    old_pid="$(cat "$pid_file" 2>/dev/null || true)"
    echo "清理失效PID文件: $pid_file (旧PID: ${old_pid:-未知})"
    rm -f -- "$pid_file"
}

# 启动并验证 Hadoop 后台服务。
# launcher 是 hdfs、yarn 或 mapred，daemon_name 是具体服务名。
start_hadoop_daemon() {
    local launcher="$1"
    local daemon_name="$2"
    local attempt

    cleanup_stale_pid_file "$daemon_name"

    if daemon_is_running "$daemon_name"; then
        echo "$daemon_name 已经正常运行，跳过重复启动"
    else
        "$HADOOP_HOME/bin/$launcher" --daemon start "$daemon_name"

        # Java 进程启动需要短暂时间。只有 PID 和进程类型都正确才算启动成功。
        for attempt in {1..10}; do
            if daemon_is_running "$daemon_name"; then
                break
            fi
            sleep 1
        done

        if ! daemon_is_running "$daemon_name"; then
            echo "错误: $daemon_name 启动失败或PID校验失败" >&2
            return 1
        fi
    fi

    STARTED_DAEMONS+=("$launcher:$daemon_name")
    echo "$daemon_name 启动成功，PID: $(cat "$(daemon_pid_file "$daemon_name")")"
}

# Docker 默认先向容器 PID 1 发送 SIGTERM。入口脚本捕获信号后调用 Hadoop
# 官方 stop 命令，使各服务删除自己的 PID 文件并正常释放资源。
shutdown_hadoop_daemons() {
    local index
    local launcher
    local daemon_name

    echo "收到停止信号，正在优雅关闭Hadoop服务..."
    for ((index=${#STARTED_DAEMONS[@]} - 1; index >= 0; index--)); do
        IFS=: read -r launcher daemon_name <<< "${STARTED_DAEMONS[$index]}"
        if daemon_is_running "$daemon_name"; then
            echo "停止 $daemon_name..."
            "$HADOOP_HOME/bin/$launcher" --daemon stop "$daemon_name" || true
        else
            # 服务若已异常退出，其 PID 文件也不应留给下次启动。
            cleanup_stale_pid_file "$daemon_name"
        fi
    done
    exit 0
}

trap shutdown_hadoop_daemons TERM INT

# ===============================================
# 基础服务启动
# ===============================================

# 启动SSH服务，用于容器间通信和远程管理
# 原理：Hadoop集群组件间需要通过SSH进行通信和故障检测
/etc/init.d/ssh start

# ===============================================
# 动态配置加载
# ===============================================

# 如果挂载了外部配置文件，则覆盖默认配置
# 原理：支持配置热更新，便于调试和配置管理
if [ -d "/config/hadoop" ]; then
    echo "加载外部Hadoop配置文件..."
    cp -f /config/hadoop/* $HADOOP_CONF_DIR/
fi

# ===============================================
# 角色识别和服务启动分发
# ===============================================

# 根据传入的参数决定启动什么服务
# 参数来源：Docker Compose command字段传递的角色标识

# ===============================================
# NameNode服务启动（主节点）
# ===============================================

if [ "$1" = "namenode" ]; then
    # 格式化NameNode元数据存储（幂等操作）
    # 原理：检查元数据目录是否存在，避免重复格式化
    if [ ! -d "/opt/hadoop/data/dfs/name" ]; then
        echo "格式化NameNode元数据..."
        $HADOOP_HOME/bin/hdfs namenode -format -force -nonInteractive
    fi
    
    # 启动NameNode服务
    echo "启动NameNode服务..."
    start_hadoop_daemon hdfs namenode || exit 1
    
    # 启动ResourceManager，负责YARN资源调度
    echo "启动ResourceManager（YARN资源管理器）..."
    start_hadoop_daemon yarn resourcemanager || exit 1
    
    # 启动JobHistoryServer，记录MapReduce作业历史
    echo "启动JobHistoryServer（作业历史服务器）..."
    start_hadoop_daemon mapred historyserver || exit 1
    
    # 等待HDFS退出安全模式后创建Spark日志目录
    echo "等待HDFS退出安全模式..."
    for i in {1..30}; do
        if $HADOOP_HOME/bin/hdfs dfsadmin -safemode get 2>/dev/null | grep -q "OFF"; then
            echo "HDFS已退出安全模式"
            break
        fi
        echo "等待HDFS安全模式... (尝试 $i/30)"
        sleep 2
    done
    
    # 创建Spark事件日志目录
    echo "创建Spark事件日志目录..."
    $HADOOP_HOME/bin/hdfs dfs -mkdir -p /spark-logs 2>/dev/null
    $HADOOP_HOME/bin/hdfs dfs -chmod 777 /spark-logs 2>/dev/null
    echo "Spark事件日志目录创建完成: /spark-logs"

# ===============================================
# DataNode服务启动（数据存储节点）
# ===============================================

elif [ "$1" = "datanode" ]; then
    echo "启动DataNode服务..."
    start_hadoop_daemon hdfs datanode || exit 1
    
    echo "Starting NodeManager..."
    start_hadoop_daemon yarn nodemanager || exit 1
else
    echo "错误: 未知的Hadoop容器角色 '$1'，应为 namenode 或 datanode" >&2
    exit 1
fi

# 保持入口脚本作为容器 PID 1 运行。
# 使用可被 wait 中断的 sleep 循环，确保 SIGTERM/INT 能触发上面的 trap；
# 单纯 tail -f /dev/null 无法负责停止后台 Hadoop 服务。
while true; do
    sleep 86400 &
    wait $!
done
