#!/bin/bash

# 禁用 Git Bash/MSYS2 的路径自动转换，防止 docker exec 中的绝对路径被转换为 Windows 路径
export MSYS_NO_PATHCONV=1

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

# 日志文件配置
LOG_DIR="test/test-log"
LOG_FILE="$LOG_DIR/test-spark-$(date +%Y%m%d-%H%M%S).log"

# 创建日志目录
mkdir -p "$LOG_DIR"

# 将脚本内所有 echo、docker、curl 的标准输出和错误统一写入日志，
# 避免只有少量 log() 调用进入文件、关键失败输出只停留在终端。
exec > >(tee -a "$LOG_FILE") 2>&1

# 日志函数
log() {
    echo "$1"
}

standalone_ok=false
yarn_ok=false
sql_ok=false
streaming_ok=false
scala_runtime_ok=false
python_runtime_ok=false
pyspark_ok=false
workers_config_ok=false
ssh_lifecycle_ok=false
mysql_connector_ok=false

log "=== Spark 集群测试 ==="
log "测试开始时间: $(date)"
log "日志文件: $LOG_FILE"
log ""

# 读取 Spark 版本号
ENV_CONF="$PROJECT_ROOT/config/environment.conf"
if [ -f "$ENV_CONF" ]; then
    SPARK_VERSION=$(grep "^SPARK_VERSION=" "$ENV_CONF" | cut -d'=' -f2)
    echo "使用 Spark 版本: $SPARK_VERSION"
else
    echo "警告: 环境配置文件不存在，使用默认版本 3.1.1"
    SPARK_VERSION="3.1.1"
fi

# 检测 Hadoop 环境（HA 或 非HA）
if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "namenode1"; then
    HADOOP_HA=true
    NAMENODE_CONTAINER="namenode1"
    echo "检测到 Hadoop HA 模式 (namenode: $NAMENODE_CONTAINER)"
else
    HADOOP_HA=false
    NAMENODE_CONTAINER="namenode"
    echo "检测到 Hadoop 标准 模式 (namenode: $NAMENODE_CONTAINER)"
fi
echo

# 检查 Spark 容器状态
echo "1. 检查 Spark 容器状态..."
docker ps | grep -E "spark-master|spark-worker"
echo

# 检查 Spark 3.x Worker 主机列表。三个容器应使用同一份 workers 配置，
# 且不应再残留旧版本使用的 slaves 文件。
echo "1.1 检查 Spark Worker 主机列表配置..."
workers_config_ok=true
for container in spark-master spark-worker1 spark-worker2; do
    if docker exec "$container" test -e /opt/spark/conf/slaves; then
        echo "✗ $container 仍存在旧配置 /opt/spark/conf/slaves"
        workers_config_ok=false
    fi

    if docker exec "$container" test -f /opt/spark/hadoop-conf/core-site.xml; then
        echo "✓ $container Hadoop客户端配置已隔离到 /opt/spark/hadoop-conf"
    else
        echo "✗ $container 缺少 /opt/spark/hadoop-conf/core-site.xml"
        workers_config_ok=false
    fi

    worker_hosts=$(docker exec "$container" awk \
        '!/^[[:space:]]*(#|$)/ {print $1}' /opt/spark/conf/workers 2>&1)
    if [ "$worker_hosts" = $'spark-worker1\nspark-worker2' ]; then
        echo "✓ $container workers 配置正确: spark-worker1、spark-worker2"
    else
        echo "✗ $container workers 配置错误"
        echo "  期望: spark-worker1、spark-worker2"
        echo "  实际内容:"
        echo "$worker_hosts" | sed 's/^/    /'
        workers_config_ok=false
    fi
done
echo

# 验证Spark原生SSH集群管理链路。该测试不仅检查22端口，还真实执行一次
# stop-all.sh与start-all.sh，并确认Master及两个Worker均按预期停止、重启和注册。
echo "1.2 测试基于 SSH 的 start-all.sh/stop-all.sh..."
ssh_connectivity_ok=true
for worker in spark-worker1 spark-worker2; do
    ssh_output=$(docker exec spark-master ssh \
        -o BatchMode=yes \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=5 \
        -o LogLevel=ERROR \
        "$worker" hostname 2>&1)
    if [ $? -eq 0 ] && [ "$ssh_output" = "$worker" ]; then
        echo "✓ spark-master 可免密 SSH 登录 $worker，远程hostname为 $ssh_output"
    else
        echo "✗ spark-master 无法免密 SSH 登录 $worker"
        echo "  期望远程hostname: $worker"
        echo "  实际输出: $ssh_output"
        ssh_connectivity_ok=false
    fi
