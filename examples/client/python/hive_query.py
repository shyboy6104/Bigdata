#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""PyHive 连接 HiveServer2 的示例。

前置：先启动 hadoop + mysql + hive（网页 /portal 里点 Hive 会自动带起依赖）。
运行：python3 python/hive_query.py

也可以用命令行验证：beeline -u jdbc:hive2://hive-server2:10000 -n root
"""
import os

from pyhive import hive

HOST = os.environ.get("HIVE_HOST", "hive-server2")
PORT = int(os.environ.get("HIVE_PORT", "10000"))
DATABASE = os.environ.get("HIVE_DATABASE", "default")


def main():
    conn = hive.Connection(host=HOST, port=PORT, username="root",
                           database=DATABASE)
    try:
        cur = conn.cursor()
        cur.execute("SHOW TABLES")
        tables = cur.fetchall()
        print("HiveServer2 %s:%s/%s 已连接，共 %d 张表"
              % (HOST, PORT, DATABASE, len(tables)))
        for row in tables[:20]:
            print("  ", row[0])
        cur.close()
    finally:
        conn.close()


if __name__ == "__main__":
    main()
