#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Kafka 消费者示例（独立程序，配合 kafka_producer.py 使用）。

前置：先启动 zookeeper + kafka 集群。
运行（在 client 容器内，/workspace 下）：
    python3 python/kafka_consumer.py                 # 从头消费，空闲 15 秒后自动退出
    python3 python/kafka_consumer.py --max 5         # 收到 5 条就退出
    python3 python/kafka_consumer.py --group g1       # 指定消费组

说明：
    - 默认 auto_offset_reset=earliest，能读到生产者之前已写入的历史消息；
      也可先起本消费者（阻塞等待），再另开终端跑生产者，观察实时接收。
    - BOOTSTRAP / TOPIC 可用环境变量或命令行参数覆盖，需与生产者保持一致。
"""
import argparse
import json
import os

from kafka import KafkaConsumer

DEFAULT_BOOTSTRAP = "kafka1:9092,kafka2:9092,kafka3:9092"


def main():
    ap = argparse.ArgumentParser(description="Kafka 消费者：订阅并打印 JSON 消息")
    ap.add_argument("--bootstrap", default=os.environ.get("KAFKA_BOOTSTRAP", DEFAULT_BOOTSTRAP),
                     help="broker 列表，逗号分隔（默认 %s）" % DEFAULT_BOOTSTRAP)
    ap.add_argument("--topic", default=os.environ.get("KAFKA_TOPIC", "client-demo"),
                     help="订阅的 topic（默认 client-demo）")
    ap.add_argument("--group", default=os.environ.get("KAFKA_GROUP") or None,
                     help="消费组 id（默认 None，独立读取）")
    ap.add_argument("--max", type=int, default=0, help="最多消费条数，0 表示不限（默认 0）")
    ap.add_argument("--timeout", type=int, default=15,
                     help="空闲多少秒后自动退出（默认 15 秒；0 表示一直等待）")
    ap.add_argument("--latest", action="store_true",
                     help="只消费新消息（默认从最早开始）")
    args = ap.parse_args()

    servers = [s.strip() for s in args.bootstrap.split(",") if s.strip()]
    print("连接 Kafka: %s" % servers)
    print("订阅 topic : %s   offset=%s   group=%s"
          % (args.topic, "latest" if args.latest else "earliest", args.group or "(none)"))
    print("-" * 60)

    consumer = KafkaConsumer(
        args.topic,
        bootstrap_servers=servers,
        group_id=args.group,
        auto_offset_reset="latest" if args.latest else "earliest",
        enable_auto_commit=True,
        consumer_timeout_ms=1000,  # 每 1 秒无消息返回一次，便于检查退出条件
        request_timeout_ms=15000,
        value_deserializer=lambda v: json.loads(v.decode("utf-8")),
        key_deserializer=lambda k: k.decode("utf-8") if k else None,
    )

    count, idle_ms = 0, 0
    print("等待消息中（Ctrl+C 可退出）...")
    while True:
        got = False
        # 一次拉取一批，poll 超时即算空闲
        batch = consumer.poll(timeout_ms=1000)
        for _tp, records in batch.items():
            for msg in records:
                got = True
                count += 1
                print("  收到 key=%-8s partition=%-2s offset=%-4s value=%s"
                      % (msg.key, msg.partition, msg.offset, msg.value))
                if args.max and count >= args.max:
                    break
            if args.max and count >= args.max:
                break
        if args.max and count >= args.max:
            break
        if not got:
            idle_ms += 1000
            if args.timeout and idle_ms >= args.timeout * 1000:
                break
        else:
            idle_ms = 0

    consumer.close()
    print("-" * 60)
    print("结束：共消费 %d 条消息（topic=%s）" % (count, args.topic))


if __name__ == "__main__":
    main()
