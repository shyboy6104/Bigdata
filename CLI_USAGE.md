# BigData CLI 使用手册

`bigdata-cli.bat` 是本项目在 Windows 下的统一管理入口。它优先在已接入 Docker Desktop 的 WSL 中调用 `bigdata-cli.sh`；如果 WSL 内无法使用 Docker、但系统已安装 Git for Windows，则自动改用 Git Bash。Shell 脚本负责完成镜像构建、容器启停、状态查看、日志查看和测试执行。

本文以 Windows 10/11、Docker Desktop、WSL2 和 PowerShell 为主要环境。示例中的项目目录为 `E:\Programs\Bigdata`，如果项目位于其他位置，请替换为实际路径。

## 1. Windows 下的调用关系

在 PowerShell 中执行：

```powershell
.\bigdata-cli.bat status hadoop
```

实际调用过程是：

```text
PowerShell 或 CMD
    -> bigdata-cli.bat
        -> 检查 WSL、Docker Desktop 与 Docker Compose
        -> 把 Windows 脚本路径转换为 WSL 路径
        -> WSL 内 Docker 可用：使用 WSL bash
        -> WSL 内 Docker 不可用：使用 Git Bash 回退
        -> 执行 bigdata-cli.sh
            -> Docker Compose 管理容器
            -> test/*.sh 执行组件测试
```

因此，`.bat` 文件是 Windows 包装器，实际管理逻辑位于 `bigdata-cli.sh`。

## 2. 使用前提

### 2.1 必需软件

Windows 主机需要：

- Windows 10 或 Windows 11。
- WSL2，并已安装一个默认 Linux 发行版，例如 Ubuntu。
- Docker Desktop，且使用 Linux 容器模式。
- 推荐为默认 WSL 发行版启用 Docker Desktop WSL Integration。
- Docker Compose V2。
- 如果未启用 WSL Integration，需要安装 Git for Windows，包装器会自动使用其中的 Git Bash。

先在 PowerShell 中检查：

```powershell
wsl --status
docker info
docker compose version
```

通过条件：

- `wsl --status` 能显示默认发行版和 WSL 版本。
- `docker info` 同时显示 Client、Server 信息，没有 daemon 连接错误。
- `docker compose version` 能显示 Compose V2 版本。

再检查 WSL 是否能访问 Docker：

```powershell
wsl bash -lc "docker version && docker compose version"
```

如果两项命令均成功，包装器使用 WSL。如果 Windows 可以运行 Docker、WSL 中却找不到 Docker，则有两种处理方式：

1. 推荐：在 Docker Desktop 的 WSL Integration 设置中启用当前发行版，然后重新打开终端。
2. 回退：安装 Git for Windows。包装器检测到 `C:\Program Files\Git\bin\bash.exe` 后会自动使用 Git Bash。

检查 Git Bash 回退是否存在：

```powershell
Test-Path 'C:\Program Files\Git\bin\bash.exe'
```

输出 `True` 表示可以使用回退方式。

### 2.2 检查项目脚本

```powershell
Set-Location E:\Programs\Bigdata
Get-Item .\bigdata-cli.bat
Get-Item .\bigdata-cli.sh
```

通过条件：两个脚本都存在。Windows 使用 `.bat` 时不需要执行 `chmod +x`，包装器会使用 `bash` 读取 Shell 脚本。

### 2.3 创建公共 Docker 网络

独立组件的 Compose 文件使用外部网络 `bigdata-net`。通过 CLI 执行独立组件的 `build` 或 `start` 时，脚本会自动检查该网络：

```text
[INFO] 检查独立组件公共网络：bigdata-net
[SUCCESS] 公共网络已存在：bigdata-net
```

如果网络不存在，CLI 自动执行等价于 `docker network create bigdata-net` 的操作。创建成功时显示：

```text
[INFO] 公共网络不存在，正在创建：bigdata-net
[SUCCESS] 公共网络创建成功：bigdata-net
```

该检查具有幂等性：网络已经存在时只读取其状态，不会删除、重建或修改网络。五节点 Compose 使用自己的内部网络，因此 `--architecture multi` 不执行此步骤。

通常不再需要手工创建网络。若要在课堂上单独验证网络，可以执行：

```powershell
docker network inspect bigdata-net
```

如果绕过 CLI、直接运行独立组件 Compose，并且检查结果显示网络不存在，则手工执行：

