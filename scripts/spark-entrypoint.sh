#!/bin/bash

# ===============================================
# Spark内存计算引擎启动脚本
# 作用：配置Spark运行环境，根据Hadoop环境动态生成配置文件
# 原理：支持标准Hadoop和HA Hadoop两种环境，自动适配配置
# 重要性：Spark依赖Hadoop环境，正确的配置确保任务执行正常
# ===============================================

# 设置严格错误处理模式：任何命令失败立即退出脚本
set -e

# ===============================================
# 基础环境变量设置
# 作用：加载系统环境变量，设置Spark和Hadoop相关路径
# 原理：确保脚本能正确找到Spark和Hadoop的安装位置
# 变量说明：
#   - SPARK_HOME: Spark安装目录
#   - HADOOP_CONF_DIR: Hadoop配置目录
# ===============================================

# 设置环境变量
source /etc/profile

# 设置默认环境变量
export SPARK_HOME=${SPARK_HOME:-/opt/spark}
export HADOOP_CONF_DIR=${HADOOP_CONF_DIR:-/opt/spark/hadoop-conf}
export YARN_CONF_DIR=${YARN_CONF_DIR:-$HADOOP_CONF_DIR}
export PYSPARK_DRIVER_PYTHON=${PYSPARK_DRIVER_PYTHON:-/usr/bin/python3}
export PYSPARK_PYTHON=${PYSPARK_PYTHON:-/usr/bin/python3}
export PYTHONPATH="$SPARK_HOME/python:$SPARK_HOME/python/lib/py4j-0.10.9-src.zip:${PYTHONPATH:-}"

# ===============================================
# 环境配置加载
# 作用：加载外部环境配置文件，支持动态配置
# 原理：如果存在/config/environment.conf文件，则加载其中的配置
# 配置内容：可能包含版本信息、集群参数等自定义配置
# ===============================================

# Compose 只把宿主机显式设置的值放入覆盖变量。
# 若该值为空，后续加载的 /config/environment.conf 才是默认配置源。
REQUESTED_HADOOP_ENVIRONMENT=${HADOOP_ENVIRONMENT_OVERRIDE:-}

# 加载环境配置
if [ -f /config/environment.conf ]; then
    source /config/environment.conf
fi

# ===============================================
# Hadoop环境类型设置
# 作用：指定使用的Hadoop环境类型（标准或HA）
# 原理：根据环境类型加载不同的Hadoop配置文件
# 默认值：ha（高可用环境），支持standard（标准环境）
# ===============================================

# 设置Hadoop环境并记录值的来源，便于从容器日志判断配置是否真正生效。
if [ -n "$REQUESTED_HADOOP_ENVIRONMENT" ]; then
    export HADOOP_ENVIRONMENT="$REQUESTED_HADOOP_ENVIRONMENT"
    echo "Hadoop environment source: explicit host/Compose override"
elif [ -n "${HADOOP_ENVIRONMENT:-}" ]; then
    export HADOOP_ENVIRONMENT
    echo "Hadoop environment source: /config/environment.conf"
else
    export HADOOP_ENVIRONMENT="ha"
    echo "Hadoop environment source: built-in fallback (ha)"
fi

# ===============================================
# 配置目录准备
# 作用：创建Hadoop配置目录，确保配置文件的正确存储
# 原理：mkdir -p确保目录存在，避免文件复制失败
# 重要性：配置目录是Spark读取Hadoop配置的关键路径
# ===============================================

# 创建Hadoop配置目录
mkdir -p "$HADOOP_CONF_DIR"