done

if [ "$ssh_connectivity_ok" = true ]; then
    echo "1.2.1 确认启停测试前Master和两个Worker均已运行..."
    prepare_output=$(docker exec spark-master timeout 60 bash -lc \
        'cd /opt/spark && ./sbin/start-all.sh' 2>&1)
    echo "$prepare_output" | sed 's/^/  /'

    initial_cluster_ready=false
    for attempt in {1..45}; do
        master_process_count=$(docker exec spark-master jps 2>/dev/null | awk '$2 == "Master" {count++} END {print count+0}')
        worker1_process_count=$(docker exec spark-worker1 jps 2>/dev/null | awk '$2 == "Worker" {count++} END {print count+0}')
        worker2_process_count=$(docker exec spark-worker2 jps 2>/dev/null | awk '$2 == "Worker" {count++} END {print count+0}')
        if [ "$master_process_count" -eq 1 ] \
            && [ "$worker1_process_count" -eq 1 ] \
            && [ "$worker2_process_count" -eq 1 ]; then
            initial_master_json=$(docker exec spark-master curl -fsS http://127.0.0.1:8080/json/ 2>/dev/null || true)
            if echo "$initial_master_json" | grep -Eq '"aliveworkers"[[:space:]]*:[[:space:]]*2'; then
                initial_cluster_ready=true
                break
            fi
        fi
        sleep 1
    done

    if [ "$initial_cluster_ready" = true ]; then
        echo "✓ 前置状态正常：Master运行且已注册2个Worker"
        echo "1.2.2 执行 /opt/spark/sbin/stop-all.sh --wait..."
    stop_all_output=$(docker exec spark-master timeout 60 bash -lc \
        'cd /opt/spark && ./sbin/stop-all.sh --wait' 2>&1)
    stop_all_status=$?
    echo "$stop_all_output" | sed 's/^/  /'

    daemons_stopped=false
    if [ "$stop_all_status" -eq 0 ]; then
        for attempt in {1..20}; do
            if ! docker exec spark-master jps 2>/dev/null | grep -Eq '[[:space:]]Master$' \
                && ! docker exec spark-worker1 jps 2>/dev/null | grep -Eq '[[:space:]]Worker$' \
                && ! docker exec spark-worker2 jps 2>/dev/null | grep -Eq '[[:space:]]Worker$'; then
                daemons_stopped=true
                break
            fi
            sleep 1
        done
    fi

    if [ "$daemons_stopped" = true ]; then
        echo "✓ stop-all.sh 已通过 SSH 停止Master和两个Worker"
    else
        echo "✗ stop-all.sh 未能完整停止集群守护进程（退出码: $stop_all_status）"
        echo "  当前进程状态:"
        for container in spark-master spark-worker1 spark-worker2; do
            echo "  [$container]"
            docker exec "$container" jps 2>&1 | sed 's/^/    /'
        done
    fi

    echo "1.2.3 执行 /opt/spark/sbin/start-all.sh..."
    start_all_output=$(docker exec spark-master timeout 60 bash -lc \
        'cd /opt/spark && ./sbin/start-all.sh' 2>&1)
    start_all_status=$?
    echo "$start_all_output" | sed 's/^/  /'

    daemons_started=false
    workers_registered=false
    if [ "$start_all_status" -eq 0 ]; then
        for attempt in {1..30}; do
            master_process_count=$(docker exec spark-master jps 2>/dev/null | awk '$2 == "Master" {count++} END {print count+0}')
            worker1_process_count=$(docker exec spark-worker1 jps 2>/dev/null | awk '$2 == "Worker" {count++} END {print count+0}')
            worker2_process_count=$(docker exec spark-worker2 jps 2>/dev/null | awk '$2 == "Worker" {count++} END {print count+0}')
            if [ "$master_process_count" -eq 1 ] \
                && [ "$worker1_process_count" -eq 1 ] \
                && [ "$worker2_process_count" -eq 1 ]; then
                daemons_started=true
                master_json=$(docker exec spark-master curl -fsS http://127.0.0.1:8080/json/ 2>/dev/null || true)
                if echo "$master_json" | grep -Eq '"aliveworkers"[[:space:]]*:[[:space:]]*2'; then
                    workers_registered=true
                    break
                fi
            fi
            sleep 1
        done
    fi

    if [ "$daemons_stopped" = true ] \
        && [ "$daemons_started" = true ] \
        && [ "$workers_registered" = true ]; then
        echo "✓ start-all.sh 已启动Master和两个Worker，Master显示2个存活Worker"
        ssh_lifecycle_ok=true
    else
        echo "✗ start-all.sh 集群恢复检查失败（退出码: $start_all_status）"
        echo "  Master进程已启动: $daemons_started"
        echo "  两个Worker已注册: $workers_registered"
    fi
    else
        echo "✗ 无法建立启停测试前置状态，未执行stop-all.sh，避免产生误判"
        echo "  要求：Master进程、两个Worker进程均运行，且aliveworkers为2"
    fi
else
    echo "✗ SSH免密连接未全部通过，为避免停止后无法恢复，跳过stop-all/start-all实测"
fi
echo

# 检查Scala与Python/PySpark运行环境
echo "2. 检查 Scala 与 Python/PySpark 运行环境..."
scala_version_output=$(docker exec spark-master /opt/spark/bin/spark-shell --version 2>&1)
if [ $? -eq 0 ] && echo "$scala_version_output" | grep -qi "version"; then
    echo "✓ Scala spark-shell 运行环境正常"
    echo "$scala_version_output" | grep -E "version|Scala" | head -5 | sed 's/^/  /'
    scala_runtime_ok=true
else
    echo "✗ Scala spark-shell 运行环境异常"
    echo "  实际输出: $scala_version_output"
fi

python_runtime_ok=true
for container in spark-master spark-worker1 spark-worker2; do
    python_version_output=$(docker exec "$container" /usr/bin/python3 --version 2>&1)
    if [ $? -eq 0 ] && echo "$python_version_output" | grep -q "Python 3"; then
        echo "✓ $container Python 3 运行环境正常: $python_version_output"
    else
        echo "✗ $container Python 3 运行环境异常"
        echo "  实际输出: $python_version_output"
        python_runtime_ok=false
    fi
done

pyspark_import_output=$(docker exec spark-master /usr/bin/python3 -c \
    "import pyspark; print('PySpark ' + pyspark.__version__)" 2>&1)
if [ $? -eq 0 ] && echo "$pyspark_import_output" | grep -q "PySpark $SPARK_VERSION"; then
    echo "✓ spark-master 能够通过 Python 3 导入 PySpark: $pyspark_import_output"
else
    echo "✗ spark-master 无法导入与 Spark 版本一致的 PySpark"
    echo "  期望: PySpark $SPARK_VERSION"
    echo "  实际输出: $pyspark_import_output"
    python_runtime_ok=false
fi

# 检查镜像是否把Connector/J放入每个Spark节点的默认JAR目录。
# 这里只验证镜像交付与驱动类；真实MySQL JDBC读写由五节点综合测试覆盖。
echo "2.1 检查 MySQL Connector/J 运行依赖..."
mysql_connector_ok=true
mysql_connector_jar="/opt/spark/jars/mysql-connector-java-5.1.49.jar"
for container in spark-master spark-worker1 spark-worker2; do
    connector_entries=$(docker exec "$container" jar tf "$mysql_connector_jar" 2>&1)
    if [ $? -eq 0 ] \
        && echo "$connector_entries" | grep -qx 'com/mysql/jdbc/Driver.class'; then
        echo "✓ $container 已内置Connector/J 5.1.49，驱动类为com.mysql.jdbc.Driver"
    else
        echo "✗ $container 的MySQL Connector/J缺失或驱动类不正确"
        echo "  检查路径: $mysql_connector_jar"
        echo "  实际输出:"
        echo "$connector_entries" | tail -20 | sed 's/^/    /'
        mysql_connector_ok=false
    fi
done
echo

# 测试 Spark Master Web UI
echo "3. 测试 Spark Master Web UI 可访问性..."
master_status=$(curl -s -L -o /dev/null -w "%{http_code}" http://localhost:8080)
if [ "$master_status" = "200" ]; then
    echo "✓ Spark Master Web UI 正常 (http://localhost:8080)"
else
    echo "⚠ Spark Master Web UI 返回状态码: $master_status"
fi

# 测试 Spark History Server Web UI
echo "4. 测试 Spark History Server Web UI 可访问性..."
history_status=$(curl -s -L -o /dev/null -w "%{http_code}" http://localhost:18080)
if [ "$history_status" = "200" ]; then
    echo "✓ Spark History Server Web UI 正常 (http://localhost:18080)"
else
    echo "⚠ Spark History Server Web UI 返回状态码: $history_status"
fi

# 测试 Spark Worker Web UI
echo "5. 测试 Spark Worker Web UI 可访问性..."
worker1_status=$(curl -s -L -o /dev/null -w "%{http_code}" http://localhost:8081)
worker2_status=$(curl -s -L -o /dev/null -w "%{http_code}" http://localhost:8082)
if [ "$worker1_status" = "200" ]; then
    echo "✓ Spark Worker1 Web UI 正常 (http://localhost:8081)"
else
    echo "⚠ Spark Worker1 Web UI 返回状态码: $worker1_status"
fi
if [ "$worker2_status" = "200" ]; then
    echo "✓ Spark Worker2 Web UI 正常 (http://localhost:8082)"
else
    echo "⚠ Spark Worker2 Web UI 返回状态码: $worker2_status"
fi

# 测试 Spark standalone 模式
echo "6. 测试 Spark standalone 模式..."

# 检查 Spark Master 状态
echo "6.1 检查 Spark Master 状态..."
master_output=$(docker exec spark-master /opt/spark/bin/spark-shell --master spark://spark-master:7077 --conf spark.ui.enabled=false <<< 'println("Spark standalone mode test"); sys.exit(0)' 2>&1)
if echo "$master_output" | grep -q "Spark context available"; then
    echo "✓ Spark standalone 模式连接正常"
else
    echo "✗ Spark standalone 模式连接失败"
    echo "  输出: $master_output"
fi

# 运行简单的 Spark 作业（standalone 模式）
echo "6.2 运行 Scala Spark standalone 模式作业..."
# 创建测试数据
echo "1,Alice,25" > /tmp/spark-test.csv
echo "2,Bob,30" >> /tmp/spark-test.csv
echo "3,Charlie,35" >> /tmp/spark-test.csv
docker cp /tmp/spark-test.csv spark-master:/tmp/spark-test.csv

# 检查 HDFS 可用性
echo "6.3 检查 HDFS 可用性..."
hdfs_available=$(docker exec $NAMENODE_CONTAINER hdfs dfs -test -d / 2>/dev/null && echo "true" || echo "false")
if [ "$hdfs_available" = "true" ]; then
    echo "✓ HDFS 可用"
    # 上传测试数据到 HDFS
    docker exec $NAMENODE_CONTAINER hdfs dfs -mkdir -p /test/spark/input 2>/dev/null
    docker cp /tmp/spark-test.csv $NAMENODE_CONTAINER:/tmp/spark-test.csv
    docker exec $NAMENODE_CONTAINER hdfs dfs -put -f /tmp/spark-test.csv /test/spark/input/ 2>/dev/null
    echo "✓ 测试数据已上传到 HDFS"
    data_path="hdfs:///test/spark/input/spark-test.csv"
else
    echo "⚠ HDFS 不可用，使用本地文件"
    data_path="/tmp/spark-test.csv"
fi

# 运行 Spark standalone 作业
standalone_output=$(docker exec spark-master /opt/spark/bin/spark-submit \
    --master spark://spark-master:7077 \
    --class org.apache.spark.examples.SparkPi \
    /opt/spark/examples/jars/spark-examples_2.12-3.1.1.jar 10 2>&1)

if echo "$standalone_output" | grep -q "Pi is roughly"; then
    echo "✓ Scala Spark standalone 作业执行成功"
    standalone_ok=true
    pi_result=$(echo "$standalone_output" | grep "Pi is roughly")
    echo "  $pi_result"
else
    echo "✗ Scala Spark standalone 作业执行失败"
    echo "  输出: $standalone_output"
fi

# 提交PySpark脚本，RDD lambda会在Worker节点的Python Worker中执行。
echo "6.4 运行 Python PySpark standalone 模式作业..."
if docker cp "$SCRIPT_DIR/pyspark-smoke.py" spark-master:/tmp/pyspark-smoke.py; then
    pyspark_output=$(docker exec spark-master timeout 180 \
        /opt/spark/bin/spark-submit \
        --master spark://spark-master:7077 \
        /tmp/pyspark-smoke.py 2>&1)
    if [ $? -eq 0 ] && echo "$pyspark_output" | grep -q \
        "PYSPARK_SMOKE_OK square_sum=55 adult_count=2"; then
        echo "✓ Python PySpark standalone 作业执行成功"
        echo "$pyspark_output" | grep -E "\[信息\]|PYSPARK_SMOKE_OK" | sed 's/^/  /'
        pyspark_ok=true
    else
        echo "✗ Python PySpark standalone 作业执行失败或计算结果不正确"
        echo "  期望标记: PYSPARK_SMOKE_OK square_sum=55 adult_count=2"
        echo "  作业输出末尾:"
        echo "$pyspark_output" | tail -80 | sed 's/^/    /'
    fi
else
    echo "✗ 无法将 $SCRIPT_DIR/pyspark-smoke.py 复制到 spark-master"
fi

# 测试 Spark on YARN 模式
echo "7. 测试 Scala Spark on YARN 模式..."

# 检查 YARN 资源管理器状态
echo "7.1 检查 YARN 资源管理器状态..."
yarn_nodes_output=$(docker exec $NAMENODE_CONTAINER yarn node -list 2>/dev/null)
if echo "$yarn_nodes_output" | grep -q "Total Nodes"; then
    yarn_nodes=$(echo "$yarn_nodes_output" | grep "Total Nodes" | awk -F: '{print $2}' | awk '{print $1}' | tr -d '[:space:]')
    echo "✓ YARN 资源管理器正常，总节点数: $yarn_nodes"
else
    echo "✗ YARN 资源管理器状态检查失败"
    echo "  输出: $yarn_nodes_output"
fi

# 运行 Spark on YARN 作业
echo "7.2 运行 Scala Spark on YARN 模式作业..."
yarn_output=$(docker exec spark-master /opt/spark/bin/spark-submit \
    --master yarn \
    --deploy-mode client \
    --class org.apache.spark.examples.SparkPi \
    /opt/spark/examples/jars/spark-examples_2.12-3.1.1.jar 10 2>&1)

if echo "$yarn_output" | grep -q "Pi is roughly"; then
    echo "✓ Spark on YARN 作业执行成功"
    yarn_ok=true
    pi_result=$(echo "$yarn_output" | grep "Pi is roughly")
    echo "  $pi_result"
else
    echo "✗ Spark on YARN 作业执行失败"
    echo "  输出: $yarn_output"
fi

# 测试 Spark SQL 功能
echo "8. 测试 Scala Spark SQL 功能..."

# 创建简单的 Scala 脚本文件，使用英文避免编码问题
cat > /tmp/spark-sql-test.scala << 'EOF'
import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions._

val spark = SparkSession.builder()
  .appName("Spark SQL Test")
  .master("spark://spark-master:7077")
  .config("spark.ui.enabled", "false")
  .getOrCreate()

import spark.implicits._

val data = Seq((1, "Alice", 25), (2, "Bob", 30), (3, "Charlie", 35))
val df = data.toDF("id", "name", "age")

println("=== Spark SQL Test Result ===")
println("DataFrame Content:")
df.show()
println("Total Records: " + df.count())
println("Average Age: " + df.agg(avg("age")).first().getDouble(0))

spark.stop()
EOF

# 复制文件到容器并执行
docker cp /tmp/spark-sql-test.scala spark-master:/tmp/spark-sql-test.scala

# 使用 spark-shell 执行脚本
sql_output=$(docker exec spark-master /opt/spark/bin/spark-shell --master spark://spark-master:7077 --conf spark.ui.enabled=false -i /tmp/spark-sql-test.scala 2>&1)

if echo "$sql_output" | grep -q "Spark SQL Test Result"; then
    echo "✓ Spark SQL 功能测试成功"
    sql_ok=true
    echo "  查询结果:"
    echo "$sql_output" | grep -A 10 "=== Spark SQL Test Result ===" | sed 's/^/  /'
else
    echo "✗ Spark SQL 功能测试失败"
    echo "  输出: $sql_output"
fi

# 测试 Spark Streaming 功能（简单测试）
echo "9. 测试 Scala Spark Streaming 功能..."

# 创建 Streaming 测试脚本
cat > /tmp/spark-streaming-test.scala << 'EOF'
import org.apache.spark.streaming._

val ssc = new StreamingContext(sc, Seconds(1))
println("Spark Streaming context created successfully")
ssc.stop()
println("Spark Streaming test completed")
EOF

# 复制文件到容器并执行
docker cp /tmp/spark-streaming-test.scala spark-master:/tmp/spark-streaming-test.scala

# 使用 spark-shell 执行脚本
streaming_output=$(docker exec spark-master /opt/spark/bin/spark-shell --master spark://spark-master:7077 --conf spark.ui.enabled=false -i /tmp/spark-streaming-test.scala 2>&1)

if echo "$streaming_output" | grep -q "Spark Streaming test completed"; then
    echo "✓ Spark Streaming 功能测试成功"
    streaming_ok=true
else
    echo "⚠ Spark Streaming 功能测试存在问题"
    echo "  输出: $streaming_output"
fi

# 清理测试数据
echo "10. 清理测试数据..."
if [ "$hdfs_available" = "true" ]; then
    docker exec $NAMENODE_CONTAINER hdfs dfs -rm -r -f /test/spark 2>/dev/null
fi
docker exec spark-master rm -f /tmp/pyspark-smoke.py 2>/dev/null || true
rm -f /tmp/spark-test.csv /tmp/spark-sql-test.scala /tmp/spark-streaming-test.scala

echo "✓ 测试数据清理完成"

# 综合测试结果
echo
echo "=== Spark 集群测试完成 ==="
echo "测试总结:"
echo "- Scala spark-shell 运行环境: $([ "$scala_runtime_ok" = true ] && echo "✓ 正常" || echo "✗ 异常")"
echo "- Python/PySpark 运行环境: $([ "$python_runtime_ok" = true ] && echo "✓ 正常" || echo "✗ 异常")"
echo "- Spark Master Web UI: $([ "$master_status" = "200" ] && echo "✓ 正常" || echo "⚠ 异常")"
echo "- Spark History Server: $([ "$history_status" = "200" ] && echo "✓ 正常" || echo "⚠ 异常")"
# 检查两个Worker的状态，只要有一个正常就认为Worker Web UI正常
if [ "$worker1_status" = "200" ] || [ "$worker2_status" = "200" ]; then
    echo "- Spark Worker Web UI: ✓ 正常"
else
    echo "- Spark Worker Web UI: ⚠ 异常"
fi
echo "- Spark workers 主机列表: $([ "$workers_config_ok" = true ] && echo "✓ 正常" || echo "✗ 异常")"
echo "- SSH原生start-all/stop-all: $([ "$ssh_lifecycle_ok" = true ] && echo "✓ 正常" || echo "✗ 异常")"
echo "- MySQL Connector/J: $([ "$mysql_connector_ok" = true ] && echo "✓ 正常" || echo "✗ 异常")"
echo "- Spark standalone 模式: $([ "$standalone_ok" = true ] && echo "✓ 正常" || echo "✗ 异常")"
echo "- PySpark standalone 模式: $([ "$pyspark_ok" = true ] && echo "✓ 正常" || echo "✗ 异常")"
echo "- Spark on YARN 模式: $([ "$yarn_ok" = true ] && echo "✓ 正常" || echo "✗ 异常")"
echo "- Spark SQL 功能: $([ "$sql_ok" = true ] && echo "✓ 正常" || echo "✗ 异常")"
echo "- Spark Streaming 功能: $([ "$streaming_ok" = true ] && echo "✓ 正常" || echo "✗ 异常")"

echo
echo "详细测试报告已生成，Spark 集群功能验证完成！"
echo "详细日志: $LOG_FILE"

failure_count=0
[ "$scala_runtime_ok" = true ] || failure_count=$((failure_count + 1))
[ "$python_runtime_ok" = true ] || failure_count=$((failure_count + 1))
[ "$workers_config_ok" = true ] || failure_count=$((failure_count + 1))
[ "$ssh_lifecycle_ok" = true ] || failure_count=$((failure_count + 1))
[ "$mysql_connector_ok" = true ] || failure_count=$((failure_count + 1))
[ "$master_status" = "200" ] || failure_count=$((failure_count + 1))
if [ "$worker1_status" != "200" ] && [ "$worker2_status" != "200" ]; then
    failure_count=$((failure_count + 1))
fi
[ "$standalone_ok" = true ] || failure_count=$((failure_count + 1))
[ "$pyspark_ok" = true ] || failure_count=$((failure_count + 1))
[ "$yarn_ok" = true ] || failure_count=$((failure_count + 1))
[ "$sql_ok" = true ] || failure_count=$((failure_count + 1))
[ "$streaming_ok" = true ] || failure_count=$((failure_count + 1))

if [ "$failure_count" -gt 0 ]; then
    echo "[诊断] 检测到 $failure_count 个关键环节失败，输出 Spark 容器最近日志。"
    for container in spark-master spark-worker1 spark-worker2; do
        echo "[诊断] $container 最近 80 行日志："
        docker logs --tail 80 "$container" 2>&1 || true
    done
    exit 1
fi

exit 0
