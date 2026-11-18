#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""kafka-python 生产/消费示例。

前置：先启动 zookeeper + kafka（网页 /portal 里点 Kafka 会自动带起 ZooKeeper）。
运行：python3 python/kafka_demo.py

Flume 的 Kafka sink 写入 topic `flume-logs`；把 TOPIC 改成 flume-logs
即可消费 Flume 采集到的数据。
"""
import json
import os
import time

from kafka import KafkaConsumer, KafkaProducer

BOOTSTRAP = os.environ.get(
    "KAFKA_BOOTSTRAP", "kafka1:9092,kafka2:9092,kafka3:9092"
).split(",")
TOPIC = os.environ.get("KAFKA_TOPIC", "client-demo")


def main():
    producer = KafkaProducer(
        bootstrap_servers=BOOTSTRAP,
        value_serializer=lambda v: json.dumps(v, ensure_ascii=False).encode("utf-8"),
        request_timeout_ms=10000,
    )
    for i in range(3):
        event = {"seq": i, "source": "client", "message": "hello kafka %d" % i}
        future = producer.send(TOPIC, event)
        meta = future.get(timeout=15)
        print("已发送 topic=%s partition=%s offset=%s %s"
              % (meta.topic, meta.partition, meta.offset, event))
    producer.flush()
    producer.close()

    consumer = KafkaConsumer(
        TOPIC,
        bootstrap_servers=BOOTSTRAP,
        auto_offset_reset="earliest",
        group_id=None,
        consumer_timeout_ms=8000,
        value_deserializer=lambda v: json.loads(v.decode("utf-8")),
    )
    print("--- 消费 %s ---" % TOPIC)
    for msg in consumer:
        print("  p=%s off=%s %s" % (msg.partition, msg.offset, msg.value))
    consumer.close()


if __name__ == "__main__":
    main()
