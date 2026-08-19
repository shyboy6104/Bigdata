# 大数据实验平台任务清单

本文记录项目当前完成状态和后续改进任务。历史上的“五节点全栈集群改造计划”已经落地，不再作为待办事项重复保留。

## 已完成

- [x] 构建 Ubuntu 20.04 + OpenJDK 8 基础镜像。
- [x] 构建 Hadoop、ZooKeeper、HBase、Hive、Kafka、Spark、Flink、Flume、MySQL 独立镜像。
- [x] 实现 Hadoop 标准集群和 Hadoop HA 集群。
- [x] 实现 ZooKeeper、Kafka、HBase、Spark、Flink 等多节点编排。
- [x] 实现 5 节点全栈统一镜像和 Compose 编排。
- [x] 使用 Supervisor 管理五节点容器内的多个服务进程。
- [x] 实现 HDFS、MySQL、Hive Schema 等首次启动初始化。
- [x] 实现 DataNode/Kafka Cluster ID 和 HBase 残留状态处理。
- [x] 实现五节点服务分阶段启动和健康监控。
- [x] 完成主要 JVM/服务内存预算，目标总量约 15.5 GB。
- [x] 提供交互式与命令行模式的 `bigdata-cli.sh`。
- [x] 提供组件测试、HA 测试、Flume-Kafka 集成测试和五节点综合测试。
- [x] 移除旧 Compose 文件中已废弃的顶层 `version` 字段，并通过全部 Compose 解析校验。
- [x] 为五节点 Hadoop、Flink、Spark 配置保留并补充面向教学的中文字段说明。
- [x] 完善 Flume 测试的分阶段中文日志和失败诊断信息。
- [x] 统一其他组件测试的详细日志、真实退出状态和失败诊断，并补齐同名测试说明文档。
- [x] 逐份对照测试脚本完善同名说明文档，明确测试范围、执行步骤或命令、预期结果、单项通过条件和脚本最终退出条件。
- [x] 提供 Windows Docker Desktop/WSL2 安装说明。
- [x] 提供 PyQt5 配置可视化工具。

## P0：配置正确性与单一来源

这些任务会直接影响服务是否按预期端口和内存运行，应优先完成。每次修改后必须运行对应组件测试和 `test/cluster-test.sh`。

### Hadoop 五节点配置

- [x] 移除 `config/all-in-one/hadoop-master/core-site.xml` 和 `hadoop-worker/hdfs-site.xml` 中显式配置的 Hadoop 2.x 端口 `50010/50075`。
- [x] 统一使用 Hadoop 3.1.3 的 DataNode 端口，并与 entrypoint 健康检查使用的 `9866/9864` 保持一致。
- [x] 将 `dfs.permissions` 改为正式属性 `dfs.permissions.enabled`。
- [x] 验证并删除疑似无效的 `hadoop.heap.size`、`hadoop.rpc.server.address` 等属性；JVM 内存统一由环境变量控制。
- [x] 将 YARN 属性从 `core-site.xml` 收敛到 `yarn-site.xml`，避免同一地址在两个文件重复维护。
- [x] 补齐五节点模式的 `mapred-site.xml`，显式声明 YARN 执行框架和 MapReduce 环境变量。
- [x] 验证 NameNode、DataNode、ResourceManager、NodeManager、MapReduce WordCount 和 Spark on YARN。

### 内存参数统一

- [x] 确定权威规则：Compose 负责节点级预算，entrypoint 只提供缺省值，组件配置文件不重复写死同一进程内存。
- [x] 解决 Flink Compose/entrypoint/YAML 中 512 MB 与 1024 MB 的冲突。
- [x] 统一 Spark Worker、Executor 和 Driver 内存的含义，避免把 Worker 守护进程内存与 Executor 可用内存混为一谈。
- [x] 统一 Hadoop、HBase、Kafka、Hive 的堆内存参数来源。
- [x] 删除未被加载的 `config/all-in-one/memory-optimization.conf`，避免形成无效副本。
- [x] 在集群测试中输出实际 JVM 启动参数，验证配置真正生效。

