#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Kafka 生产者示例（独立程序，配合 kafka_consumer.py 使用）。

前置：先启动 zookeeper + kafka 集群（网页 /portal 点 Kafka 会自动带起 ZooKeeper）。
运行（在 client 容器内，/workspace 下）：
    python3 python/kafka_producer.py
    python3 python/kafka_producer.py --count 10 --topic my-topic

说明：
    - 默认连接 kafka1:9092,kafka2:9092,kafka3:9092（容器服务名，走 bigdata-net 内部网络）
    - 每条消息用 send().get() 等待 broker 确认，打印 topic/partition/offset，
      能直观确认消息确实写入了 Kafka 集群。
    - BOOTSTRAP / TOPIC 可用环境变量或命令行参数覆盖。
"""
import argparse
import json
import os
import time

from kafka import KafkaProducer

DEFAULT_BOOTSTRAP = "kafka1:9092,kafka2:9092,kafka3:9092"


def main():
    ap = argparse.ArgumentParser(description="Kafka 生产者：发送若干条 JSON 消息")
    ap.add_argument("--bootstrap", default=os.environ.get("KAFKA_BOOTSTRAP", DEFAULT_BOOTSTRAP),
                     help="broker 列表，逗号分隔（默认 %s）" % DEFAULT_BOOTSTRAP)
    ap.add_argument("--topic", default=os.environ.get("KAFKA_TOPIC", "client-demo"),
                     help="目标 topic（默认 client-demo）")
    ap.add_argument("--count", type=int, default=5, help="发送消息条数（默认 5）")
    ap.add_argument("--key", default="demo", help="消息 key（默认 demo）")
    args = ap.parse_args()

    servers = [s.strip() for s in args.bootstrap.split(",") if s.strip()]
    print("连接 Kafka: %s" % servers)
    print("目标 topic : %s   消息条数: %d" % (args.topic, args.count))
    print("-" * 60)

    producer = KafkaProducer(
        bootstrap_servers=servers,
        key_serializer=lambda k: k.encode("utf-8"),
        value_serializer=lambda v: json.dumps(v, ensure_ascii=False).encode("utf-8"),
        request_timeout_ms=15000,
        retries=3,
    )

    for i in range(1, args.count + 1):
        event = {
            "seq": i,
            "source": "kafka_producer.py",
            "message": "你好 Kafka 第 %d 条消息" % i,
            "ts": time.strftime("%Y-%m-%d %H:%M:%S"),
        }
        future = producer.send(args.topic, key=args.key, value=event)
        meta = future.get(timeout=20)  # 等待 broker 确认
        print("  已发送 seq=%-3d topic=%-12s partition=%-2s offset=%s"
              % (i, meta.topic, meta.partition, meta.offset))

    producer.flush()
    producer.close()
    print("-" * 60)
    print("完成：%d 条消息已全部写入 topic=%s" % (args.count, args.topic))


if __name__ == "__main__":
    main()
