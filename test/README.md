# 测试目录说明

## 运行方式

所有脚本都应从项目根目录使用 Bash 执行：

```bash
bash test/test-hadoop.sh
bash test/test-kafka.sh
bash test/cluster-test.sh
```

独立组件测试要求相应容器及上游依赖已经启动；`cluster-test.sh` 只用于五节点全栈架构。具体依赖和覆盖范围见同名 `.md`。

## 如何阅读测试说明

每个测试脚本都有一个同名 Markdown，内容直接对应脚本，统一说明：

1. 测试覆盖哪些方面；
2. 脚本按什么顺序执行；
3. 每一步实际执行的命令或操作；
4. 命令会返回什么关键结果；
5. 满足什么条件时该步骤通过；
6. 哪些失败会使整个脚本返回非零退出码。

运行脚本后可以检查退出码：

```bash
bash test/test-hadoop.sh
echo $?
```

退出码为 `0` 表示脚本规定的全部关键条件均已满足；退出码非 `0` 表示至少一个关键测试项失败。不能只根据命令是否执行结束判断通过，还要核对同名 Markdown 中列出的预期结果和断言条件。

## 统一日志约定

- 日志目录：`test/test-log/`
- 文件名：`测试名-YYYYMMDD-HHMMSS.log`
- 主要标记：`[信息]`、`[通过]`、`[失败]`、`[跳过]`、`[详情]`、`[诊断]`
- 测试资源尽量使用时间戳和进程号生成唯一名称。
- 失败必须返回非零退出码；不能用“可能未配置”“结果不确定”等信息代替关键断言。
- 失败日志应至少包含失败阶段、实际输出和下一步排查方向。

`test-common.sh` 为部分新测试提供统一日志、容器检查、计数和汇总函数，它不是独立测试脚本。

## 脚本与说明对应关系

| 脚本 | 说明 |
|---|---|
| `test-hadoop.sh` | [Hadoop 标准集群](test-hadoop.md) |
| `test-hadoop-ha.sh` | [Hadoop HA](test-hadoop-ha.md) |
| `test-zookeeper.sh` | [ZooKeeper](test-zookeeper.md) |
| `test-kafka.sh` | [Kafka](test-kafka.md) |
| `test-flume.sh` | [Flume](test-flume.md) |
| `test-flume-kafka.sh` | [Flume → Kafka](test-flume-kafka.md) |
| `test-hbase.sh` | [HBase](test-hbase.md) |
| `test-hive.sh` | [Hive](test-hive.md) |
| `test-mysql.sh` | [MySQL](test-mysql.md) |
| `test-spark.sh` | [Spark](test-spark.md) |
| `test-flink.sh` | [Flink](test-flink.md) |
| `cluster-test.sh` | [五节点综合测试](cluster-test.md) |
