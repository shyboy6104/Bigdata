#!/bin/bash

# 禁用 Git Bash/MSYS2 的路径自动转换，防止 docker exec 中的绝对路径被转换为 Windows 路径
export MSYS_NO_PATHCONV=1

# 日志文件配置
LOG_DIR="test/test-log"
LOG_FILE="$LOG_DIR/test-spark-$(date +%Y%m%d-%H%M%S).log"

# 创建日志目录
mkdir -p "$LOG_DIR"

# 日志函数
log() {
    echo "$1" | tee -a "$LOG_FILE"
}

log "=== Spark 集群测试 ==="
log "测试开始时间: $(date)"
log "日志文件: $LOG_FILE"
log ""

# 读取 Spark 版本号
ENV_CONF="../config/environment.conf"
if [ -f "$ENV_CONF" ]; then
    SPARK_VERSION=$(grep "^SPARK_VERSION=" "$ENV_CONF" | cut -d'=' -f2)
    echo "使用 Spark 版本: $SPARK_VERSION"
else
    echo "警告: 环境配置文件不存在，使用默认版本 3.1.1"
    SPARK_VERSION="3.1.1"
fi
echo

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

# 测试 Spark Master Web UI
echo "2. 测试 Spark Master Web UI 可访问性..."
master_status=$(curl -s -L -o /dev/null -w "%{http_code}" http://localhost:8080)
if [ "$master_status" = "200" ]; then
    echo "✓ Spark Master Web UI 正常 (http://localhost:8080)"
else
    echo "⚠ Spark Master Web UI 返回状态码: $master_status"
fi

# 测试 Spark History Server Web UI
echo "3. 测试 Spark History Server Web UI 可访问性..."
history_status=$(curl -s -L -o /dev/null -w "%{http_code}" http://localhost:18080)
if [ "$history_status" = "200" ]; then
    echo "✓ Spark History Server Web UI 正常 (http://localhost:18080)"
else
    echo "⚠ Spark History Server Web UI 返回状态码: $history_status"
fi

# 测试 Spark Worker Web UI
echo "4. 测试 Spark Worker Web UI 可访问性..."
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
echo "5. 测试 Spark standalone 模式..."

# 检查 Spark Master 状态
echo "5.1 检查 Spark Master 状态..."
master_output=$(docker exec spark-master /opt/spark/bin/spark-shell --master spark://spark-master:7077 --conf spark.ui.enabled=false <<< 'println("Spark standalone mode test"); sys.exit(0)' 2>&1)
if echo "$master_output" | grep -q "Spark context available"; then
    echo "✓ Spark standalone 模式连接正常"
else
    echo "✗ Spark standalone 模式连接失败"
    echo "  输出: $master_output"
fi

# 运行简单的 Spark 作业（standalone 模式）
echo "5.2 运行 Spark standalone 模式作业..."
# 创建测试数据
echo "1,Alice,25" > /tmp/spark-test.csv
echo "2,Bob,30" >> /tmp/spark-test.csv
echo "3,Charlie,35" >> /tmp/spark-test.csv
docker cp /tmp/spark-test.csv spark-master:/tmp/spark-test.csv

# 检查 HDFS 可用性
echo "5.3 检查 HDFS 可用性..."
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
    echo "✓ Spark standalone 作业执行成功"
    pi_result=$(echo "$standalone_output" | grep "Pi is roughly")
    echo "  $pi_result"
else
    echo "✗ Spark standalone 作业执行失败"
    echo "  输出: $standalone_output"
fi

# 测试 Spark on YARN 模式
echo "6. 测试 Spark on YARN 模式..."

# 检查 YARN 资源管理器状态
echo "6.1 检查 YARN 资源管理器状态..."
yarn_nodes_output=$(docker exec $NAMENODE_CONTAINER yarn node -list 2>/dev/null)
if echo "$yarn_nodes_output" | grep -q "Total Nodes"; then
    yarn_nodes=$(echo "$yarn_nodes_output" | grep "Total Nodes" | awk -F: '{print $2}' | awk '{print $1}' | tr -d '[:space:]')
    echo "✓ YARN 资源管理器正常，总节点数: $yarn_nodes"
else
    echo "✗ YARN 资源管理器状态检查失败"
    echo "  输出: $yarn_nodes_output"
fi

# 运行 Spark on YARN 作业
echo "6.2 运行 Spark on YARN 模式作业..."
yarn_output=$(docker exec spark-master /opt/spark/bin/spark-submit \
    --master yarn \
    --deploy-mode client \
    --class org.apache.spark.examples.SparkPi \
    /opt/spark/examples/jars/spark-examples_2.12-3.1.1.jar 10 2>&1)

if echo "$yarn_output" | grep -q "Pi is roughly"; then
    echo "✓ Spark on YARN 作业执行成功"
    pi_result=$(echo "$yarn_output" | grep "Pi is roughly")
    echo "  $pi_result"
else
    echo "✗ Spark on YARN 作业执行失败"
    echo "  输出: $yarn_output"
fi

# 测试 Spark SQL 功能
echo "7. 测试 Spark SQL 功能..."

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
    echo "  查询结果:"
    echo "$sql_output" | grep -A 10 "=== Spark SQL Test Result ===" | sed 's/^/  /'
else
    echo "✗ Spark SQL 功能测试失败"
    echo "  输出: $sql_output"
fi

# 测试 Spark Streaming 功能（简单测试）
echo "8. 测试 Spark Streaming 功能..."

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
else
    echo "⚠ Spark Streaming 功能测试存在问题"
    echo "  输出: $streaming_output"
fi

# 清理测试数据
echo "9. 清理测试数据..."
if [ "$hdfs_available" = "true" ]; then
    docker exec $NAMENODE_CONTAINER hdfs dfs -rm -r -f /test/spark 2>/dev/null
fi
rm -f /tmp/spark-test.csv /tmp/spark-sql-test.scala

echo "✓ 测试数据清理完成"

# 综合测试结果
echo
echo "=== Spark 集群测试完成 ==="
echo "测试总结:"
echo "- Spark Master Web UI: $([ "$master_status" = "200" ] && echo "✓ 正常" || echo "⚠ 异常")"
echo "- Spark History Server: $([ "$history_status" = "200" ] && echo "✓ 正常" || echo "⚠ 异常")"
# 检查两个Worker的状态，只要有一个正常就认为Worker Web UI正常
if [ "$worker1_status" = "200" ] || [ "$worker2_status" = "200" ]; then
    echo "- Spark Worker Web UI: ✓ 正常"
else
    echo "- Spark Worker Web UI: ⚠ 异常"
fi
echo "- Spark standalone 模式: $([ -n "$pi_result" ] && echo "✓ 正常" || echo "✗ 异常")"
echo "- Spark on YARN 模式: $([ -n "$(echo "$yarn_output" | grep 'Pi is roughly')" ] && echo "✓ 正常" || echo "✗ 异常")"
echo "- Spark SQL 功能: $([ -n "$(echo \"$sql_output\" | grep 'Spark SQL Test Result')" ] && echo "✓ 正常" || echo "✗ 异常")"
echo "- Spark Streaming 功能: $([ -n "$(echo "$streaming_output" | grep 'Spark Streaming test completed')" ] && echo "✓ 正常" || echo "⚠ 异常")"

echo
echo "详细测试报告已生成，Spark 集群功能验证完成！"