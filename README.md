# 大数据分布式服务实验平台

本项目面向大数据相关课程和实验教学，在 Windows 10/11 + WSL2 环境中，使用 Docker 与 Docker Compose 搭建可重复部署的大数据分布式实验平台。

平台覆盖镜像构建、集群编排、配置管理、服务初始化、健康监控和功能测试，支持“先学习单个组件，再进行全栈综合实训”的教学路径。

## 项目状态

- 已实现 Hadoop（标准 / HA）、ZooKeeper、HBase、Hive、MySQL、Kafka、Spark、Flink、Flume 9 类组件，以及 `client` 代码开发容器。
- 已实现独立组件架构与 5 节点全栈架构（Supervisor 多进程管理），适用于单组件教学和综合实训。
- 已提供网页版多用户实验平台：账号登录、每用户独立容器栈、组件依赖自动启动、局域网访问、逐条命令终端与全交互 TTY。
- 已提供统一 CLI（中 / 英文）、组件测试脚本、PyQt5 配置可视化工具与 `examples/` 教学示例。
- `bigdata-client` 采用两阶段构建，镜像体积 7.15GB → 4.23GB；ZooKeeper 宿主机端口避开 Windows 保留区间，Kafka 具备 ClusterId 自愈。
- 项目定位为教学与实验环境，不建议未经安全加固直接用于生产。

## 组件与版本

版本的主要维护入口是 `config/environment.conf`。

| 组件 | 版本 | 教学用途 |
|---|---:|---|
| Hadoop | 3.1.3 | HDFS、YARN、MapReduce |
| ZooKeeper | 3.6.3 | 分布式协调与选主 |
| HBase | 2.2.3 | HDFS 上的分布式列式数据库 |
| Hive | 3.1.2 | 数据仓库与 SQL 查询 |
| MySQL | 5.7 | Hive Metastore 元数据存储 |
| Kafka | 2.4.1 | 分布式消息队列 |
| Flume | 1.9.0 | 日志采集与 Kafka 联动 |
| Spark | 3.1.1 | Standalone 与 YARN 批处理 |
| Flink | 1.14.0 | 流批处理与作业提交 |
| Client | — | 代码开发/作业提交容器，预装全套客户端与 Python/Java 库 |

`module/` 中还保存了 Kylin、ClickHouse、Hudi、Redis、Sqoop 等安装包，但当前没有对应的 Dockerfile、Compose、启动脚本和测试，因此不属于已交付组件。

## 两种部署架构

### 1. 独立组件架构

每个组件使用单独的 Dockerfile、Compose 文件和启动脚本，所有服务通过外部网络 `bigdata-net` 互联。

| 组件 | 实际服务/容器 | 说明 |
|---|---|---|
| Hadoop | `namenode`、`datanode1`、`datanode2` | NameNode 同时运行 ResourceManager 和 JobHistoryServer；DataNode 同时运行 NodeManager |
| Hadoop HA | `namenode1/2`、`journalnode1/2/3`、`datanode1/2` | 依赖外部 ZooKeeper，使用 QJM、ZKFC 和双 ResourceManager |
| ZooKeeper | `zoo1/2/3` | 3 节点仲裁集群 |
| HBase | `hbase-master`、`hbase-regionserver1/2` | 依赖 HDFS 和 ZooKeeper |
| Hive | `hive-metastore`、`hive-server2`、`hive-cli` | 依赖 HDFS 和 MySQL |
| Kafka | `kafka1/2/3` | ZooKeeper 模式的 3 Broker 集群 |
| Spark | `spark-master`、`spark-worker1/2` | 支持 Standalone 和 YARN |
| Flink | `flink-jobmanager`、`flink-taskmanager1/2` | Standalone 集群 |
| Flume | `flume-kafka` | 默认演示日志与 Kafka 数据链路 |
| MySQL | `mysql` | 保存 Hive 元数据 |

适合课程中的单组件原理、配置观察、命令操作和故障实验。

### 2. 五节点全栈架构

`docker-compose.5-node-cluster.yml` 使用同一个 `bigdata-all-in-one:latest` 镜像，根据容器主机名分配角色。

| 节点 | 运行服务 | 计划内存 |
|---|---|---:|
| `master` | NameNode、ResourceManager、HMaster、Hive Metastore、HiveServer2、Spark Master、Flink JobManager | 4.0 GB |
| `worker-1` | DataNode、NodeManager、ZooKeeper、Kafka、RegionServer、Spark Worker、Flink TaskManager | 3.5 GB |
| `worker-2` | 同 `worker-1` | 3.5 GB |
| `worker-3` | 同 `worker-1` | 3.5 GB |
| `infra` | MySQL、Flume | 1.0 GB |

计划 JVM/服务内存合计约 15.5 GB。Docker Desktop/WSL2 建议至少分配 16 GB；如果物理内存不足，应按教学场景分批启动组件。

五节点模式是标准单 NameNode 架构，不提供 Hadoop HA。它主要用于组件联动、资源规划和综合实训。

## 多用户实验平台（网页版）

`docker-manager/docker-relay.py` 在原有 Docker/大数据网页管理之外，提供账号体系与**每用户独立容器环境**：管理员为普通用户分配账号密码，学生登录后即可自行开设一套大数据组件容器，各用户互不影响。

### 启动与登录

```bat
docker-manager\start.bat              :: 默认 http://127.0.0.1:8000/login
docker-manager\start-lan.bat          :: 局域网可访问（0.0.0.0，不设令牌），供学生从自己电脑登录
```

- 首次启动自动创建管理员 `admin / admin123`（可用环境变量 `ADMIN_PASSWORD` 指定），**请登录后立即修改**。
- 页面入口：`/login` 登录 · `/` Docker 管理器（管理员）· `/bigdata` 大数据平台（管理员）· `/users` 用户管理（管理员）· `/portal` 我的实验环境（普通用户）。
- 组件镜像需先由管理员在 `/bigdata` 构建；普通用户只能启停自己的容器，不能构建/删除镜像。
- `RELAY_TOKEN` 仍可设置（兼容旧用法）：带正确令牌的请求**视为管理员**；正常教学场景请直接用账号登录，**切勿把令牌发给学生**。
- `BIGDATA_USERS_FILE` 可指定用户库路径（默认 `docker-manager/users.json`），便于多实例或测试隔离。

### 局域网访问（学生从自己电脑打开）

默认 `start.bat` 只监听 `127.0.0.1`，此时 **`http://<服务器IP>:8000/portal` 打不开**。要开放给学生：

```bat
:: 1. 先关闭旧的 "BigData Relay" 窗口（启动脚本有端口幂等检查，端口被占用时不会重新绑定）
:: 2. 再运行局域网启动脚本（不带令牌）；如需自定义端口：start-lan.bat "" 9000
docker-manager\start-lan.bat
```

启动窗口会打印多个 `http://<IP>:8000/login`，**选与学生同一网段的物理网卡 IP**（VMware / WSL / vEthernet 等虚拟网卡地址要排除）。发给学生的地址是 **`/login`**：登录后普通用户自动进入 `/portal`，管理员进入 `/`；直接访问 `/portal` 而未登录时，页面会自行跳转到 `/login`。

