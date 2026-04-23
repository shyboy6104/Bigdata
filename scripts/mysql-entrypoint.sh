#!/bin/bash

# ===============================================
# MySQL数据库服务启动脚本
# 作用：初始化MySQL数据目录，创建必要的数据库和用户
# 原理：检测数据目录是否已初始化，如未初始化则执行初始化流程
# 重要性：Hive等组件依赖MySQL存储元数据，确保数据库正确初始化
# ===============================================

# 设置严格错误处理模式：任何命令失败立即退出脚本
set -e

# ===============================================
# 修复配置文件权限问题
# 作用：解决MySQL 8.0忽略world-writable配置文件的问题
# 原理：在容器内重新设置配置文件权限为644
# ===============================================

# 修复配置文件权限
if [ -f "/etc/mysql/my.cnf" ]; then
    chmod 644 /etc/mysql/my.cnf
fi

# ===============================================
# MySQL数据目录初始化检测
# 作用：检查MySQL数据目录是否已经初始化
# 原理：通过检查/var/lib/mysql/mysql目录是否存在判断初始化状态
# 初始化条件：只有在首次启动容器时才执行初始化流程
# ===============================================

# 初始化 MySQL 数据目录
if [ ! -d "/var/lib/mysql/mysql" ]; then
    echo "Initializing MySQL data directory..."
    
    # ===============================================
    # 数据库初始化阶段
# 作用：使用mysqld --initialize命令初始化MySQL数据目录
# 原理：创建系统表、权限表等基础数据库结构
# 安全模式：使用--initialize-insecure避免生成随机root密码
# ===============================================
    
    # 使用 mysqld --initialize 初始化数据库
    mysqld --initialize-insecure --user=mysql --datadir=/var/lib/mysql
    
    # ===============================================
    # 临时MySQL服务器启动
# 作用：启动临时MySQL服务器用于执行初始化SQL
# 原理：使用--skip-networking避免网络连接，确保安全
# 等待时间：sleep 5确保服务器完全启动
# ===============================================
    
    # 启动临时 MySQL 服务器
    mysqld --user=mysql --datadir=/var/lib/mysql --skip-networking &
    sleep 5
    
    # ===============================================
    # 数据库配置阶段
# 作用：设置root密码、创建Hive元数据库和用户
# 原理：通过MySQL客户端连接临时服务器执行SQL语句
# 权限配置：为root和hive用户配置远程访问权限
# ===============================================
    
    # 设置 root 密码和创建必要的数据库
    mysql -u root --socket=/var/run/mysqld/mysqld.sock << EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY 'root';
CREATE USER 'root'@'%' IDENTIFIED BY 'root';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;

-- 创建 hive 元数据库
CREATE DATABASE IF NOT EXISTS hive;
CREATE USER 'hive'@'%' IDENTIFIED BY 'hive';
GRANT ALL PRIVILEGES ON hive.* TO 'hive'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF
    
    # ===============================================
    # 临时服务器关闭
# 作用：安全关闭临时MySQL服务器
# 原理：使用mysqladmin命令发送关闭信号
# 安全考虑：确保临时服务器完全停止后再继续
# ===============================================
    
    # 停止临时 MySQL 服务器
    mysqladmin -u root -proot --socket=/var/run/mysqld/mysqld.sock shutdown
fi

# ===============================================
    # MySQL服务启动阶段
# 作用：启动正式的MySQL服务器进程
# 原理：使用exec "$@"执行Docker Compose传递的启动命令
# 启动模式：支持mysqld的各种启动参数和配置
# ===============================================

# 启动 MySQL 服务器
echo "Starting MySQL server..."
exec "$@"