```powershell
docker network create bigdata-net
```

通过条件：CLI 显示网络已存在或创建成功，且 `docker network inspect bigdata-net` 能返回网络信息。网络检查或创建失败时，CLI 会取消镜像构建或容器启动，并返回退出码 1。

### 2.4 准备基础镜像与离线安装包

CLI 不会静默地自动构建父镜像，也不会下载 `module` 中的离线包。基础镜像可以通过镜像管理菜单中的 `Build Base Image` 构建，也可以直接执行：

```powershell
.\bigdata-cli.bat build-base
```

执行 `build <component>` 时，CLI 会读取组件 Dockerfile 的 `FROM`。如果组件直接依赖 `bigdata-base:latest` 而该镜像不存在，CLI 会终止本次组件构建，并明确提示先执行 `build-base`。

除 MySQL 外，大多数组件依赖 `bigdata-base:latest`。也可以使用等价的原生 Docker 命令：

```powershell
docker build -f dockerfile.base -t bigdata-base:latest .
docker image ls bigdata-base:latest
```

还应检查目标 Dockerfile 中的 `COPY module/...` 指令，确认所需压缩包或 JAR 已放入 `module` 目录。例如：

| 组件 | 主要离线文件 |
|---|---|
| Hadoop / Hadoop HA | `module/hadoop-3.1.3.tar.gz` |
| ZooKeeper | `module/apache-zookeeper-3.6.3-bin.tar.gz` |
| Kafka | `module/kafka_2.12-2.4.1.tgz` |
| Spark | `module/spark-3.1.1-bin-hadoop3.2.tgz` |
| Flink | `module/flink-1.14.0-bin-scala_2.12.tar` |
| Flume | `module/apache-flume-1.9.0-bin.tar.gz`、`module/guava-27.0-jre.jar` |
| HBase | `module/hbase-2.2.3-bin.tar.gz` |
| Hive | `module/apache-hive-3.1.2-bin.tar.gz`、MySQL JDBC 和 Guava JAR |

HBase 和 Hive 镜像基于 `bigdata-hadoop:latest`，因此必须先构建 Hadoop：

```powershell
.\bigdata-cli.bat build hadoop
.\bigdata-cli.bat build hbase
.\bigdata-cli.bat build hive
```

