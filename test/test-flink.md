# Flink 独立集群测试说明

## 脚本与依赖

- 脚本：`test/test-flink.sh`
- 容器：`flink-jobmanager`、`flink-taskmanager1/2`
- Web/REST：http://localhost:18081

```bash
bash test/test-flink.sh
```

## 测试范围

按照“容器 → REST/Dashboard → TaskManager 注册 → CLI → 实际作业”的顺序验证 Flink Standalone 集群。

## 详细测试流程

### 1. 检查容器

检查 `flink-jobmanager`、`flink-taskmanager1`、`flink-taskmanager2`，要求三个容器均处于运行状态。

### 2. 检查 REST API 和 Dashboard

请求：

```text
http://localhost:18081/overview
http://localhost:18081/
```

保存 `/overview` JSON，并检查页面中是否包含 `Flink Dashboard`。

### 3. 校验 TaskManager 注册

从 `/overview` 的 `taskmanagers` 字段解析数量，要求至少两个。数量不足时额外请求 `/taskmanagers` 保存节点明细。

### 4. 检查 CLI

在 JobManager 中执行 `flink --version` 和 `flink list -a`，分别验证安装版本和 CLI 到集群的连接。

### 5. 提交 WordCount

自动查找 `/opt/flink/examples/streaming/*WordCount*.jar`，然后执行 `flink run`。脚本等待有界作业结束，并把作业输出末尾写入日志。

## 结果判定

| 环节 | 通过条件 |
|---|---|
| 容器 | JobManager 和两个 TaskManager 均运行 |
| REST/UI | `/overview` 可解析，Dashboard 页面正确 |
| 注册 | 至少两个 TaskManager |
| CLI | 版本与作业列表命令成功 |
| 作业 | WordCount 提交和执行命令返回成功 |

脚本只有在三个容器、REST、Dashboard、TaskManager 注册数量、两条 CLI 命令和 WordCount 作业全部通过时返回退出码 `0`。

## 关键命令、预期结果与通过条件

| 脚本执行的命令 | 预期结果 | 该项通过条件 |
|---|---|---|
| `curl -fsS http://localhost:18081/overview` | JSON 包含 `taskmanagers` | curl 成功且字段存在 |
| 解析 `/overview` 中的 `taskmanagers` | 数值至少为 2 | 两个 TaskManager 已注册 |
| `curl -fsS http://localhost:18081` | HTML 包含 `Flink Dashboard` | 页面请求成功且标题文本匹配 |
| `docker exec flink-jobmanager /opt/flink/bin/flink --version` | 输出包含 `Version` | 命令成功且版本字段存在 |
| `docker exec flink-jobmanager /opt/flink/bin/flink list -a` | 返回作业列表或空列表 | 命令退出码为 0 |
| `docker exec flink-jobmanager /opt/flink/bin/flink run <WordCount.jar>` | 作业命令正常结束 | `flink run` 退出码为 0 |

本脚本验证 Flink Standalone 集群，不再使用 `flink info` 或仅调用 YARN 帮助命令来冒充功能测试。

## 日志与失败定位

日志保存到 `test/test-log/test-flink-时间戳.log`。日志包括 REST JSON、版本、作业列表和作业提交输出末尾。失败时追加 JobManager 和两个 TaskManager 的最近容器日志，并返回非零状态。

TaskManager 注册不足时优先检查 `jobmanager.rpc.address`、进程内存拆分、网络内存和 Slot 配置。