### Flume Agent 一致性

- [x] 统一独立模式 Agent 名称为 `agent1`。
- [x] 修正 `test/test-flume.sh` 和 `test/test-flume-kafka.sh`，让“无消息”成为测试失败，而不是仅输出警告后继续通过。
- [x] 增加唯一测试消息校验，确认消费到的是本轮写入的数据，而非 Topic 中的历史消息。

### P0 验收记录（2026-08-19）

- [x] 独立组件架构：完成 ZooKeeper、标准 Hadoop、MySQL、Kafka、Flink、HBase、Hive、Spark、Flume 及 Flume → Kafka 链路验收。
- [x] Hadoop：HDFS 读写、2 个 DataNode、2 个 NodeManager、MapReduce WordCount 均通过。
- [x] Kafka：3 Broker、3 分区、3 副本、ISR 和消息收发通过；Flume 唯一消息严格校验通过。
- [x] HBase/Hive：HBase 双 RegionServer 与 CRUD 通过；Hive 建表、写入、查询、删除通过。
- [x] Spark/Flink：Spark Standalone、Spark on YARN、Spark SQL/Streaming 和 Flink 集群注册通过。
- [x] 五节点全栈架构：`test/cluster-test.sh` 共 83 项，83 项通过，0 失败，成功率 100%。
- [x] 五节点最终日志：`test/test-log/cluster-test-20260819-064104.log`。

## P1：配置目录简化

### 可以直接整理的重复内容

- [ ] 删除或归档 `config/all-in-one/hadoop/`。其中 `core-site.xml`、`hdfs-site.xml` 与 `hadoop-master/` 完全相同，当前 entrypoint 不引用该目录。
- [ ] 删除或归档 `config/supervisor/conf.d/`。当前五节点运行使用 `config/all-in-one/supervisor/`，旧目录中的配置还保留 `autostart=true`，容易误导维护者。
- [ ] 删除 `scripts/all-in-one-entrypoint.sh` 中读取不存在的 `/config/all-in-one/environment.conf` 的死分支，或创建并正式使用该文件。
- [ ] 清理 `config/spark/*.template`：如果不参与生成流程则删除；如果作为教学模板则移入明确的 `examples/` 目录。
- [ ] 更新 `config/module-files.md`，区分“已容器化组件”和“仅保存安装包的候选组件”。

### 需要测试后合并的配置

- [ ] 设计 `config/all-in-one/common/`，将主从节点共享的 Hadoop、HBase、Spark、Flink 参数集中管理。
- [ ] 评估五节点 Hadoop 是否可以让 master/worker 共用一套客户端连接配置，仅保留存储目录等角色差异。
- [ ] 评估 HBase master/worker 共用一份 `hbase-site.xml`；Master 专属和 RegionServer 专属属性可由对应进程忽略。
- [ ] 将 Kafka 公共 Broker 参数抽为模板，只动态生成 `broker.id` 和 `advertised.listeners`。
- [ ] 保留 Kafka 1/2/3 的最终渲染结果或教学示例，确保学生仍能观察 Broker 差异。
- [ ] 将配置文件中的长篇原理说明迁移到配置文档或可视化工具，只在运行配置中保留参数用途和非默认值原因。

## P1：启动与 CLI 一致性

- [ ] CLI 同时兼容 `docker compose` 和 `docker-compose`，优先使用 Compose v2 子命令。
- [ ] CLI 构建组件镜像前检查 `bigdata-base:latest`，必要时提示或自动构建。
- [ ] 构建 HBase/Hive 前检查 `bigdata-hadoop:latest`。
- [ ] `start` 前检查并创建外部网络 `bigdata-net`。
- [ ] 增加按依赖顺序启动独立组件的 `deploy` 命令，避免 README 中手工串联多个命令。
- [ ] 明确 Spark 独立模式默认连接 Hadoop 标准还是 HA，避免 Compose 默认值与教学步骤不一致。
- [ ] 修正 Windows `bigdata-cli.bat` 中 Windows 路径直接传给 WSL Bash 的兼容性，使用 `wslpath` 转换。
- [ ] 为五节点 Compose 增加容器级 `healthcheck`，减少仅靠启动脚本轮询端口的依赖。