- 页面、API、WebSocket 全交互终端、端口徽章链接都按浏览器当前访问的主机名同源拼接，局域网下无需额外配置。
- **不要启用 `RELAY_TOKEN` 并把令牌发给学生**：带正确令牌的请求会被视作管理员，可增删账号并操作宿主机全部容器。`start-lan.bat` / `start-lan.sh` 默认已改为不设令牌，统一用账号登录。
- **Windows 防火墙**：若网络被识别为「公用网络(Public)」，系统对 `python.exe` 的显式阻止规则可能拦掉 8000 入站。把该网络设为「专用网络(Private)」，或由管理员添加 TCP 8000 入站允许规则（并确认没有优先级更高的程序级阻止规则）。
- 学生机与服务器需在同一可达网段；校园网若开启 AP/客户端隔离，需联系网络管理员放通。

### 管理员操作（/users）

创建账号（用户名 + 初始密码）、重置密码（旧会话立即失效）、禁用/启用、删除用户（可勾选**同时销毁该用户全部容器与数据**）。列表显示每个用户的 UID、端口段与已创建环境。

### 隔离机制

| 维度 | 规则 |
|---|---|
| Compose 项目名 | `bigdata-u<uid>`，各组件同属该项目以便服务名互访 |
| 容器名 | `u<uid>-原容器名`，全局唯一，避免多用户重名冲突 |
| 网络 | `bigdata-u<uid>-net`（外部网络，各用户独立，跨用户不可互通） |
| 宿主机端口 | 每用户 200 个端口：`20000 + (uid-1)*200`，每组件 20 个槽位；容器内部端口不变 |
| 数据 | 具名卷自动带项目前缀；`./data/...` 落到 `stacks/<用户名>/data/`；`./config/...` 指向项目共享只读配置 |

生成的用户专属 compose 保存在 `stacks/<用户名>/docker-compose.<组件>.yml`，不纳入版本管理。

### 组件依赖（自动处理）

启动计算组件时后端会按拓扑顺序自动先启动前置组件，已运行的依赖自动跳过：

| 目标组件 | 自动前置 |
|---|---|
| Spark | Hadoop（`HADOOP_ENVIRONMENT=standard`）或 Hadoop HA（`ha`） |
| Hive | Hadoop/Hadoop HA + MySQL |
| HBase | Hadoop/Hadoop HA + ZooKeeper |
| Kafka | ZooKeeper |
| Flume | Kafka（进而带起 ZooKeeper） |

Spark 入口脚本会阻塞等待 `namenode:8020`，因此该顺序是必需的；依赖就绪后日志出现 `HDFS NameNode is ready!`，Master 随即启动。

### 进入容器执行命令

普通用户在 `/portal` 启动组件后，运行中的容器右侧提供两个入口：

| 入口 | 形态 | 适用场景 |
|---|---|---|
| **>_ 终端** | 页面内逐条命令面板 | 快速执行单条命令、查看输出；轻量、无需长连接 |
| **▣ 全交互** | 新标签页打开 `/terminal?container=<容器名>` | **真实 TTY**：`vim` / `top` / `spark-shell` / `hdfs dfs`，Tab 补全、Ctrl+C、命令历史 |

#### 逐条命令终端（`>_ 终端`）

- 后端 `POST /api/portal/exec-container`，等价于 `docker exec -i <容器> bash -lc "<命令>"`；镜像无 bash 时自动回退 `sh`。
- 返回输出与退出码，自动保留 `cd` 后的工作目录；支持 ↑↓ 历史、Ctrl+L 清空、9 个快捷命令。
- 单条命令默认 60 秒（上限 120 秒）超时中断；面板可复制 `docker exec -it <容器> bash` 供本机终端使用。

#### 全交互 TTY（`▣ 全交互`）

- `GET /api/portal/term-ws?container=<容器名>` 是原生 WebSocket（**纯 Python 标准库实现 RFC 6455**，无第三方后端依赖），浏览器端用本地静态资源 `docker-manager/vendor/xterm.min.js`（xterm.js 5.3.0，MIT，离线可用）。
- Windows 上 `docker exec -it` 要求父进程 stdin 本身是 TTY，Python 服务不满足；后端改为在容器内用 util-linux 的 `script` 创建伪终端：
  `docker exec -i <容器> script -q -c "stty rows 40 cols 120; exec bash -l" /dev/null`，
  容器内得到 `/dev/pts/X`，因此 `vim` / `top` 等全屏程序能正常工作。
- 终端固定 **120×40**，页面提供字号缩放；动态调整窗口尺寸需要 Docker Engine API 的 exec resize，当前版本未实现。
- 输入 `exit`、点「发送 exit」或直接关闭页面，后端都会让 shell 正常退出并清理 PTY 进程，不会在容器内残留交互进程。

#### 共用的安全边界

两种入口共用 `user_container_allowed()` 三重校验：容器名前缀 `u<uid>-`、`com.docker.compose.project` / `.service` 标签必须属于本人 compose 项目、容器必须正在运行，且 inspect 返回的真实容器名与传入一致。普通用户无法进入他人容器、宿主机主平台容器或手工伪造的同名容器；WebSocket 握手同样要求登录会话（Cookie 为 `SameSite=Lax`）。

### 示例目录

`examples/` 统一存放教学代码，两类示例**运行位置不同**，不要混用：

| 目录 | 运行位置 | 用途 | 进镜像 |
|---|---|---|---|
| `examples/client/` | client 容器内的 `/workspace` | 预装客户端的 Python / Java 示例。`dockerfile.client` 拷入 `/opt/client-examples/`，每次启动按文件粒度增量投放给学生，学生可直接在其上改代码 | **是**（构建输入） |
| `examples/course/` | 宿主机 Windows（conda PySpark） | 课堂讲义与 PySpark 本地 / 容器 / HDFS 演示脚本，含 `.md` 说明；已在 `.dockerignore` 中排除 | 否 |

运行态代码目录另计：主平台 `./workspace`、学生 `stacks/<用户名>/workspace`，都是挂载卷，已加入 `.gitignore`。

### 代码开发容器（client）

`docker-compose.client.yml` + `dockerfile.client` 提供一个**只装客户端、不启动任何服务**的开发节点，用于编写、提交、运行 Spark / Flink / MapReduce 代码，并通过代码调用 HDFS / Hive / Kafka / Flume 的 API。主平台在 `/bigdata` 注册为「代码开发」，普通用户在 `/portal` 也能各开一套（独立网络、独立 `/workspace` 代码目录）。

**镜像**：`bigdata-client:latest`，父镜像为 `bigdata-spark:latest`（**须先构建 Spark 镜像**）。安装包全部取自 `module/` 离线包，版本与 `config/environment.conf` 一致。

> **镜像体积（2026-11-18 优化）**：`dockerfile.client` 改为**两阶段构建** —— 解包与裁剪只在临时阶段完成，1.14GB 离线 tar 包不再进入最终镜像；同时裁掉运行时绝不读取的 Hadoop 离线文档（485MB）、Flume / Kafka 文档与 88 个 `*-sources.jar` / `*-tests.jar`。实测 `7.15GB → 4.23GB`（约省 41%）。Hadoop / Spark 自带的 `examples`（wordcount、SparkPi 等教学示例）、Flink `opt/` 可选 connector、Hive `jdbc/`、Hadoop `tools/`、apt 编译工具**全部保留**。
> 关键：`COPY` 与「解压后 `rm`」若拆成两条 Dockerfile 指令，压缩包层会被永久钉在镜像里（`rm` 只写 whiteout 标记，不减小镜像），务必保持在同一个临时构建阶段内完成。