# ===============================================
# SSH服务启动
# 作用：支持Spark原生start-all.sh/stop-all.sh跨容器批量管理Worker
# 原理：Master读取conf/workers，并以root免密SSH连接各Worker执行启停脚本
# 注意：sshd只在Docker内部网络提供服务，Compose不把22端口映射到宿主机
# ===============================================
start_ssh_service() {
    local attempt
    local sshd_pid

    mkdir -p /run/sshd /root/.ssh
    chmod 0700 /root/.ssh
    [ ! -f /root/.ssh/authorized_keys ] || chmod 0600 /root/.ssh/authorized_keys
    [ ! -f /root/.ssh/id_rsa ] || chmod 0600 /root/.ssh/id_rsa

    # 若镜像构建阶段未生成服务端host key，则在每个容器中补齐。
    ssh-keygen -A >/dev/null 2>&1

    if [ -s /run/sshd.pid ]; then
        sshd_pid=$(cat /run/sshd.pid 2>/dev/null || true)
    fi
    if [ -n "${sshd_pid:-}" ] && kill -0 "$sshd_pid" 2>/dev/null; then
        echo "SSH service is already running"
        return 0
    fi

    /usr/sbin/sshd -t
    /usr/sbin/sshd
    # sshd会派生为后台进程；在较慢的Docker Desktop文件系统上，PID文件可能
    # 比启动命令返回稍晚，因此进行短暂轮询，避免把正常启动误判为失败。
    for attempt in {1..5}; do
        if [ -s /run/sshd.pid ]; then
            sshd_pid=$(cat /run/sshd.pid 2>/dev/null || true)
            if [ -n "$sshd_pid" ] && kill -0 "$sshd_pid" 2>/dev/null; then
                echo "SSH service started for Spark native cluster scripts (PID: $sshd_pid)"
                return 0
            fi
        fi
        sleep 1
    done

    echo "Error: SSH service failed to start"
    return 1
}

start_ssh_service

# ===============================================
# Spark配置文件复制
# 作用：将外部配置目录中的Spark配置文件复制到安装目录
# 原理：支持配置热更新，便于调试和配置管理
# 配置内容：spark-defaults.conf、spark-env.sh等核心配置
# ===============================================

# 先移除旧版本遗留的实际节点列表。Spark 安装包中的 *.template 是官方示例，
# 可以保留；实际生效的主机列表统一使用项目提供的 workers 文件。
rm -f "$SPARK_HOME/conf/slaves"

