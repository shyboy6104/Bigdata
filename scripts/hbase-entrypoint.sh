#!/bin/bash

# ===============================================
# HBase分布式数据库服务启动脚本
# 作用：配置HBase运行环境，根据Hadoop环境动态生成配置文件
# 原理：支持标准Hadoop和HA Hadoop两种环境，自动适配HDFS路径
# 重要性：HBase依赖Hadoop环境，正确的配置确保数据存储正常
# ===============================================

# ===============================================
# 基础环境变量设置
# 作用：设置HBase相关的环境变量和系统路径
# 原理：确保脚本能正确找到HBase和Hadoop的安装位置
# 变量说明：
#   - HBASE_HOME: HBase安装目录
#   - PATH: 包含HBase可执行文件路径
# ===============================================

# 设置环境变量
export HBASE_HOME=/opt/hbase
export PATH=$HBASE_HOME/bin:$PATH

# ===============================================
# 服务启动信息输出
# 作用：输出HBase服务启动信息，便于调试和监控
# 原理：在容器日志中提供清晰的启动信息
# 重要性：便于运维人员了解服务启动状态
# ===============================================

echo "Starting HBase services..."

# ===============================================
# DNS解析配置说明
# 作用：说明Docker环境下的服务发现机制
# 原理：Docker内置DNS自动处理容器间的域名解析
# 优势：使用容器名称进行服务发现，确保可扩展性
# ===============================================

# 配置DNS解析 - 使用Docker内置DNS
echo "Configuring DNS resolution..."
# Docker会自动处理容器间的DNS解析，无需手动配置/etc/hosts
# 使用容器名称进行服务发现，确保可扩展性

# ===============================================
# HBase配置文件复制
# 作用：将外部配置目录中的HBase配置文件复制到安装目录
# 原理：支持配置热更新，便于调试和配置管理
# 配置内容：hbase-site.xml、hbase-env.sh等核心配置
# ===============================================

# 复制配置文件
cp -r /config/hbase/* $HBASE_HOME/conf/

# ===============================================
# Hadoop配置路径设置
# 作用：设置Hadoop配置目录路径
# 原理：HBase需要访问Hadoop配置来连接HDFS
# 路径说明：/opt/hadoop/etc/hadoop是Hadoop的标准配置目录
# ===============================================

# 设置Hadoop配置路径
export HADOOP_CONF_DIR=/opt/hadoop/etc/hadoop

# ===============================================
# 环境配置加载
# 作用：加载外部环境配置文件，支持动态配置
# 原理：如果存在/config/environment.conf文件，则加载其中的配置
# 配置内容：可能包含版本信息、集群参数等自定义配置
# ===============================================

# Docker Compose 显式传入的部署模式优先于共享环境文件中的默认值。
REQUESTED_HADOOP_ENVIRONMENT=${HADOOP_ENVIRONMENT:-}

# 复制正确的Hadoop配置文件到容器中
if [ -f /config/environment.conf ]; then
    source /config/environment.conf
fi

# ===============================================
# Hadoop环境类型设置
# 作用：指定使用的Hadoop环境类型（标准或HA）
# 原理：根据环境类型加载不同的Hadoop配置文件
# 默认值：standard（标准环境），支持ha（高可用环境）
# ===============================================

export HADOOP_ENVIRONMENT=${REQUESTED_HADOOP_ENVIRONMENT:-${HADOOP_ENVIRONMENT:-standard}}

echo "Using Hadoop environment: $HADOOP_ENVIRONMENT"

# ===============================================
# Hadoop环境适配配置
# 作用：根据Hadoop环境类型动态配置HBase的HDFS路径
# 原理：使用sed命令替换配置文件中的占位符
# 配置内容：hbase.rootdir参数，指定HBase数据在HDFS中的存储位置
# ===============================================

if [ "$HADOOP_ENVIRONMENT" = "ha" ]; then
    echo "Copying Hadoop HA configuration..."
    cp -r /config/hadoop-ha/* $HADOOP_CONF_DIR/
    # 动态配置 HBase rootdir 为 HA 模式
    sed -i 's|HBASE_ROOTDIR_PLACEHOLDER|hdfs://mycluster/hbase|g' $HBASE_HOME/conf/hbase-site.xml
elif [ "$HADOOP_ENVIRONMENT" = "standard" ]; then
    echo "Copying standard Hadoop configuration..."
    cp -r /config/hadoop/* $HADOOP_CONF_DIR/
    # 动态配置 HBase rootdir 为 Standard 模式
    sed -i 's|HBASE_ROOTDIR_PLACEHOLDER|hdfs://namenode:8020/hbase|g' $HBASE_HOME/conf/hbase-site.xml
else
    echo "Warning: Unknown Hadoop environment '$HADOOP_ENVIRONMENT', using HA configuration as default"
    cp -r /config/hadoop-ha/* $HADOOP_CONF_DIR/
    sed -i 's|HBASE_ROOTDIR_PLACEHOLDER|hdfs://mycluster/hbase|g' $HBASE_HOME/conf/hbase-site.xml
fi

# 等待Hadoop服务就绪
echo "Waiting for Hadoop services to be ready..."
for i in {1..60}; do
    if /opt/hadoop/bin/hdfs dfs -test -d / > /dev/null 2>&1; then
        echo "HDFS is ready!"
        break
    fi
    echo "Waiting for HDFS... (attempt $i/60)"
    sleep 2
    if [ $i -eq 60 ]; then
        echo "Error: HDFS not ready after 120 seconds"
        exit 1
    fi
done

# 创建HBase在HDFS上的目录
echo "Creating HBase directories in HDFS..."
hdfs dfs -mkdir -p /hbase
hdfs dfs -chmod 755 /hbase

# 每个容器只启动与其角色对应的守护进程。
if [[ "$HOSTNAME" == *"master"* ]]; then
    echo "Starting HBase Master..."
    $HBASE_HOME/bin/hbase-daemon.sh start master
elif [[ "$HOSTNAME" == *"regionserver"* ]]; then
    echo "Starting HBase RegionServer..."
    $HBASE_HOME/bin/hbase-daemon.sh start regionserver
else
    echo "Error: cannot determine HBase role from hostname '$HOSTNAME'"
    exit 1
fi

# 等待HBase服务完全启动
echo "Waiting for HBase services to be fully ready..."
for i in {1..30}; do
    if $HBASE_HOME/bin/hbase shell -e "status" 2>/dev/null | grep -q "active master"; then
        echo "HBase is ready!"
        break
    fi
    echo "Waiting for HBase... (attempt $i/30)"
    sleep 5
    if [ $i -eq 30 ]; then
        echo "Warning: HBase not fully ready after 150 seconds, but continuing..."
    fi
done

# 检查HBase状态
echo "Checking HBase status..."
$HBASE_HOME/bin/hbase shell -e "status"

echo "HBase services started successfully!"

# 保持容器运行
tail -f /dev/null