## P1：测试与回归

- [ ] 在干净数据卷上重新运行所有独立组件测试。
- [ ] 在干净数据卷上重新运行 `test/cluster-test.sh`，记录总测试数、通过数和运行环境。
- [ ] 增加 Compose 静态校验：所有 `docker-compose*.yml` 执行 `docker compose config --quiet`。
- [ ] 增加 XML、YAML、Properties 基础语法校验。
- [ ] 增加配置引用检查，检测 entrypoint 引用不存在的目录或文件。
- [ ] 增加端口一致性检查，对比组件配置、Supervisor、entrypoint 健康检查和 Compose 映射。
- [ ] 增加内存一致性检查，发现同一服务在多处配置不同值时直接失败。
- [ ] 为 Hadoop HA 增加自动故障切换测试，除手动 `haadmin -failover` 外验证 ZKFC 行为。
- [ ] 为 HBase、Hive、Kafka 测试增加失败后的可靠清理和唯一测试资源名。
- [ ] 将测试结果保存为结构化 JSON/JUnit，便于课程验收或 CI 展示。

## P2：教学场景化启动

- [ ] 增加离线数仓场景：HDFS + YARN + Hive + HBase。
- [ ] 增加实时采集场景：ZooKeeper + Kafka + Flume + Flink。
- [ ] 增加批处理场景：HDFS + YARN + Spark。
- [ ] 增加完整数据链路实验：日志 → Flume → Kafka → Flink/Spark → HDFS/Hive。
- [ ] 为每个场景提供启动、验证、清理三组命令。
- [ ] 根据 8 GB、16 GB、32 GB 三档教学电脑提供资源配置示例。
- [ ] 在课程文档中明确 Standalone、YARN、HA、主从、副本和检查点等概念与容器的对应关系。

## P2：配置可视化工具

- [ ] 增加“仅显示非默认项”和“显示全部教学项”两种视图。
- [ ] 同步前显示 diff，并要求确认目标文件。
- [ ] 对端口、内存、主机名、布尔值和路径增加类型校验。
- [ ] 检测同一服务在 Compose、entrypoint 和配置文件中的冲突值。
- [ ] 对 XML/YAML/Properties 保存结果执行语法验证。
- [ ] 将新增组件清单持久化，避免只存在于本次进程内。
- [ ] 增加只读模式，便于课堂演示配置而不误修改源文件。

## P2：安全与可维护性

- [ ] 将 MySQL root/hive 密码移出 Compose，使用 `.env.example` 或 Docker Secret 示例。
- [ ] 为 Kafka、Hive、Hadoop 增加认证与 TLS/Kerberos 的扩展教学方案。
- [ ] 减少容器内以 root 运行的服务，明确目录所有权。
- [ ] 移除未使用的 SSH 服务；确需展示 Hadoop SSH 管理时改为可选 profile。
- [ ] 固定基础镜像摘要并增加镜像漏洞扫描。
- [ ] 为本地安装包增加 SHA256 校验清单。
- [ ] 对数据卷备份、恢复和清理提供明确脚本，危险命令默认要求确认。
- [ ] 增加日志轮转和磁盘占用监控。

## 验收规则

配置或编排变更至少满足以下条件后才能标记完成：

1. `docker compose config --quiet` 校验所有 Compose 文件通过。
2. 相关 XML、YAML、Properties 文件语法正确。
3. 对应独立组件测试通过。
4. 五节点模式受影响时，`test/cluster-test.sh` 通过。
5. README 中的容器名、端口、命令与代码保持一致。
6. 不依赖仓库中已有数据卷或残留运行数据才能启动。