| 类别 | 预装内容 |
|---|---|
| Spark / PySpark | Spark 3.1.1 的 `spark-submit` / `pyspark` / py4j；`pyspark` 由镜像自带，**不 pip 安装**，避免与集群版本不一致 |
| Hadoop / MapReduce | Hadoop 3.1.3 客户端：`hdfs` / `yarn` / `hadoop jar` / `mapred` 及 `share/hadoop` 全部 jar |
| Hive | Hive 3.1.2 的 `beeline` / `hive` CLI、Hive JDBC jar、MySQL Connector/J；Python 侧 `PyHive` + `thrift` + `thrift-sasl` + `pure-sasl` |
| Kafka | Kafka 2.4.1 控制台脚本与 `kafka-clients` jar；Python 侧 `kafka-python==2.0.2` |
| Flink | Flink 1.14.0 客户端（`flink run`）与 `lib/*.jar`，用于 Java/Scala 作业编译与提交 |
| Flume | Flume 1.9.0 的 `flume-ng-sdk` jar + Python `avro-python3`，供 Avro/Thrift source 改造使用 |
| 其它 | Maven 3.6.3、JDK 8、`BIGDATA_JARS`（离线 `javac -cp`）、`pandas` / `numpy` / `hdfs` / `requests`、vim / nano / git |

**使用步骤**

1. 管理员在 `/bigdata` 构建 `client` 镜像（或 `bash bigdata-cli.sh build client`）；学生无需构建，直接在 `/portal` 点「代码开发 → 启动」。
2. 启动要操作的组件（用 HDFS 先起 Hadoop、用 Kafka 先起 Kafka）。开发容器**不会自动拉起依赖**——它与所有组件都是可选关系。
3. 在该容器卡片上点 **▣ 全交互** 进入终端（或用 `>_ 终端` 跑单条命令），代码写在 `/workspace`。
4. 自检：`cd /workspace && python3 python/check_libs.py`。

**配置自动适配**：`scripts/client-entrypoint.sh` 按 `config/environment.conf` 的 `HADOOP_ENVIRONMENT` 把 `standard` / `ha` 的 Hadoop 配置、Spark 模板（替换 `{{HDFS_NAMESERVICE}}`）、`hive-site.xml` 渲染到各客户端的实际配置目录，并把环境变量写入 `/etc/profile.d/bigdata-client.sh`。因此务必用**登录 shell**（`bash -l`；网页全交互终端已经是登录 shell）。

**代码持久化**：主平台 `./workspace`，学生环境 `stacks/<用户名>/workspace`。`client-entrypoint.sh` 每次启动按文件粒度从 `/opt/client-examples/` 增量投放示例（`cp -n` 不覆盖学生已有代码），因此镜像构建之后新增的示例也能补进已创建的用户栈；网页启动 client 时 `docker-relay.py` 还会从宿主 `examples/client/` 同步一次。两个运行态目录均已加入 `.gitignore`。

**限制**

- 容器**不发布任何宿主机端口**（故不占用每用户 200 个端口的配额），只能通过 `docker exec` 进入；网页终端已覆盖这一入口。
- 当前 Flume 配置是 `exec source → Kafka sink(topic=flume-logs)`，没有对外监听端口。程序要「接 Flume」就消费该 Kafka topic；若需要直接向 Flume 发送事件，须把 source 改为 `avro` / `netcat` 并发布端口，镜像里已备好 SDK 与 `avro-python3`。
- 默认关闭 `spark.eventLog.enabled` 以便 `local[*]` 单机调试；需要 History Server 时设 `CLIENT_SPARK_EVENTLOG=true` 或提交时 `--conf spark.eventLog.enabled=true`。

### 安全说明

relay 以宿主机用户权限调用 Docker，等同于把 Docker 控制权交给已登录用户，**仅在可信局域网内使用**。全交互 TTY 授予的是用户自己容器内的完整 shell；共享的 `config/` 会挂载进每个用户容器，请勿在其中放置敏感信息。账号密码使用 PBKDF2-SHA256 加盐哈希存放于 `docker-manager/users.json`（已加入 `.gitignore`，严禁提交），会话为 12 小时内存态 Cookie，服务重启后需重新登录。

## 环境要求

- Windows 10/11，WSL2 Ubuntu 20.04 或更新版本
- Docker 20.10+
- Docker Compose 2.x，并保留 `docker-compose` 兼容命令供现有 CLI 使用
- Bash、curl、常用 GNU 工具
- 建议内存 16 GB 以上，可用磁盘空间 50 GB 以上

Windows 环境安装说明见 [安装docker desktop.md](安装docker%20desktop.md)。在 WSL 中建议显式使用 `bash` 执行 `.sh` 文件：

```bash
bash bigdata-cli.sh --help
bash scripts/network.sh
bash test/test-hadoop.sh
```

## 快速开始

平台提供两个管理入口，可以并用：

