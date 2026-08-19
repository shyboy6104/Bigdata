# MySQL 与 Hive 元数据库测试说明

## 脚本与依赖

- 脚本：`test/test-mysql.sh`
- 容器：独立架构的 `mysql`
- 账户：教学环境默认 `root/root`、`hive/hive`

```bash
bash test/test-mysql.sh
```

## 测试范围

按照“容器 → 服务就绪 → 账户 → Hive 元数据库 → CRUD → 清理”的流程验证独立 MySQL 服务。

## 详细测试流程

### 1. 检查容器

执行 `docker inspect mysql`，要求容器存在且 `Running=true`。日志记录容器状态和退出码。

### 2. 等待 MySQL 就绪

每两秒运行 `mysqladmin ping -uroot -proot`，最多 30 次。输出必须包含 `mysqld is alive`，否则在 60 秒后判定启动超时。

### 3. 检查账户和元数据库

- root 用户执行 `SELECT 'root-connection-ok'` 并精确匹配结果。
- 在 `information_schema.SCHEMATA` 中查询独立架构使用的 `hive` 数据库。
- hive 用户执行 `SELECT 'hive-connection-ok'` 并精确匹配结果。

### 4. 执行 CRUD

创建 `test_db_<时间戳_进程号>`，然后：

1. 创建带主键和字符串列的 `test_table`；
2. 插入 `mysql-value-<时间戳-进程号>`；
3. 按主键查询；
4. 要求查询值与本轮写入值完全一致。

### 5. 清理

删除唯一测试数据库。脚本退出前还会执行 `DROP DATABASE IF EXISTS` 兜底清理。

## 结果判定

| 环节 | 通过条件 |
|---|---|
| 服务 | 60 秒内响应 mysqladmin ping |
| 账户 | root、hive 均能执行查询 |
| 元数据 | `hive` 数据库存在 |
| CRUD | 建库、建表、插入、精确查询均成功 |
| 清理 | 测试数据库删除成功 |

脚本只有在所有断言通过、汇总失败数为 `0` 时返回退出码 `0`。`mysqladmin ping` 成功但账户登录、元数据库或 CRUD 任一项失败，整体仍判定失败。

## 关键命令、预期结果与通过条件

| 脚本执行的命令 | 预期结果 | 该项通过条件 |
|---|---|---|
| `docker inspect mysql` | `Running=true` | 容器存在且正在运行 |
| `mysqladmin ping -uroot -proot` | `mysqld is alive` | 60 秒内命令成功且包含 `alive` |
| `SELECT 'root-connection-ok'` | 精确返回该字符串 | root 查询退出码为 0 且结果逐行匹配 |
| 查询 `information_schema.SCHEMATA` | 返回 `hive` | 查询成功且结果精确为 `hive` |
| hive 用户执行 `SELECT 'hive-connection-ok'` | 精确返回测试字符串 | hive 用户查询成功且结果逐行匹配 |
| 创建库、建表和 INSERT | 各 SQL 退出码为 0 | 三个写操作均执行成功 |
| INSERT 后按主键 SELECT | 返回本轮唯一值 | 查询退出码为 0 且结果与写入值完全一致 |
| `DROP DATABASE <唯一库>` | 命令退出码为 0 | 测试数据库删除成功 |

## 日志与失败定位

日志保存到 `test/test-log/test-mysql-时间戳.log`。每个 SQL 环节记录明确结果；失败时保留客户端错误、进程列表和 MySQL 最近容器日志。任一关键断言失败，脚本返回非零状态。

五节点架构的 MySQL 位于 `infra` 容器且数据库名为 `hive_metastore`，由 `cluster-test.sh` 验证；不要直接用本脚本测试 `infra`。
