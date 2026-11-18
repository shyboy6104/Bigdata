#!/usr/bin/env bash
# 用容器自带的 Hadoop 客户端编译并提交 MapReduce WordCount。
# 前置：先启动 hadoop（网页 /portal 里点 Hadoop）。
# 运行：bash java/run-wordcount.sh
set -e

# 登录 shell 会自动加载；这里显式 source 保证脚本单独执行也可用。
[ -f /etc/profile.d/bigdata-client.sh ] && . /etc/profile.d/bigdata-client.sh
: "${BIGDATA_JARS:?BIGDATA_JARS 未生成，请检查容器启动日志}"

cd "$(dirname "$0")"
mkdir -p classes

echo "=== 1/4 编译 Java 源码（离线，使用容器自带客户端 jar）==="
javac -encoding UTF-8 -cp "$BIGDATA_JARS" -d classes WordCount.java
jar -cf wordcount.jar -C classes .

echo "=== 2/4 准备 HDFS 输入 ==="
printf 'hello spark hello flink\nkafka hive hadoop mapreduce\nspark flink kafka\n' > /tmp/wc-input.txt
hdfs dfs -mkdir -p /user/root/wc-input
hdfs dfs -put -f /tmp/wc-input.txt /user/root/wc-input/
hdfs dfs -rm -r -f /user/root/wc-output

echo "=== 3/4 提交 MapReduce 作业 ==="
hadoop jar wordcount.jar WordCount /user/root/wc-input /user/root/wc-output

echo "=== 4/4 结果 ==="
hdfs dfs -cat /user/root/wc-output/part-r-00000