| 入口 | 适用场景 | 启动方式 |
|---|---|---|
| 统一 CLI（英文 / 中文） | 管理员构建镜像、批量启停、日志与组件测试 | `bigdata-cli.bat` / `bigdata-cli.sh`，或汉化版 `bigdata-cli-zh.bat` / `bigdata-cli-zh.sh` |
| 网页多用户平台 | 学生按账号登录，各开一套隔离容器，网页内直接操作终端 | 本机 `docker-manager\start.bat`；局域网 `docker-manager\start-lan.bat`，详见[多用户实验平台（网页版）](#多用户实验平台网页版) |

学生实验推荐网页平台；**组件镜像仍需管理员先用 CLI 或 `/bigdata` 页面构建一次**，普通用户只有启停自己容器的权限。CLI 完整用法见 [CLI_USAGE.md](CLI_USAGE.md)。

### 1. 创建公共网络

除五节点 Compose 自带网络外，独立组件 Compose 使用公共外部网络 `bigdata-net`。通过 `bigdata-cli.sh` 或 `bigdata-cli.bat` 构建、启动独立组件时，CLI 会自动检查并创建该网络。

只有绕过 CLI、直接使用 Compose 时，才需要先手工创建：

```bash
bash scripts/network.sh
```

### 2. 构建基础镜像

所有 Apache 组件镜像都依赖 `bigdata-base:latest`：

```powershell
# 使用项目 CLI（Windows）
.\bigdata-cli.bat build-base

# 或直接使用 Docker
docker build -f dockerfile.base -t bigdata-base:latest .
```

如需手工构建全部独立组件镜像，可按依赖顺序执行：

```bash
docker build -f dockerfile.hadoop -t bigdata-hadoop:latest .
docker build -f dockerfile.zookeeper -t bigdata-zookeeper:latest .
docker build -f dockerfile.mysql -t bigdata-mysql:latest .
docker build -f dockerfile.hbase -t bigdata-hbase:latest .
docker build -f dockerfile.hive -t bigdata-hive:latest .
docker build -f dockerfile.kafka -t bigdata-kafka:latest .
docker build -f dockerfile.spark -t bigdata-spark:latest .
docker build -f dockerfile.flink -t bigdata-flink:latest .
docker build -f dockerfile.flume -t bigdata-flume:latest .
docker build -f dockerfile.client -t bigdata-client:latest .   # 父镜像是 bigdata-spark:latest，须最后构建
```

`scripts/update-dockerfile-versions.sh` 用于读取 `config/environment.conf`、检查安装包并同步 Dockerfile 版本。该脚本可能访问网络和修改 Dockerfile，运行前建议先提交或暂存本地改动：

```bash
bash scripts/update-dockerfile-versions.sh
git diff -- dockerfile.*
```

### 3. 启动独立组件

CLI 支持交互菜单和命令模式。镜像管理菜单提供 `Build Base Image`，命令行也支持 `build-base`。构建直接继承 `bigdata-base:latest` 的组件时，CLI 会先检查基础镜像；若不存在则终止组件构建并显示构建基础镜像的命令。CLI 不会静默自动构建基础镜像，也不会自动启动上游依赖。

```bash
# 查看组件
bash bigdata-cli.sh list

# 构建并启动 ZooKeeper
bash bigdata-cli.sh build zookeeper
bash bigdata-cli.sh start zookeeper

# 构建并启动 Hadoop 标准集群
bash bigdata-cli.sh build hadoop
bash bigdata-cli.sh start hadoop

# 查看状态并运行测试
bash bigdata-cli.sh status hadoop
bash bigdata-cli.sh test hadoop
```

推荐依赖顺序：

```text
ZooKeeper → Hadoop 或 Hadoop HA → MySQL
           ├→ HBase
           ├→ Hive
           ├→ Spark
           └→ Flink
ZooKeeper → Kafka → Flume
```

HBase、Hive 基于 `bigdata-hadoop:latest` 构建，构建它们之前需先构建 Hadoop 镜像。Spark 默认读取 `config/environment.conf` 中的 `HADOOP_ENVIRONMENT`；宿主机显式设置同名变量时才临时覆盖共享配置。

`client` 是纯开发节点：不发布宿主机端口、不启动服务进程，也没有专用 `test/test-client.sh`。启动后用 `docker exec -it client bash -l` 进入，`cd /workspace && python3 python/check_libs.py` 自检；示例源码位于 `examples/client/`（详见[代码开发容器](#代码开发容器client)）。网页平台中对应「代码开发」卡片，学生点「▣ 全交互」即可进入。

CLI 完整用法见 [CLI_USAGE.md](CLI_USAGE.md)。也可以直接使用 Compose：

```bash
docker-compose -f docker-compose.zookeeper.yml up -d
docker-compose -f docker-compose.hadoop.yml up -d
docker-compose -f docker-compose.mysql.yml up -d
```

### 4. 启动五节点全栈集群

```bash
docker build -f dockerfile.all-in-one -t bigdata-all-in-one:latest .
docker-compose -f docker-compose.5-node-cluster.yml up -d
```

也可以使用 CLI：

```bash
bash bigdata-cli.sh --architecture multi build all
bash bigdata-cli.sh --architecture multi start all
bash bigdata-cli.sh --architecture multi status all
bash bigdata-cli.sh --architecture multi test all
```

五节点启动脚本会完成以下工作：

1. 按主机名选择 master、worker 或 infra 配置。
2. 初始化 HDFS、MySQL 和 Hive Metastore Schema。
3. 检查 DataNode Cluster ID、Kafka Cluster ID 和 HBase 残留状态。
4. 使用 Supervisor 按依赖顺序启动服务。
5. 启动健康监控，异常时有限次数重启对应服务。

## 服务端口

### 独立组件架构

| 服务 | 主机访问地址/端口 |
|---|---|
| Hadoop NameNode | http://localhost:19870 |
| Hadoop YARN | http://localhost:18088 |
| Hadoop JobHistory | http://localhost:19888 |
| Hadoop HA NameNode 1/2 | http://localhost:19870 / http://localhost:29870 |
| Hadoop HA YARN 1/2 | http://localhost:18088 / http://localhost:28088 |
| ZooKeeper 1/2/3 | `localhost:12181/12182/12183`（容器内仍是 2181；避开 Windows 保留端口 2180-2279） |
| HBase Master | http://localhost:16210 |
| HBase RegionServer 1/2 | http://localhost:16030 / http://localhost:16031 |
| HBase REST / Thrift | `localhost:18280` / `localhost:19090` |
| Hive Metastore | `localhost:19083` |
| HiveServer2 JDBC / Web UI | `localhost:11000` / http://localhost:11002 |
| Kafka 1/2/3 | `localhost:19092/19093/19094` |
| Spark Master / History | http://localhost:8080 / http://localhost:18082 |
| Spark Worker 1/2 | http://localhost:8081 / http://localhost:8082 |
| Flink Dashboard | http://localhost:18081 |
| MySQL | `localhost:3307` |

### 五节点架构

| 服务 | 主机访问地址/端口 |
|---|---|
| HDFS NameNode | http://localhost:29870 |
| YARN ResourceManager | http://localhost:28088 |
| YARN JobHistory | http://localhost:29888 |
| HBase Master | http://localhost:26010 |
| HiveServer2 JDBC / Web UI | `localhost:21001` / http://localhost:21002 |
| Spark Master / RPC | http://localhost:28080 / `localhost:27077` |
| Flink Dashboard | http://localhost:28081 |
| MySQL | `localhost:3307` |

容器内部应优先通过服务名和容器端口通信，不应使用上述主机映射端口。

## 教学实验操作手册

下面恢复并修正各组件的常用操作示例。独立组件示例使用当前 Compose 中的实际容器名；五节点示例使用 `master`、`worker-1` 和 `infra`。

### 独立组件服务管理

```bash
# 查看所有容器
docker ps

# 查看某个组件状态和日志
docker-compose -f docker-compose.hadoop.yml ps
docker-compose -f docker-compose.hadoop.yml logs -f

# 停止、重启或移除组件容器
docker-compose -f docker-compose.hadoop.yml stop
docker-compose -f docker-compose.hadoop.yml restart
docker-compose -f docker-compose.hadoop.yml down

# 同时删除数据卷会丢失持久化数据
docker-compose -f docker-compose.hadoop.yml down -v
```

### Hadoop：HDFS、YARN 与 MapReduce

```bash
# 进入标准 Hadoop NameNode 容器
docker exec -it namenode bash

# HDFS 文件操作
hdfs dfs -ls /
hdfs dfs -mkdir -p /user/test/input
echo "hello hadoop" > /tmp/input.txt
hdfs dfs -put -f /tmp/input.txt /user/test/input/
hdfs dfs -cat /user/test/input/input.txt
hdfs dfs -du -h /user/test
hdfs dfs -cp /user/test/input/input.txt /user/test/input/input-copy.txt
hdfs dfs -chmod 755 /user/test

# HDFS 管理
hdfs dfsadmin -report
hdfs dfsadmin -safemode get

# YARN 管理
yarn node -list
yarn application -list
yarn application -kill <application_id>

# YARN Pi 示例
yarn jar /opt/hadoop/share/hadoop/mapreduce/hadoop-mapreduce-examples-3.1.3.jar pi 10 100

# MapReduce WordCount
hadoop jar /opt/hadoop/share/hadoop/mapreduce/hadoop-mapreduce-examples-3.1.3.jar \
  wordcount /user/test/input /user/test/wordcount-output
hdfs dfs -cat /user/test/wordcount-output/part-r-00000

# 清理实验数据
hdfs dfs -rm -r -f /user/test
```

Hadoop HA 模式使用逻辑地址 `hdfs://mycluster`。可以在任意 NameNode 查询主备状态：

```bash
docker exec namenode1 hdfs haadmin -getAllServiceState
docker exec namenode1 hdfs haadmin -getServiceState nn1
docker exec namenode2 hdfs haadmin -getServiceState nn2
```

教学环境可使用以下命令演示手动切换，切换前应确认两个 NameNode 和三个 JournalNode 均正常：

```bash
docker exec namenode1 hdfs haadmin -failover nn1 nn2
```

### HBase：表与数据操作

```bash
docker exec -it hbase-master hbase shell

# 在 HBase Shell 中执行
status
version
create 'test_table', 'cf1', 'cf2'
list
describe 'test_table'

put 'test_table', 'row1', 'cf1:name', 'Alice'
put 'test_table', 'row1', 'cf2:age', '25'
put 'test_table', 'row2', 'cf1:name', 'Bob'
get 'test_table', 'row1'
scan 'test_table'
count 'test_table'

delete 'test_table', 'row1', 'cf2:age'
disable 'test_table'
drop 'test_table'
```

HBase 依赖 HDFS 和 ZooKeeper。排障时应同时检查三层状态，而不能只观察 HMaster 进程。

### Hive：数据库、分区表与外部表

```bash
# 从 Hive CLI 容器连接 HiveServer2
docker exec -it hive-cli beeline -u jdbc:hive2://hive-server2:10000
```

进入 Beeline 后可以执行：

```sql
CREATE DATABASE IF NOT EXISTS test_db;
SHOW DATABASES;
USE test_db;

CREATE TABLE test_table (
  id INT,
  name STRING,
  age INT
)
PARTITIONED BY (dt STRING);

INSERT INTO test_table PARTITION (dt='2026-08-19')
VALUES (1, 'Alice', 25), (2, 'Bob', 30);

SELECT * FROM test_table;
SELECT name, age FROM test_table WHERE age > 25;
SHOW PARTITIONS test_table;

ALTER TABLE test_table ADD IF NOT EXISTS PARTITION (dt='2026-08-20');

CREATE EXTERNAL TABLE external_table (
  id INT,
  name STRING
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
LOCATION '/user/hive/external_table';

CREATE VIEW test_view AS
SELECT name, age FROM test_table WHERE age > 25;

DROP VIEW test_view;
DROP TABLE external_table;
DROP TABLE test_table;
DROP DATABASE test_db;
```

### ZooKeeper：节点与集群状态

```bash
docker exec -it zoo1 /opt/zookeeper/bin/zkCli.sh -server localhost:2181

# 在 ZooKeeper CLI 中执行
ls /
create /test-node "test-data"
get /test-node
set /test-node "updated-data"
stat /test-node
delete /test-node
quit
```

在宿主机检查三个节点的角色和四字命令响应：

```bash
echo ruok | nc localhost 12181
echo stat | nc localhost 12181
echo stat | nc localhost 12182
echo stat | nc localhost 12183
```
> 注：以上为**宿主机**侧端口（12181/12182/12183）。容器内部仍是标准 2181，
> 因此在容器内执行 `zkServer.sh status`、或 Kafka 配置里的 `zoo1:2181` 均无需改动。

### Kafka：Topic、生产者和消费者

```bash
docker exec -it kafka1 bash

# 创建并查看 Topic
kafka-topics.sh --create \
  --topic test-topic \
  --partitions 3 \
  --replication-factor 3 \
  --bootstrap-server kafka1:9092
kafka-topics.sh --list --bootstrap-server kafka1:9092
kafka-topics.sh --describe --topic test-topic --bootstrap-server kafka1:9092

# 生产消息；输入完成后按 Ctrl+D
kafka-console-producer.sh \
  --topic test-topic \
  --bootstrap-server kafka1:9092

# 从头消费消息
kafka-console-consumer.sh \
  --topic test-topic \
  --from-beginning \
  --bootstrap-server kafka1:9092

# 使用消费者组
kafka-console-consumer.sh \
  --topic test-topic \
  --group test-group \
  --bootstrap-server kafka1:9092
kafka-consumer-groups.sh --list --bootstrap-server kafka1:9092
kafka-consumer-groups.sh --describe --group test-group --bootstrap-server kafka1:9092

# 清理 Topic
kafka-topics.sh --delete --topic test-topic --bootstrap-server kafka1:9092
```

#### 在 client 开发容器里用 Python 生产 / 消费

启动 Kafka 后，可在 `client` 容器用两个独立程序完成生产者、消费者任务（详见
`examples/client/README.md` 第 3.1 节）：

```bash
docker exec -it client bash -l
cd /workspace
python3 python/kafka_producer.py --topic client-demo --count 5   # 生产者
python3 python/kafka_consumer.py --topic client-demo --max 5     # 消费者（从头读）
```

程序连容器内部服务名 `kafka1/2/3:9092`，无需宿主机端口映射。

#### 运维说明：Windows 保留端口与 ClusterId 自愈

- **ZooKeeper 宿主机端口为 `12181/12182/12183`**（容器内仍是标准 2181）。Windows 会把
  `2180–2279` 划为保留排除区间，若映射到 `2181/2182/2183`，Docker 绑定时报
  `ports are not available ... bind: forbidden by its access permissions` / HTTP 500。
  Kafka 通过内部服务名 `zoo1:2181` 连接，不受此改动影响。
- **Kafka clusterId 自愈**：`scripts/kafka-entrypoint.sh` 在启动前比对本地
  `meta.properties` 与 ZooKeeper 的 `/cluster/id`。当两者不一致、或 ZK 是全新集群
  （尚无数个节点注册、读不到 `/cluster/id`）时，会删除本地残留的 `meta.properties`
  让 broker 全新注册，避免 `InconsistentClusterIdException` 导致首次启动退出。
  因此删除/重建 ZK 卷后无需手工清理 Kafka 数据目录。

### Spark：Scala、PySpark、Standalone、YARN与Spark SQL

PySpark 的完整课堂操作流程见 [PySpark教学操作手册.md](PySpark教学操作手册.md)，其中包含镜像构建、独立组件与五节点集群启动、RDD/DataFrame/SQL 实验、Standalone/YARN 提交、自动化测试和故障判定。

```bash
docker exec -it spark-master bash

# 交互式 Shell
spark-shell --master spark://spark-master:7077

# 自动定位示例 JAR
SPARK_EXAMPLE_JAR=$(ls /opt/spark/examples/jars/spark-examples_*.jar | head -1)

# Standalone 模式
spark-submit \
  --class org.apache.spark.examples.SparkPi \
  --master spark://spark-master:7077 \
  "$SPARK_EXAMPLE_JAR" 100

# YARN 模式
spark-submit \
  --class org.apache.spark.examples.SparkPi \
  --master yarn \
  --deploy-mode client \
  "$SPARK_EXAMPLE_JAR" 100
```

Spark 根据 `config/environment.conf` 中的 `HADOOP_ENVIRONMENT` 选择标准或 HA Hadoop 配置。修改后必须重新创建 Spark 容器；仅停止后启动旧容器不会更新容器环境与启动阶段生成的配置。需要临时覆盖时，可以在宿主机显式设置同名环境变量。

三个独立Spark容器均运行SSH服务，并使用基础镜像提供的root免密密钥。可以在Master中演示Spark原生的集群批量管理流程：

```bash
docker exec -it spark-master bash

# 验证Master能够免密登录两个Worker
ssh -o BatchMode=yes spark-worker1 hostname
ssh -o BatchMode=yes spark-worker2 hostname

# workers中的每个主机都会通过SSH执行Worker停止脚本，然后停止本机Master
cd /opt/spark
./sbin/stop-all.sh --wait

# 启动本机Master，再通过SSH启动workers中的两个Worker
./sbin/start-all.sh
```

当`stop-all.sh`执行完成时，三个Spark守护进程应停止，但容器本身仍保持运行；执行`start-all.sh`后，Master页面应重新显示两个ALIVE Worker。SSH只在Docker内部`bigdata-net`网络使用，Compose没有把22端口映射到宿主机。若要直接管理容器生命周期，仍使用`docker compose -f docker-compose.spark.yml stop/start`。

Spark SQL 可以在 `spark-shell` 中演示：

```scala
val data = Seq((1, "Alice", 25), (2, "Bob", 30)).toDF("id", "name", "age")
data.createOrReplaceTempView("people")
spark.sql("SELECT name, age FROM people WHERE age >= 30").show()
```

Spark容器同时提供Python 3和Spark自带的PySpark。进入独立Spark Master后可以启动PySpark Shell，或者直接提交Python文件：

```bash
docker exec -it spark-master bash

# 交互式PySpark Shell
pyspark --master spark://spark-master:7077

# 提交项目自带的PySpark冒烟作业
exit
docker cp test/pyspark-smoke.py spark-master:/tmp/pyspark-smoke.py
docker exec spark-master spark-submit \
  --master spark://spark-master:7077 \
  /tmp/pyspark-smoke.py
```

作业输出`PYSPARK_SMOKE_OK square_sum=55 adult_count=2`表示Python Driver、Worker端Python进程、RDD和DataFrame计算均正常。完整自动测试使用`bash test/test-spark.sh`。

独立Spark镜像和五节点全栈镜像都已内置`/opt/spark/jars/mysql-connector-java-5.1.49.jar`，不需要再向运行中的容器执行`docker cp`。该版本的驱动类是`com.mysql.jdbc.Driver`；修改镜像后必须重新构建并重建容器，已经启动的PySpark JVM不会动态重新扫描JAR目录。

```python
df = spark.read.format("jdbc") \
    .option("driver", "com.mysql.jdbc.Driver") \
    .option("url", "jdbc:mysql://mysql:3306/spark?useSSL=false") \
    .option("dbtable", "person") \
    .option("user", "root") \
    .option("password", "root") \
    .load()
```

五节点架构中的MySQL主机名为`infra`。综合测试会使用`hive/hive`账号在`hive_metastore`中创建临时表，提交真实PySpark JDBC读取，再清理测试数据。五节点Spark进程由Supervisor管理，不使用独立Spark容器的SSH`start-all.sh/stop-all.sh`流程。

### Flink：作业提交与管理

```bash
docker exec -it flink-jobmanager bash

# 提交内置 WordCount 示例
flink run /opt/flink/examples/streaming/WordCount.jar

# 查看、取消作业
flink list
flink cancel <job_id>

# 需要访问 HDFS 时，标准 Hadoop 使用 hdfs://namenode:8020
export HADOOP_CONF_DIR=/opt/flink/conf
```

Flink 1.14 的示例 JAR 名称和参数可能因发行包不同而变化，应先执行 `ls /opt/flink/examples/streaming/` 确认。

### Flume：日志采集到 Kafka

独立模式的 `config/flume/flume-kafka.conf` 与 `flume-entrypoint.sh` 已统一使用 `agent1`，监控 `/var/log/application/application.log` 并写入 Kafka 的 `flume-logs` Topic。容器启动后 Agent 会自动运行；以下命令可用于课堂上的重启和链路观察：

```bash
# 先确认 Kafka Topic；不存在时再执行 create
docker exec kafka1 kafka-topics.sh \
  --list \
  --bootstrap-server kafka1:9092

# Kafka 2.4 的 --bootstrap-server 模式不与 --if-not-exists 混用
docker exec kafka1 kafka-topics.sh \
  --create \
  --topic flume-logs \
  --partitions 3 \
  --replication-factor 3 \
  --bootstrap-server kafka1:9092

# 重启容器内唯一的 Agent，并确认启动参数使用 agent1
docker restart flume-kafka
docker exec flume-kafka bash -c \
  "ps aux | grep '[o]rg.apache.flume.node.Application' | grep -- '--name agent1'"

# 追加测试日志
docker exec flume-kafka bash -c \
  'echo "flume teaching message" >> /var/log/application/application.log'

# 从 Kafka 消费验证
docker exec kafka1 kafka-console-consumer.sh \
  --topic flume-logs \
  --from-beginning \
  --max-messages 1 \
  --bootstrap-server kafka1:9092
```

### 五节点全栈启动顺序

五节点 entrypoint 不依赖 Compose 的简单启动次序，而是在各节点内按服务依赖逐项启动。

**Master 节点：**

1. NameNode
2. ResourceManager
3. 等待 DataNode 注册并退出安全模式
4. 等待 infra MySQL
5. 初始化 Hive Metastore Schema
6. Hive Metastore、HiveServer2
7. 等待 worker ZooKeeper 集群
8. HBase Master
9. Spark Master
10. Flink JobManager
11. 健康监控

**Worker 节点：**

1. ZooKeeper
2. 等待 NameNode
3. 检查 DataNode Cluster ID
4. DataNode、NodeManager
5. Kafka Broker
6. HBase RegionServer
7. Spark Worker
8. Flink TaskManager
9. 健康监控

**Infra 节点：** MySQL → Flume → 健康监控。

### 五节点综合操作

```bash
# 进入 Master
docker exec -it master bash

# HDFS
hdfs dfs -mkdir -p /user/test
hdfs dfs -put -f /opt/hadoop/LICENSE.txt /user/test/
hdfs dfs -ls /user/test

# HBase
echo "status" | hbase shell -n

# Hive
beeline -u jdbc:hive2://localhost:10000

# Spark Standalone
SPARK_EXAMPLE_JAR=$(ls /opt/spark/examples/jars/spark-examples_*.jar | head -1)
spark-submit --class org.apache.spark.examples.SparkPi \
  --master spark://master:7077 "$SPARK_EXAMPLE_JAR" 100

# Spark on YARN
spark-submit --class org.apache.spark.examples.SparkPi \
  --master yarn --deploy-mode client "$SPARK_EXAMPLE_JAR" 100

# Flink
flink list
```

```bash
# 在 Worker 上管理 Kafka
docker exec -it worker-1 bash
kafka-topics.sh --list --bootstrap-server worker-1:9092
```

## 配置结构与生效路径

```text
config/
├── environment.conf              # 独立组件版本与环境选择
├── hadoop/                       # Hadoop 标准模式
├── hadoop-ha/                    # Hadoop HA 模式
├── hbase/ hive/ kafka/ ...       # 独立组件配置
├── supervisor/supervisord.conf   # 五节点 Supervisor 主配置
└── all-in-one/
    ├── hadoop-master/            # 五节点 master Hadoop 配置
    ├── hadoop-worker/            # 五节点 worker Hadoop 配置
    ├── hbase-master/worker/      # 五节点 HBase 角色配置
    ├── spark-master/worker/      # 五节点 Spark 角色配置
    ├── flink-master/worker/      # 五节点 Flink 角色配置
    ├── hive/ kafka/ zookeeper/   # 五节点共享组件配置
    ├── mysql/ flume/
    └── supervisor/               # 各角色 Supervisor program 配置
```

独立组件由各自 entrypoint 将 `config/<component>/` 复制或挂载到组件目录。五节点模式由 `scripts/all-in-one-entrypoint.sh` 根据角色从 `config/all-in-one/` 复制配置。

### 配置设计与维护约定

当前运行配置以正确性和教学可读性为先。Compose 负责五节点资源预算，entrypoint 提供缺省值，组件配置文件保留关键字段的用途、原理和角色说明。

| 主题 | 约定 |
|---|---|
| 内存预算 | Compose 是权威入口，entrypoint 仅提供缺省值；不保留未被加载的 `memory-optimization.conf` |
| Hadoop | 五节点使用 9866/9864、`dfs.permissions.enabled`，并提供 `mapred-site.xml`；变更后运行 MapReduce 与 Spark on YARN 测试 |
| 计算引擎内存 | Flink 使用统一进程内存；Spark 区分守护进程、Worker、Driver 和 Executor |
| JVM 内存 | Hadoop、HBase、Kafka、Hive 的堆内存通过环境变量统一传入 |
| 教学可读性 | 保留 Hadoop HA 的 QJM/ZKFC、Kafka Broker ID、Flume Source-Channel-Sink 等体现核心概念的配置 |

配置或编排变更后，建议按以下顺序验收：

1. 所有 `docker-compose*.yml` 执行 `docker compose config --quiet` 通过。
2. XML / YAML / Properties 语法与配置引用路径正确。
3. 对应组件测试通过；涉及五节点时再运行 `test/cluster-test.sh`。
4. README 与 CLI_USAGE.md 中的容器名、端口和命令同步更新。
5. 在干净数据卷上复现一次启动，不依赖残留运行数据。

## 配置可视化工具

`config-visualizer/` 提供 PyQt5 图形化编辑器，支持 XML、Properties、Shell、INI、YAML、Spark Conf、列表文件和纯文本。

```bash
cd config-visualizer
python main.py
```

主要流程：

1. 从 `config/` 读取组件配置。
2. 在表格或纯文本模式编辑。
3. 保存到 `config-visualizer/output/` 工作区。
4. 人工确认后同步回 `config/`。

工具支持配置项说明、预设值、核心项标记以及新增组件和文件。同步操作会修改运行配置，建议同步前查看 Git diff。

### 界面与文件管理

- 左侧组件列表用于切换 Hadoop、HBase、Hive、Kafka、Spark、Flink 等配置集合。
- 文件列表显示当前组件的配置文件，并支持新增、删除文件。
- 右侧表格模式用于结构化编辑键、值和说明。
- 纯文本模式用于列表、自由文本或无法安全结构化的配置。
- `保存` 只写入 `config-visualizer/output/`。
- `同步到 config/` 才会覆盖项目运行配置。

支持的主要文件类型：

| 文件类型 | 典型扩展名/文件 | 适用组件 |
|---|---|---|
| XML | `.xml` | Hadoop、HBase、Hive |
| Properties | `.properties` | Kafka |
| 键值配置 | `.conf`、`.cfg` | Flume |
| Spark Conf | `spark-defaults.conf` | Spark |
| Shell 环境 | `.sh` | Spark、Hadoop 环境变量 |
| INI | `.cnf`、`.ini` | MySQL |
| YAML | `.yaml`、`.yml` | Flink |
| 主机列表 | `workers`、`regionservers` | Hadoop、Spark、HBase |
| 纯文本 | `.txt`、`.md` | 说明或自定义内容 |

新增组件时，工具会在工作区创建组件目录；新增文件时会按类型生成基础模板。配置项说明和核心项标记来自 `config-visualizer/config_data.py`。

## 测试

测试脚本的依赖、实际覆盖范围、日志约定和失败定位方式见 [test/README.md](test/README.md)，各脚本另有同名 Markdown 说明。

### 独立组件测试

```bash
bash test/test-hadoop.sh
bash test/test-hadoop-ha.sh
bash test/test-zookeeper.sh
bash test/test-hbase.sh
bash test/test-hive.sh
bash test/test-kafka.sh
bash test/test-spark.sh
bash test/test-flink.sh
bash test/test-flume.sh
bash test/test-flume-kafka.sh
bash test/test-mysql.sh
```

### 五节点综合测试

```bash
bash test/cluster-test.sh
```

综合测试覆盖容器状态、HDFS/YARN/MapReduce、ZooKeeper、HBase、Hive、Kafka、Flume-Kafka、Spark Standalone/YARN、Flink 和 MySQL。测试会创建临时目录、表、Topic 和数据库，脚本结束时会尽量清理。

测试的内存检查会先输出容器内实际 Java 命令行，再校验 NameNode、DataNode、HBase、ZooKeeper、Kafka、Spark 和 Flink 的关键内存参数。Flume 测试使用本轮唯一消息；未消费到该消息时直接失败，不再以警告代替失败。

## 常用管理命令

```bash
# 查看五节点容器
docker-compose -f docker-compose.5-node-cluster.yml ps

# 查看 Supervisor 服务
docker exec master supervisorctl status
docker exec worker-1 supervisorctl status
docker exec infra supervisorctl status

# 查看日志
docker-compose -f docker-compose.5-node-cluster.yml logs -f
docker logs -f master

# 停止但保留数据卷
docker-compose -f docker-compose.5-node-cluster.yml down

# 删除数据卷，数据不可恢复，请谨慎执行
docker-compose -f docker-compose.5-node-cluster.yml down -v
```

## 常见问题

### HDFS 长时间处于安全模式

```bash
docker exec master hdfs dfsadmin -safemode get
docker exec master hdfs dfsadmin -report
docker exec master hdfs dfsadmin -safemode leave
```

先确认 DataNode 已注册，再手动退出安全模式。

### HBase Master 无法完成初始化

检查 HDFS、ZooKeeper、RegionServer 和 Master 日志：

```bash
docker exec master supervisorctl status
docker exec master hdfs dfs -ls /hbase
docker exec worker-1 /opt/zookeeper/bin/zkCli.sh -server localhost:2181
```

五节点 entrypoint 包含残留数据修复逻辑。手工删除 `/hbase` 会丢失数据，不应作为首选操作。

进一步检查：

```bash
# Master 与 RegionServer 进程
docker exec master jps
docker exec worker-1 jps

# HBase 日志
docker exec master tail -n 100 /opt/hbase/logs/hbase-master-error.log
docker exec worker-1 tail -n 100 /opt/hbase/logs/hbase-regionserver-error.log

# ZooKeeper 中的 HBase 节点
docker exec worker-1 bash -c \
  'echo "ls /hbase" | /opt/zookeeper/bin/zkCli.sh -server localhost:2181'
```

只有确认实验数据可以丢弃时，才能清理 ZooKeeper/HDFS 中的 HBase 状态并重新初始化。

### Hive 无法连接 MySQL 或 Metastore

```bash
docker exec infra mysqladmin ping
docker exec infra mysql -uroot -proot -e 'SHOW DATABASES;'
docker exec master bash -c 'echo > /dev/tcp/infra/3306'
docker exec master bash -c 'echo > /dev/tcp/localhost/9083'
docker exec master supervisorctl status hive-metastore hive-server2
```

重点核对 `hive-site.xml` 中的数据库名、用户名、密码、JDBC URL 和 Metastore URI 是否与当前架构一致。独立模式使用 `mysql`、`hive-metastore`，五节点模式使用 `infra`、`master`。

### Kafka Broker 无法启动

```bash
docker exec worker-1 supervisorctl status kafka-broker
docker exec worker-1 tail -n 100 /opt/kafka/logs/kafka-error.log
docker exec worker-1 bash -c 'echo > /dev/tcp/worker-2/2181'
docker exec worker-1 grep -E 'broker.id|advertised.listeners|zookeeper.connect' \
  /opt/kafka/config/server.properties
```

常见原因包括 Broker ID 重复、`advertised.listeners` 使用错误主机名、ZooKeeper 不可达，以及数据卷中的 Cluster ID 与 ZooKeeper 不一致。

### 端口冲突

宿主机端口被占用时，优先只修改 Compose 左侧的主机端口，不要随意修改容器内部服务端口：

```bash
# Windows
netstat -ano | findstr :19870

# WSL/Linux
ss -lntp | grep ':19870'
```

例如 `19870:9870` 中，`19870` 可以改为其他空闲主机端口，而容器内部 `9870` 应与 Hadoop 配置保持一致。

### Windows 脚本换行或路径异常

- 在 WSL 终端中执行命令，路径使用 `/`。
- 推荐 `bash script.sh`，避免 Windows Shell 直接解释 Bash 语法。
- 仓库通过 `.gitattributes` 将 Shell 和配置文件固定为 LF。
- 出现 `bash: $'\r': command not found` 时运行 `dos2unix <script>`。
- 出现 `Permission denied` 时使用 `bash <script>`，或执行 `chmod +x <script>`。
- 从 Windows 路径切换到 WSL 路径时，可使用 `wslpath` 转换。

环境自检：

```bash
wsl --version
docker --version
docker compose version
docker-compose --version
docker info
bash bigdata-cli.sh --help
```

### 内存不足

- 增加 Docker Desktop/WSL2 内存。
- 不要同时启动独立组件架构和五节点架构。
- 按离线数仓、实时链路、Spark/Flink 计算等场景分批启动。
- 修改内存参数后运行对应组件测试。

### 监控与维护

五节点模式可同时从 Supervisor、进程、端口和 Web UI 四个层次观察服务：

```bash
# Supervisor 状态
docker exec master supervisorctl status
docker exec worker-1 supervisorctl status
docker exec infra supervisorctl status

# Java 进程
docker exec master jps
docker exec worker-1 jps

# 健康监控生成的业务日志
docker exec master tail -f /var/log/health-monitor.log

# Supervisor 捕获的健康监控输出
docker exec master tail -f /var/log/health-monitor-stdout.log
```

主要 Web UI：

- HDFS：http://localhost:29870
- YARN：http://localhost:28088
- HBase：http://localhost:26010
- Spark：http://localhost:28080
- Flink：http://localhost:28081

性能观察建议结合 HDFS 副本状态、YARN 容器资源、HBase Region 分布、Kafka Topic 分区、Spark Stage 和 Flink Checkpoint，而不是只观察容器是否运行。

## 项目结构

```text
.
├── config/                       # 独立组件、HA 与五节点配置
├── config-visualizer/            # PyQt5 配置编辑器
├── data/                         # 本地日志和运行数据，Git 默认忽略
├── docker-manager/               # 网页管理端：relay、页面与启动脚本
│   ├── docker-relay.py           # 纯标准库 HTTP / WebSocket 服务，含账号与用户隔离
│   ├── start.bat / start.sh       # 本机 127.0.0.1:8000
│   └── start-lan.bat / start-lan.sh  # 局域网 0.0.0.0:8000（学生访问）
├── examples/
│   ├── client/                  # client 容器示例（进镜像，增量投放到 /workspace）
│   └── course/                   # 宿主机 PySpark 讲义与演示脚本
├── module/                       # 离线安装包，Git 默认忽略
├── scripts/                      # entrypoint、初始化、网络与版本脚本
├── stacks/                       # 学生专属 compose / 数据 / 代码，Git 默认忽略
├── test/                         # 组件测试与全栈测试
├── workspace/                    # 主平台 client 挂载代码，Git 默认忽略
├── dockerfile.base / dockerfile.<component> / dockerfile.client
├── dockerfile.all-in-one         # 五节点统一镜像
├── docker-compose.<component>.yml / docker-compose.client.yml
├── docker-compose.5-node-cluster.yml
├── bigdata-cli.sh / .bat         # 英文 CLI（Linux/WSL 与 Windows）
├── bigdata-cli-zh.sh / .bat      # 中文 CLI（.bat 为 GBK + CRLF）
├── README.md / CLI_USAGE.md
├── PySpark教学操作手册.md
└── 安装docker desktop.md
```

各目录职责：

| 目录/文件 | 主要作用 |
|---|---|
| `config/` | 独立组件、HA、五节点角色和 Supervisor 配置 |
| `docker-manager/` | 网页管理端；`users.json` 存放账号哈希，严禁提交 |
| `examples/` | 教学示例；`client/` 进镜像，`course/` 供宿主机课堂演示 |
| `scripts/` | 容器 entrypoint、初始化、网络与版本同步 |
| `test/` | 独立组件、HA、集成链路和五节点测试 |
| `module/` | 离线安装包与 JDBC/Guava 兼容依赖 |
| `data/` | 本地挂载日志和运行数据，不应提交到 Git |
| `stacks/` / `workspace/` | 学生专属环境生成物与主平台挂载代码，均为运行态目录 |
| `dockerfile.*` | 基础镜像、独立组件镜像、client 与统一全栈镜像 |
| `docker-compose.*.yml` | 服务、网络、端口和数据卷编排 |
| `bigdata-cli*.sh/.bat` | 镜像、容器、日志、状态和测试的命令行入口（中 / 英文） |

## 安全与生产边界

当前默认配置使用 root/hive 等教学账号、明文密码、PLAINTEXT Kafka、无 Kerberos、无 TLS，并关闭了部分权限检查。它们降低了实验门槛，但不符合生产安全要求。

如果要扩展到生产模拟，需要至少补充：密钥和密码外置、Kerberos/ACL、TLS、细粒度网络访问、镜像漏洞扫描、指标监控、备份恢复、资源限额以及真实 HA 验证。
