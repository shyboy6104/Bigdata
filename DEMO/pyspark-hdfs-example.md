# PySpark 读写 Docker HDFS 示例

两个示例都会把订单数据以 Parquet 格式写入 HDFS，再从 HDFS 读回并汇总。
示例将 `dfs.replication` 设置为 `2`，与当前两个 DataNode 的集群规模一致。

HDFS 目录：

```text
/examples/pyspark-hdfs/orders
```

重复运行会覆盖该教学目录中的旧数据。

## 本地 Driver

确保 `docker-compose.hadoop.yml` 已将 NameNode RPC 端口映射为 `8020:8020`，
然后执行：

```powershell
conda activate pyspark_proj
cd E:\Programs\Bigdata
python DEMO\pyspark-hdfs-example-local.py
```

本地脚本自动取得 Windows 主机的局域网 IPv4 地址，例如
`hdfs://10.248.224.109:8020`。Docker 将宿主机 8020 端口转发到 NameNode，
该地址可同时被本地 Driver 和 Docker 中的 Executor 访问。

## Docker Driver

```powershell
cd E:\Programs\Bigdata
docker cp DEMO\pyspark-hdfs-example-docker.py spark-master:/tmp/example.py
docker exec spark-master python3 /tmp/example.py
```

容器脚本使用 Docker DNS 地址 `hdfs://namenode:8020`。当前 NameNode IP 是
`172.18.0.3`，但代码不硬编码这个可能在容器重建后改变的 IP。

## 预期结果

```text
+--------+------------+
|category|total_amount|
+--------+------------+
|    book|         200|
|    food|         120|
+--------+------------+
```

可检查 HDFS 文件：

```powershell
docker exec namenode hdfs dfs -ls /examples/pyspark-hdfs/orders
```
