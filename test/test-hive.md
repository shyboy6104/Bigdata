# Hive 数据仓库测试说明

## 脚本与依赖

- 脚本：`test/test-hive.sh`
- 容器：`hive-server2`、`hive-metastore`、`hive-cli`
- 依赖：MySQL、HDFS/YARN

```bash
bash test/test-hive.sh
```

## 测试范围

从服务启动、元数据连接、HiveQL 到 HDFS 存储，验证 HiveServer2、Metastore、CLI 和 Hadoop 的联动。

## 详细测试流程

### 1. 检查容器

检查 `hive-server2`、`hive-metastore`、`hive-cli`。若容器不完整，脚本直接退出并保留容器状态。

### 2. 等待并连接 HiveServer2

每两秒使用 Beeline 执行一次 `SHOW DATABASES`，最多等待 120 秒。就绪后再次执行连接检查，并用 `hive-cli` 执行相同查询，区分 JDBC 服务和传统 CLI 问题。

### 3. 创建数据库和普通表

清理旧 `test_db` 后，创建 `employees` 表，字段包括编号、姓名、年龄、城市、工资和部门。

### 4. 插入并查询数据

插入三条中文员工数据，然后依次执行：

- 全表查询；
- `department='技术部'` 条件查询；
- 按部门计算平均工资；
- 按年龄降序排序；
- `DESCRIBE`、`SHOW DATABASES`、`SHOW TABLES`；
- `COUNT(*)` 行数统计。

每条 SQL 都有预期关键文本，日志保留 Beeline 输出末尾。

### 5. 测试分区表和外部表

创建 `sales` 分区表，向 `year=2024/month=1` 写入两行并查询；随后创建 LOCATION 为 `/tmp/external_test` 的外部表。

### 6. 检查 HDFS

执行 `hdfs dfs -ls /user/hive/warehouse/`，确认 Hive 数据实际落在 HDFS，而不是仅验证 Metastore 中有表名。

### 7. 清理和报告复核

删除 `test_db`。报告阶段再创建并删除普通检查表和分区检查表，用于验证清理后的基本能力仍正常。

## 结果判定

| 环节 | 通过条件 |
|---|---|
| 服务 | 三个容器运行，HiveServer2 在 120 秒内可连接 |
| 普通表 | 建库、建表、插入和各类查询成功 |
| 高级表 | 分区表写入查询成功，外部表可创建 |
| HDFS | Warehouse 目录可访问 |
| 清理 | 测试数据库删除成功 |

脚本报告阶段复核五项关键功能：容器、HiveServer2、普通建表、分区建表和 HDFS。整体通过必须同时满足成功率至少 `70%`，并且运行过程中没有记录明确失败；否则返回退出码 `1`。

## 关键命令、预期结果与通过条件

| 脚本执行的 SQL/命令 | 预期结果 | 该项通过条件 |
|---|---|---|
| Beeline `SHOW DATABASES` | 命令成功返回 | 120 秒内首次成功，随后 30 秒连接检查也成功 |
| Hive CLI `SHOW DATABASES` | 命令退出码为 0 | CLI 连接项通过；异常会记录为警告 |
| 建库、选库、建表、INSERT | 输出包含 `No rows affected` 或 `StatsTask...SUCCESS` | 每条 SQL 匹配脚本指定成功文本 |
| `SELECT * FROM employees` | 输出包含 `张三` | 全表查询通过 |
| 技术部条件查询 | 输出包含 `技术部` | 条件查询通过 |
| 部门平均工资聚合 | 输出包含 `avg_salary` | 聚合查询通过 |
| 年龄降序查询 | 输出包含 `李四` | 排序查询通过 |
| `DESCRIBE`、`SHOW DATABASES`、`SHOW TABLES`、`COUNT` | 分别包含 `id`、`test_db`、`employees`、`total` | 四项元数据与统计查询分别通过 |
| 分区表插入与查询 | 查询输出包含 `产品A` | 分区表链路通过 |
| 创建外部表 | 输出包含 `No rows affected` | 外部表创建成功 |
| `hdfs dfs -ls /user/hive/warehouse/` | 命令退出码为 0 | Warehouse 路径可访问 |
| `DROP DATABASE IF EXISTS test_db CASCADE` | 输出包含 `No rows affected` | 测试数据库清理成功 |

脚本没有专门加载自定义 UDF，也不把“查看执行计划”列为已覆盖能力。

## 日志与失败定位

日志保存到 `test/test-log/hive-test-时间戳.log`。Beeline、HDFS 和容器输出统一写入日志；SQL 失败会保存输出末尾。存在明确失败时追加 HiveServer2、Metastore、CLI 容器日志并返回非零状态。

常见问题：Metastore JDBC 地址、MySQL Schema、HiveServer2 初始化耗时、HDFS 权限以及 MapReduce/YARN Container 失败。