# 复制Spark配置文件
cp -r /config/spark/* "$SPARK_HOME/conf/"

# 校验 Worker 主机名，避免默认 localhost 或错误容器名进入运行配置。
if [ ! -f /config/spark/workers ]; then
    echo "Error: /config/spark/workers not found"
    exit 1
fi

EXPECTED_WORKERS=$'spark-worker1\nspark-worker2'
ACTUAL_WORKERS=$(grep -Ev '^[[:space:]]*(#|$)' /config/spark/workers | awk '{print $1}')
if [ "$ACTUAL_WORKERS" != "$EXPECTED_WORKERS" ]; then
    echo "Error: invalid Spark workers configuration"
    echo "Expected workers:"
    printf '%s\n' "$EXPECTED_WORKERS"
    echo "Actual workers:"
    printf '%s\n' "$ACTUAL_WORKERS"
    exit 1
fi

install -m 0644 /config/spark/workers "$SPARK_HOME/conf/workers"
rm -f "$SPARK_HOME/conf/slaves"
echo "Configured Spark workers: spark-worker1, spark-worker2"

# 根据环境配置复制Hadoop配置文件
echo "Using Hadoop environment: $HADOOP_ENVIRONMENT"
if [ "$HADOOP_ENVIRONMENT" = "ha" ]; then
    echo "Copying Hadoop HA configuration..."
    cp -r /config/hadoop-ha/* $HADOOP_CONF_DIR/
    # 设置HA环境的HDFS nameservice
    export HDFS_NAMESERVICE="hdfs://mycluster"
elif [ "$HADOOP_ENVIRONMENT" = "standard" ]; then
    echo "Copying standard Hadoop configuration..."
    cp -r /config/hadoop/* $HADOOP_CONF_DIR/
    # 设置标准环境的HDFS nameservice
    export HDFS_NAMESERVICE="hdfs://namenode:8020"
else
    echo "Warning: Unknown Hadoop environment '$HADOOP_ENVIRONMENT', using HA configuration as default"
    cp -r /config/hadoop-ha/* $HADOOP_CONF_DIR/
    export HDFS_NAMESERVICE="hdfs://mycluster"
fi

# 动态生成Spark配置文件
echo "Generating Spark configuration files..."

# 生成spark-defaults.conf
if [ -f /config/spark/spark-defaults.conf.template ]; then
    # 使用不同的分隔符避免路径中的斜杠冲突
    sed "s|{{HDFS_NAMESERVICE}}|$HDFS_NAMESERVICE|g" /config/spark/spark-defaults.conf.template > $SPARK_HOME/conf/spark-defaults.conf
    echo "Generated spark-defaults.conf with HDFS nameservice: $HDFS_NAMESERVICE"
else
    echo "Warning: spark-defaults.conf.template not found, using static configuration"
    cp -r /config/spark/* $SPARK_HOME/conf/
fi

# 生成spark-env.sh
if [ -f /config/spark/spark-env.sh.template ]; then
    # 使用不同的分隔符避免路径中的斜杠冲突
    sed "s|{{HDFS_NAMESERVICE}}|$HDFS_NAMESERVICE|g" /config/spark/spark-env.sh.template > $SPARK_HOME/conf/spark-env.sh
    echo "Generated spark-env.sh with HDFS nameservice: $HDFS_NAMESERVICE"
else
    echo "Warning: spark-env.sh.template not found, using static configuration"
    cp -r /config/spark/* $SPARK_HOME/conf/
fi

# 确保HADOOP_CONF_DIR在classpath中
export SPARK_DIST_CLASSPATH=$HADOOP_CONF_DIR

# 启动前检查Scala/Spark与Python/PySpark运行时，避免容器启动后才发现解释器缺失。
echo "Checking Spark language runtimes..."
echo "PySpark Driver Python: $PYSPARK_DRIVER_PYTHON"
echo "PySpark Executor Python: $PYSPARK_PYTHON"
"$PYSPARK_DRIVER_PYTHON" --version
"$PYSPARK_DRIVER_PYTHON" -c "import pyspark; print('PySpark ' + pyspark.__version__)"

# 等待HDFS服务就绪（通过测试HDFS端口连通性）
echo "Waiting for HDFS services to be ready..."
HDFS_READY=false
for i in {1..60}; do
    if [ "$HADOOP_ENVIRONMENT" = "ha" ]; then
        if (echo > /dev/tcp/namenode1/8020) 2>/dev/null; then
            echo "HDFS NameNode is ready!"
            HDFS_READY=true
            break
        fi
    else
        if (echo > /dev/tcp/namenode/8020) 2>/dev/null; then
            echo "HDFS NameNode is ready!"
            HDFS_READY=true
            break
        fi
    fi
    echo "Waiting for HDFS... (attempt $i/60)"
    sleep 1
done

if [ "$HDFS_READY" = "false" ]; then
    echo "Warning: HDFS not available, event logging may fail"
fi

# 根据角色启动服务
case "$ROLE" in
    "master")
        if jps 2>/dev/null | awk '$2 == "Master" {found=1} END {exit !found}'; then
            echo "Spark Master is already running; skip duplicate startup"
        else
            echo "Starting Spark Master..."
            $SPARK_HOME/sbin/start-master.sh
        fi

        if jps 2>/dev/null | awk '$2 == "HistoryServer" {found=1} END {exit !found}'; then
            echo "Spark History Server is already running; skip duplicate startup"
        else
            echo "Starting Spark History Server..."
            $SPARK_HOME/sbin/start-history-server.sh
        fi
        # Spark原生stop-all.sh --wait使用ps+类名判断进程是否仍存在。
        # 不能用tail跟随带有Master/Worker类名的日志文件，否则tail命令行会被误判
        # 为Spark守护进程。实际日志保存在已挂载的/opt/spark/logs目录中。
        exec tail -f /dev/null
        ;;
    "worker")
        echo "Waiting for Spark Master to start..."
        sleep 30
        # Worker可能已由Master中的start-all.sh通过SSH启动。先检查进程，避免
        # start-worker.sh返回“已运行”的非零状态触发set -e并使容器退出。
        if jps 2>/dev/null | awk '$2 == "Worker" {found=1} END {exit !found}'; then
            echo "Spark Worker is already running (possibly started through SSH); skip duplicate startup"
        else
            echo "Starting Spark Worker..."
            $SPARK_HOME/sbin/start-worker.sh spark://spark-master:7077
        fi
        # 使用不含Spark类名的保活命令，避免stop-all.sh --wait误匹配日志路径。
        exec tail -f /dev/null
        ;;
    *)
        echo "Unknown role: $ROLE"
        exit 1
        ;;
esac
