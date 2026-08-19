# Hadoop 标准集群测试说明

## 脚本与依赖

- 脚本：`test/test-hadoop.sh`
- 容器：`namenode`、`datanode1`、`datanode2`
- 服务：HDFS、YARN、MapReduce、NameNode/ResourceManager Web UI

在项目根目录执行：

```bash
bash test/test-hadoop.sh
```

## 测试范围

按照“容器 → 管理页面 → HDFS → YARN → MapReduce → 清理”的顺序，验证标准 Hadoop 集群从基础进程到实际计算作业的完整链路。

## 详细测试流程

### 1. 检查容器

依次对 `namenode`、`datanode1`、`datanode2` 执行 `docker inspect`。不仅检查容器是否存在，还要求 `Running=true`；任一容器未运行即停止后续测试。

### 2. 检查管理页面

- 请求 `http://localhost:19870`，要求 NameNode Web UI 返回 HTTP 200。
- 请求 `http://localhost:18088`，跟随重定向后要求 ResourceManager Web UI 返回 HTTP 200。

### 3. 检查 HDFS 集群状态

在 `namenode` 中执行：

```bash
hdfs dfsadmin -report
hdfs dfsadmin -safemode get
```

日志会保存容量摘要和 DataNode 名称。判定条件是至少两个 Live DataNode，且安全模式为 OFF。

### 4. 验证 HDFS 文件操作

脚本创建 `/test/hadoop-<时间戳-进程号>/input`，通过标准输入写入：

```text
hello world hello hadoop
```

随后依次执行 `hdfs dfs -cat` 和 `hdfs dfs -stat`。读取内容必须与写入文本完全一致，日志还会记录文件长度、副本数和块大小。

### 5. 验证 YARN

执行 `yarn node -list` 和 `yarn application -list`。日志保存完整节点列表，要求至少两个 NodeManager 处于 RUNNING 状态，并能正常访问应用管理接口。

### 6. 运行 MapReduce

脚本自动定位 `hadoop-mapreduce-examples-*.jar`，使用前面的 HDFS 文件作为输入运行 WordCount。作业必须正常结束，输出必须包含：

```text
hello   2
hadoop  1
```

### 7. 清理

删除本轮唯一 HDFS 测试目录。即使前面失败，脚本结束前仍会执行兜底清理。

## 结果判定

| 环节 | 通过条件 |
|---|---|
| 容器 | NameNode、两个 DataNode 均为运行状态 |
| Web UI | NameNode、ResourceManager 均返回 HTTP 200 |
| HDFS | 至少两个 DataNode、安全模式 OFF、写入内容可精确读回 |
| YARN | 至少两个 RUNNING NodeManager，应用列表命令成功 |
| MapReduce | 作业成功，WordCount 结果精确匹配 |
| 清理 | 本轮 HDFS 目录删除成功 |

脚本只有在上述关键项全部通过、汇总中的失败数为 `0` 时才返回退出码 `0`。MapReduce 命令执行成功但输出计数不正确，仍然判定测试失败。

## 关键命令、预期结果与通过条件

| 脚本执行的命令 | 预期结果 | 该项通过条件 |
|---|---|---|
| `docker inspect namenode` | `Running=true`、退出码为 0 | 容器存在且正在运行 |
| `docker exec namenode hdfs dfsadmin -report` | `Live datanodes (2)` 及两个 DataNode 明细 | 可解析出的 Live DataNode 数量不少于 2 |
| `docker exec namenode hdfs dfsadmin -safemode get` | `Safe mode is OFF` | 命令成功且输出包含 `OFF` |
| `docker exec namenode hdfs dfs -cat <文件>` | 输出 `hello world hello hadoop` | 输出与写入内容逐字一致 |
| `docker exec namenode yarn node -list` | 至少两行 `RUNNING` | RUNNING NodeManager 数量不少于 2 |
| `hadoop jar ... wordcount <输入> <输出>` | 日志出现 `completed successfully` | 作业命令成功且出现成功标记 |
| `hdfs dfs -cat <输出>/part-r-00000` | `hello<TAB>2`、`hadoop<TAB>1` | 两个精确计数都存在 |

## 日志与失败定位

日志保存到 `test/test-log/test-hadoop-时间戳.log`。每个失败项会记录实际命令输出；出现失败时还会附加 NameNode、DataNode 的 Java 进程和最近容器日志。只要关键断言失败，脚本就以非零状态退出。

常见定位方向：

- DataNode 不足：查看 Cluster ID、数据卷和 DataNode 日志。
- HDFS 拒绝写入：检查安全模式和 `dfs.permissions.enabled`。
- YARN 节点不足：检查 ResourceManager/NodeManager 地址及日志。
- MapReduce 失败：查看作业输出末尾和 `yarn logs -applicationId <id>`。
