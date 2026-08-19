# HBase 集群测试说明

## 脚本与依赖

- 脚本：`test/test-hbase.sh`
- 容器：`hbase-master`、`hbase-regionserver1/2`
- 依赖：HDFS 与 ZooKeeper 已启动

```bash
bash test/test-hbase.sh
```

## 测试范围

按照“容器和依赖 → Master 服务 → HBase Shell → 表数据操作 → RegionServer → 清理复核”的流程验证 HBase 集群。

## 详细测试流程

### 1. 检查容器

检查 `hbase-master`、`hbase-regionserver1`、`hbase-regionserver2`，日志记录容器状态和端口。任一容器未运行则停止测试。

### 2. 检查 Master 与 Shell

- 请求 `http://localhost:16210/master-status`。
- 在 Master 容器中运行 HBase Shell `version`，要求输出版本 `2.2.3`。

### 3. 准备测试表

先尝试禁用并删除可能残留的 `test_table`，然后创建两个列族 `cf1`、`cf2`。预清理用于保证重复运行脚本不会因为旧表失败。

### 4. 执行数据操作

按顺序执行：

1. `put` 写入 `row1` 的姓名和年龄。
2. `put` 写入 `row2`。
3. `scan` 确认表内存在 `row1`。
4. `get` 确认 `cf1:name`。
5. `describe` 检查表结构。
6. `count` 统计行数。
7. `list` 确认表已注册。

每条 HBase Shell 命令都有独立描述和预期文本；超时、异常或结果不确定会分别记录。

### 5. 检查集群状态

执行 `status` 并解析 RegionServer 数量，要求至少两个；随后执行 `status 'detailed'` 观察测试表 Region 信息。

### 6. 清理与复核

禁用并删除 `test_table`。报告阶段另外创建 `test_check_table`，确认基本建表能力后立即删除。

## 结果判定

| 环节 | 通过条件 |
|---|---|
| 容器 | Master 和两个 RegionServer 均运行 |
| 服务 | Master Web UI、HBase Shell 可访问 |
| CRUD | 建表、写入、扫描、读取、描述、计数、列表成功 |
| 集群 | 至少两个 RegionServer 注册 |
| 清理 | 测试表可禁用并删除 |

脚本最后重新检查容器、Master Web UI、建表能力和 RegionServer 数量，计算四项关键功能成功率。整体通过必须同时满足：成功率至少 `70%`，并且运行过程中没有记录任何明确失败；否则返回退出码 `1`。

## 关键命令、预期结果与通过条件

| 脚本执行的命令 | 预期结果 | 该项通过条件 |
|---|---|---|
| 请求 `http://localhost:16210/master-status` | curl 退出码为 0 | Master Web UI 可访问 |
| HBase Shell `version` | 输出包含 `2.2.3` | Shell 连接成功且版本匹配 |
| `create 'test_table', 'cf1', 'cf2'` | 出现 `Created table` | 建表命令在 30 秒内成功并匹配文本 |
| 三条 `put` | 每条输出包含 `Took` 且没有 Error/Exception | 三条写入分别通过 |
| `scan 'test_table'` | 输出包含 `row1` | 扫描命令成功并找到指定行 |
| `get 'test_table','row1'` | 输出包含 `cf1:name` | 单行读取返回指定列 |
| `describe`、`count`、`list` | 分别出现表名、`row(s)`、`test_table` | 三条命令均匹配脚本指定文本 |
| `status` | 可解析到至少 `2 servers` | RegionServer 数量不少于 2 |
| `disable` 后 `drop` | drop 输出包含 `Took` | 测试表删除命令成功 |

当前脚本检查 RegionServer 注册和表操作，不宣称执行了 Region 拆分、负载均衡或跨集群复制测试。

## 日志与失败定位

日志保存到 `test/test-log/test-hbase-时间戳.log`。所有终端与 HBase Shell 输出均进入日志；明确失败会使脚本返回非零状态，并追加 Master、两个 RegionServer 的最近容器日志。

常见问题：HDFS 安全模式、ZooKeeper znode 残留、RegionServer 未注册、Master 地址配置错误或测试表残留。
