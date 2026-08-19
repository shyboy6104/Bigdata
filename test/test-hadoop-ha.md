# Hadoop HA 集群测试说明

## 脚本与依赖

- 脚本：`test/test-hadoop-ha.sh`
- 容器：`namenode1/2`、`journalnode1/2/3`、`datanode1/2`
- 外部依赖：`zoo1/2/3`

```bash
bash test/test-hadoop-ha.sh
```

## 测试范围

沿着“JournalNode 仲裁 → NameNode 主备 → HDFS 同步 → 受控切换 → YARN/MapReduce”的流程验证 Hadoop HA 配置。

## 详细测试流程

### 1. 检查基础容器和 JournalNode

列出 NameNode、DataNode、JournalNode 容器，并在三个 JournalNode 内执行 `jps`。每个节点都必须存在一个 JournalNode 进程。

### 2. 确认 NameNode 主备关系

分别执行：

```bash
hdfs haadmin -getServiceState nn1
hdfs haadmin -getServiceState nn2
```

期望得到一个 `active` 和一个 `standby`。脚本据此确定后续操作目标，而不是固定假设 `namenode1` 永远为 Active。

### 3. 检查 Web UI 和 HDFS

访问两个 NameNode Web UI，随后在 Active 节点执行 `hdfs dfsadmin -report`。日志记录当前 Active、Standby、DataNode 数量和页面状态码。

### 4. 验证数据同步

在 Active 创建 `/test` 下的测试目录并上传唯一内容，然后通过 HA 逻辑命名服务读取文件。读取结果必须与写入内容相同，用于确认客户端访问不会依赖某一个物理 NameNode。

### 5. 执行受控故障转移

调用：

```bash
hdfs haadmin -failover <当前Active> <当前Standby>
```

再次查询双 NameNode 状态，确认角色交换，并在新的 Active 上执行 HDFS 操作。验证后尝试恢复原角色。

### 6. 验证 YARN 和 MapReduce

在当前可用 NameNode 容器中执行 `yarn node -list`，然后提交 WordCount。日志记录 YARN 节点列表、作业输出和结果读取状态。

### 7. 清理

删除 `/test` 下本轮文件，并移除宿主机临时输入文件。

## 结果判定

| 环节 | 通过条件 |
|---|---|
| JournalNode | 三个 JournalNode 进程均存在 |
| NameNode | 恰好一个 Active、一个 Standby |
| HDFS 同步 | 写入数据能够通过 HA 文件系统读回 |
| 手工切换 | `haadmin -failover` 后角色成功交换，新 Active 可操作 |
| YARN/MapReduce | 节点列表正常且 WordCount 成功 |

脚本汇总 JournalNode、NameNode HA、Web UI、HDFS、数据同步、故障转移、YARN 和 MapReduce 的结果。日志中出现明确的 `✗` 项即表示对应步骤失败；最终应返回退出码 `0`，否则整体不通过。

## 关键命令、预期结果与通过条件

| 脚本执行的命令 | 预期结果 | 该项通过条件 |
|---|---|---|
| `docker exec journalnodeN jps` | 每个节点出现一个 `JournalNode` | 三次检查全部得到计数 1 |
| `hdfs haadmin -getServiceState nn1/nn2` | 一个返回 `active`，另一个返回 `standby` | 两个状态均可读取，并能确定 Active 和 Standby |
| `curl` 访问两个 NameNode Web UI | HTTP 200 | Active 与 Standby 对应页面均成功响应 |
| `hdfs dfsadmin -report` | 能解析 Live DataNode 数量 | 输出中存在 `Live datanodes` 数值 |
| 上传后执行 `hdfs dfs -cat` | 返回 `Hadoop HA Test Data` | 从 Standby 容器发起读取时内容完全一致 |
| `hdfs haadmin -failover ...` | nn1/nn2 状态至少一个发生变化 | 等待 10 秒后角色与切换前不同 |
| 切换后再次 `hdfs dfs -cat` | 返回原测试内容 | 新 Active 可以读取既有数据 |
| `yarn node -list` | 输出包含 `Total Nodes` | 能解析 YARN 总节点数 |
| MapReduce WordCount | 输出包含 `completed successfully` 且结果文件非空 | 作业完成并可读取输出 |

脚本当前只执行 `haadmin -failover` 受控切换，不会停止容器模拟宕机，因此不包含 ZKFC 自动故障转移测试。

## 日志与失败定位

日志保存到 `test/test-log/test-hadoop-ha-时间戳.log`。终端中的 Docker、HDFS、HA、YARN 和 MapReduce 输出会完整进入日志。汇总发现失败时，脚本返回非零状态，并追加双 NameNode、三个 JournalNode 和两个 DataNode 的最近日志。

重点排查：ZooKeeper/ZKFC 连接、JournalNode 仲裁、`dfs.nameservices`、NameNode 格式化状态以及 ResourceManager/NodeManager 注册。