五节点全栈镜像所需的完整文件检查见 [PySpark教学操作手册.md](PySpark教学操作手册.md#111-构建与启动)。

## 3. Windows 快速开始

### 3.1 PowerShell

PowerShell 执行当前目录中的脚本时必须添加 `.\`：

```powershell
Set-Location E:\Programs\Bigdata
.\bigdata-cli.bat --help
.\bigdata-cli.bat list
```

### 3.2 CMD

CMD 可以直接使用脚本名：

```bat
cd /d E:\Programs\Bigdata
bigdata-cli.bat --help
bigdata-cli.bat list
```

### 3.3 从其他目录调用

包装器会自动定位项目目录，因此也可以使用完整路径：

```powershell
& 'E:\Programs\Bigdata\bigdata-cli.bat' status hadoop
```

### 3.4 判断 CLI 是否启动成功

执行：

```powershell
.\bigdata-cli.bat --help
```

WSL 中的 Docker 可用时，预期首先出现：

```text
Running BigData CLI via WSL...
BigData Platform CLI Management Tool
```

如果 WSL 内 Docker 不可用但 Git Bash 已安装，则出现：

```text
Docker is unavailable in WSL; running BigData CLI via Git Bash...
BigData Platform CLI Management Tool
```

两种情况随后都应显示命令、参数和组件列表，退出码应为 0。

## 4. 两种使用模式

### 4.1 交互式菜单

不提供参数时进入交互式菜单：

```powershell
.\bigdata-cli.bat
```

主菜单包括镜像管理、容器生命周期、状态与日志、组件测试和组件列表。交互模式适合课堂演示。通常需要依次选择操作类型、部署架构和组件；但容器生命周期菜单中的 `Clean ALL Project Containers, Networks and Volumes` 是全项目操作，确认后直接执行，不再选择架构或组件。

### 4.2 命令行模式

基本格式：

```text
bigdata-cli.bat [选项] <命令> <组件>
```

PowerShell 示例：

```powershell
.\bigdata-cli.bat start hadoop
.\bigdata-cli.bat status hadoop
.\bigdata-cli.bat test hadoop
```

命令行模式适合实验指导书、重复操作和故障复现。

## 5. 架构参数

### 5.1 独立组件架构

默认架构为 `single`，可以省略架构参数：

```powershell
.\bigdata-cli.bat start hadoop
```

等价于：

```powershell
.\bigdata-cli.bat --architecture single start hadoop
```

独立架构使用各自的 `docker-compose.<component>.yml`。

### 5.2 五节点全栈架构

五节点架构使用 `multi`，组件参数统一写成 `all`：

```powershell
.\bigdata-cli.bat --architecture multi start all
.\bigdata-cli.bat -a multi status all
```

五节点架构统一使用：

- Compose：`docker-compose.5-node-cluster.yml`
- 镜像：`bigdata-all-in-one:latest`
- Dockerfile：`dockerfile.all-in-one`

推荐把 `--architecture multi` 放在命令前，便于直接识别本次操作的架构。

## 6. 可用组件

运行：

```powershell
.\bigdata-cli.bat list
```

独立架构支持：

| 组件参数 | 用途 | 构建镜像 |
|---|---|---|
| `hadoop` | 标准 HDFS/YARN 集群 | `bigdata-hadoop:latest` |
| `hadoop-ha` | Hadoop HA 集群 | 与 `hadoop` 共用 `bigdata-hadoop:latest` |
| `zookeeper` | ZooKeeper 集群 | `bigdata-zookeeper:latest` |
| `hbase` | HBase 集群 | `bigdata-hbase:latest` |
| `hive` | Hive 服务 | `bigdata-hive:latest` |
| `kafka` | Kafka 集群 | `bigdata-kafka:latest` |
| `spark` | Scala Spark 与 PySpark | `bigdata-spark:latest` |
| `flink` | Flink 集群 | `bigdata-flink:latest` |
| `flume` | Flume 服务 | `bigdata-flume:latest` |
| `mysql` | Hive Metastore 数据库 | `bigdata-mysql:latest` |

`hadoop` 与 `hadoop-ha` 使用不同 Compose 和配置，但共用同一个 Hadoop 镜像。

## 7. 命令说明

| 命令 | 示例 | 实际行为 | 数据影响 |
|---|---|---|---|
| `build-base` | `build-base` | 使用 `dockerfile.base` 构建 `bigdata-base:latest` | 不删除容器数据 |
| `build` | `build spark` | 根据组件 Dockerfile 构建镜像 | 不删除容器数据 |
| `delete` | `delete spark` | 删除对应 Docker 镜像 | 不删除数据；被容器占用时可能失败 |
| `start` | `start spark` | 执行 Compose `up -d` | 保留已有数据 |
| `stop` | `stop spark` | 停止容器但不删除 | 保留容器与数据 |
| `destroy` | `destroy spark` | 执行 Compose `down` | 删除容器；不带 `-v` |
| `restart` | `restart spark` | 先 `stop`，再 `start` | 保留数据 |
| `clean` | `clean spark` | 对所选组件执行 `down -v` | 删除该 Compose 中声明的卷，不影响其他组件和系统级悬空卷 |
| `status` | `status spark` | 显示 Compose 容器状态 | 只读 |
| `logs` | `logs spark` | 显示组件日志 | 只读 |
| `logs ... -f` | `logs spark -f` | 持续跟踪日志，按 `Ctrl+C` 退出 | 只读 |
| `supervisor` | `-a multi supervisor all` | 检查五节点各容器的 Supervisor | 只读，仅适用于 `multi` |
| `test` | `test spark` | 执行 `test/test-spark.sh` | 会创建并清理测试数据 |
| `list` | `list` | 显示组件和架构 | 不需要组件参数 |
| `clean-volumes` | `clean-volumes` | 删除 Docker 主机上所有悬空卷 | 系统级清理，可能不可恢复 |

`clean` 和 `clean-volumes` 的命令行模式不会再次询问确认。执行前应确认卷中没有需要保留的数据。交互菜单中的 `Clean ALL Project Containers, Networks and Volumes` 与命令行的按组件 `clean` 不同：它不要求选择组件，但会先要求确认，然后清理本项目所有 Compose 部署资源和公共网络 `bigdata-net`。

## 8. 独立组件完整示例

### 8.1 标准 Hadoop

首次使用先准备网络、基础镜像和 Hadoop 压缩包，然后执行：

```powershell
.\bigdata-cli.bat build hadoop
.\bigdata-cli.bat start hadoop
.\bigdata-cli.bat status hadoop
.\bigdata-cli.bat test hadoop
```

通过条件：

- 构建输出 `Image built successfully: bigdata-hadoop:latest`。
- 启动输出 `Containers started successfully`。
- 状态中 NameNode 和 DataNode 为运行状态。
- 测试最终输出 `Component test completed successfully`，退出码为 0。

日志和停止操作：

```powershell
.\bigdata-cli.bat logs hadoop
.\bigdata-cli.bat logs hadoop -f
.\bigdata-cli.bat stop hadoop
.\bigdata-cli.bat start hadoop
.\bigdata-cli.bat destroy hadoop
```

实时日志使用 `Ctrl+C` 退出，只会结束日志跟踪，不会停止容器。

### 8.2 Hadoop HA

```powershell
.\bigdata-cli.bat build hadoop-ha
.\bigdata-cli.bat start hadoop-ha
.\bigdata-cli.bat status hadoop-ha
.\bigdata-cli.bat test hadoop-ha
```

标准 Hadoop 与 Hadoop HA 使用的容器名称和端口可能冲突，教学时应先停止当前架构，再启动另一架构。

### 8.3 Spark 与 PySpark 连接标准 Hadoop

先启动标准 Hadoop：

```powershell
.\bigdata-cli.bat start hadoop
```

Spark 默认读取 `config/environment.conf`。连接标准 Hadoop 时，先确认文件中包含：

```text
HADOOP_ENVIRONMENT=standard
```

不需要再设置 PowerShell 环境变量。构建并启动：

```powershell
.\bigdata-cli.bat build spark
.\bigdata-cli.bat start spark
.\bigdata-cli.bat status spark
.\bigdata-cli.bat test spark
```

如果 Spark 容器以前按 HA 模式创建过，修改配置文件后应重新创建，不能只执行 `restart`：

```powershell
.\bigdata-cli.bat destroy spark
.\bigdata-cli.bat start spark
```

如果 Spark 连接 Hadoop HA，则把 `config/environment.conf` 改为 `HADOOP_ENVIRONMENT=ha`，先启动 Hadoop HA，再重新创建 Spark 容器。

宿主机变量只用于不修改配置文件的临时覆盖。例如临时使用 HA：

```powershell
$env:HADOOP_ENVIRONMENT = 'ha'
.\bigdata-cli.bat start hadoop-ha
.\bigdata-cli.bat destroy spark
.\bigdata-cli.bat start spark
Remove-Item Env:HADOOP_ENVIRONMENT -ErrorAction SilentlyContinue
```

PySpark 的手工实验和通过条件见 [PySpark教学操作手册.md](PySpark教学操作手册.md)。

### 8.4 其他组件

命令形式相同，例如：

```powershell
.\bigdata-cli.bat build zookeeper
.\bigdata-cli.bat start zookeeper
.\bigdata-cli.bat status zookeeper
.\bigdata-cli.bat test zookeeper

.\bigdata-cli.bat build kafka
.\bigdata-cli.bat start kafka
.\bigdata-cli.bat logs kafka -f
```

HBase、Hive、Kafka、Spark 等组件还依赖 Hadoop、MySQL 或 ZooKeeper。应按照 [README.md](README.md) 中的依赖顺序启动，CLI 不会隐式启动上游组件。

## 9. 五节点全栈示例

### 9.1 构建

先构建基础镜像，并检查 `dockerfile.all-in-one` 要求的全部 `module` 文件：

```powershell
docker build -f dockerfile.base -t bigdata-base:latest .
.\bigdata-cli.bat --architecture multi build all
```

通过条件：输出 `Image built successfully: bigdata-all-in-one:latest`。

### 9.2 启动与状态

```powershell
.\bigdata-cli.bat --architecture multi start all
.\bigdata-cli.bat --architecture multi status all
```

通过条件：`master`、`worker-1`、`worker-2`、`worker-3`、`infra` 五个容器均为运行状态。

### 9.3 Supervisor 状态

```powershell
.\bigdata-cli.bat --architecture multi supervisor all
```

该命令依次显示五个容器中的 Supervisor 进程、可用进程配置和最后十行 Supervisor 日志。通过条件：本次课程所需服务为 `RUNNING`，没有持续处于 `BACKOFF` 或 `FATAL`。

以下命令是错误的，因为没有指定 `multi`：

```powershell
.\bigdata-cli.bat supervisor all
```

### 9.4 综合测试

```powershell
.\bigdata-cli.bat --architecture multi test all
```

CLI 会调用 `test/cluster-test.sh`。通过条件：综合测试最终成功，CLI 输出 `Full-stack cluster test completed successfully`，退出码为 0。

### 9.5 停止与移除

```powershell
.\bigdata-cli.bat --architecture multi stop all
.\bigdata-cli.bat --architecture multi start all
.\bigdata-cli.bat --architecture multi destroy all
```

## 10. 状态、日志与测试结果

### 10.1 查看状态

```powershell
.\bigdata-cli.bat status spark
```

`status` 只显示容器状态。容器为 `Up` 只能说明容器进程存在，不能证明 HDFS、Kafka、Spark 等业务功能正确。

### 10.2 查看日志

```powershell
.\bigdata-cli.bat logs spark
.\bigdata-cli.bat logs spark -f
```

- 不带 `-f`：输出当前 Compose 日志后退出。
- 带 `-f`：持续显示新日志，使用 `Ctrl+C` 返回 PowerShell。

### 10.3 运行测试

```powershell
.\bigdata-cli.bat test spark
```

独立架构下，CLI 查找 `test/test-<component>.sh`。例如：

| CLI 命令 | 测试脚本 |
|---|---|
| `test hadoop` | `test/test-hadoop.sh` |
| `test hadoop-ha` | `test/test-hadoop-ha.sh` |
| `test zookeeper` | `test/test-zookeeper.sh` |
| `test kafka` | `test/test-kafka.sh` |
| `test spark` | `test/test-spark.sh` |

测试通过应同时满足：

- 对应容器已运行。
- 测试脚本返回退出码 0。
- CLI 输出 `Component test completed successfully`。
- 组件测试日志中的关键步骤均显示成功。

各测试脚本的具体命令、预期输出和通过条件见 [test/README.md](test/README.md)。

## 11. 停止、销毁与清理的区别

### 11.1 只停止容器

```powershell
.\bigdata-cli.bat stop hadoop
```

容器仍然存在，可以再次 `start`。这是课堂暂停实验时的首选操作。

### 11.2 删除容器但保留卷

```powershell
.\bigdata-cli.bat destroy hadoop
```

该命令执行 Compose `down`，不主动添加 `-v`。如果数据使用宿主机目录挂载，目录中的文件仍然保留。

### 11.3 删除容器和卷

```powershell
.\bigdata-cli.bat clean hadoop
```

该命令会对所选组件执行 `down -v`，删除其容器以及 Compose 中声明的关联卷，不删除其他组件，也不删除 Docker 主机上的其他悬空卷。此操作可能造成该组件数据丢失，且命令行模式不会再次确认。不要把 `clean` 当作普通停止命令。

如果在交互菜单中选择：

```text
Container Lifecycle Management
  -> Clean ALL Project Containers, Networks and Volumes
```

CLI 不再显示架构和组件选择菜单，而是直接显示全项目清理警告。输入 `y` 后，将依次清理独立组件和五节点全栈 Compose 中的容器、Compose 卷及网络，最后删除独立组件公共网络 `bigdata-net`。输入其他内容则取消。

该全项目操作不会删除 Docker 镜像，也不会删除 `./data/...` 等宿主机目录映射中的文件。若 `bigdata-net` 仍被本项目以外的容器占用，CLI 不会强制断开这些容器，而会保留网络并报告具体失败环节。

### 11.4 清理所有悬空卷

```powershell
.\bigdata-cli.bat clean-volumes
```

该操作是 Docker 主机级别的清理，不限于本项目。交互菜单会询问确认，但直接执行命令行不会询问。

## 12. 常见问题

### 12.1 PowerShell 无法识别 `bigdata-cli.bat`

PowerShell 不会默认执行当前目录中的脚本，应添加 `.\`：

```powershell
.\bigdata-cli.bat --help
```

### 12.2 WSL 不存在或无法启动

```powershell
wsl --status
wsl --list --verbose
```

至少需要一个版本为 2、可以启动且设为默认的 Linux 发行版。

### 12.3 Windows 能用 Docker，但 WSL 中找不到 Docker

```powershell
wsl bash -lc "docker version"
```

如果失败，可以选择：

- 打开 Docker Desktop，在 WSL Integration 中启用实际使用的发行版。
- 安装 Git for Windows，让 `bigdata-cli.bat` 自动回退到 Git Bash。

回退生效时会显示：

```text
Docker is unavailable in WSL; running BigData CLI via Git Bash...
```

随后可以继续执行 `build`、`start`、`status` 和 `test`。包装器会设置 `MSYS_NO_PATHCONV=1`，防止 Git Bash 把 `docker exec` 中的 Linux 容器路径错误转换为 Windows 路径。

### 12.4 Docker daemon 不可用

启动 Docker Desktop，等待引擎完全就绪，再执行：

```powershell
docker info
```

### 12.5 Docker Compose 不存在

```powershell
docker compose version
wsl bash -lc "docker compose version"
```

Shell 主程序优先使用 `docker compose`，如果不可用才尝试旧命令 `docker-compose`。

### 12.6 外部网络不存在

错误通常包含 `network bigdata-net declared as external, but could not be found`。执行：

```powershell
docker network create bigdata-net
```

### 12.7 镜像构建提示 `COPY module/... not found`

```powershell
Select-String -Path dockerfile.spark -Pattern 'COPY module/'
Get-ChildItem .\module
```

文件名必须与 `COPY` 指令一致；只下载到 Windows“下载”目录而未移动到项目 `module` 目录仍会失败。

### 12.8 缺少父镜像

如果出现 `pull access denied for bigdata-base` 或 `bigdata-hadoop:latest` 不存在：

```powershell
docker build -f dockerfile.base -t bigdata-base:latest .
.\bigdata-cli.bat build hadoop
```

随后再构建目标组件。

### 12.9 容器已运行但测试失败

```powershell
.\bigdata-cli.bat status spark
.\bigdata-cli.bat logs spark
.\bigdata-cli.bat test spark
```

测试失败应以测试日志指出的具体环节为准，不能仅凭容器状态判断组件正常。

### 12.10 Spark 连接了错误的 Hadoop 环境

先检查统一配置：

```powershell
Select-String -Path config\environment.conf -Pattern '^HADOOP_ENVIRONMENT='
```

连接标准 Hadoop，应显示 `HADOOP_ENVIRONMENT=standard`。然后重新创建 Spark 容器：

```powershell
.\bigdata-cli.bat destroy spark
.\bigdata-cli.bat start spark
```

如果当前 PowerShell 曾设置过同名变量，它会临时覆盖配置文件，应先移除：

```powershell
Remove-Item Env:HADOOP_ENVIRONMENT -ErrorAction SilentlyContinue
.\bigdata-cli.bat destroy spark
.\bigdata-cli.bat start spark
```

## 13. Windows 常用命令速查

```powershell
# 帮助和组件列表
.\bigdata-cli.bat --help
.\bigdata-cli.bat list

# 独立组件
.\bigdata-cli.bat build hadoop
.\bigdata-cli.bat start hadoop
.\bigdata-cli.bat stop hadoop
.\bigdata-cli.bat restart hadoop
.\bigdata-cli.bat status hadoop
.\bigdata-cli.bat logs hadoop
.\bigdata-cli.bat logs hadoop -f
.\bigdata-cli.bat test hadoop
.\bigdata-cli.bat destroy hadoop

# 五节点全栈
.\bigdata-cli.bat -a multi build all
.\bigdata-cli.bat -a multi start all
.\bigdata-cli.bat -a multi status all
.\bigdata-cli.bat -a multi supervisor all
.\bigdata-cli.bat -a multi test all
.\bigdata-cli.bat -a multi stop all
.\bigdata-cli.bat -a multi destroy all
```

## 14. Linux 或 WSL 中直接使用

如果已经进入 WSL，也可以跳过 `.bat`：

```bash
cd /mnt/e/Programs/Bigdata
bash bigdata-cli.sh --help
bash bigdata-cli.sh list
bash bigdata-cli.sh start hadoop
```

脚本会自动切换到自身所在的项目目录，因此也可以从其他目录通过绝对路径调用：

```bash
bash /mnt/e/Programs/Bigdata/bigdata-cli.sh status hadoop
```

Linux/WSL 的命令、架构和组件参数与 Windows 包装器相同。
