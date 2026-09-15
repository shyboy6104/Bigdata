# PySpark 入门示例

两个脚本执行相同的订单汇总任务，区别仅在于 Driver 的运行位置。

## 1. 在本地运行

脚本：`pyspark-example-local.py`

```powershell
conda activate pyspark_proj
cd E:\Programs\Bigdata
python DEMO\pyspark-example-local.py
```

- Driver：Windows 本地
- Master：`spark://127.0.0.1:7077`（Docker 映射端口）
- Executor：Docker 中的 Spark Worker

## 2. 在 Docker 中运行

脚本：`pyspark-example-docker.py`

先把脚本复制到 Master 容器，再执行：

```powershell
cd E:\Programs\Bigdata
docker cp DEMO\pyspark-example-docker.py spark-master:/tmp/pyspark-example.py
docker exec spark-master python3 /tmp/pyspark-example.py
```

- Driver：`spark-master` 容器
- Master：`spark://spark-master:7077`
- Executor：Docker 中的 Spark Worker

## 预期结果

两个脚本的数据和计算步骤相同：

1. 创建订单 DataFrame。
2. 保留 `status` 为 `paid` 的订单。
3. 按 `category` 分组。
4. 对 `amount` 求和。

```text
+--------+------------+
|category|total_amount|
+--------+------------+
|    book|         200|
|    food|         120|
+--------+------------+
```

本地示例通过 `log4j-local.properties` 定向隐藏缺少 `winutils.exe` 的警告。
这只适用于当前不在 Windows 本地调用 Hadoop 文件工具的示例；如需进行本地
Hadoop 文件操作，仍应安装匹配版本的 `winutils.exe` 并设置 `HADOOP_HOME`。
