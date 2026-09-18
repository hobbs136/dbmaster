#!/usr/bin/env python3
"""
Elasticsearch 测试数据生成脚本
为 DbMaster ES 集成测试创建真实业务数据

用法:
    source .venv_es/bin/activate
    DBMASTER_ES_HOST=https://<host>:9200 DBMASTER_ES_USER=<user> \
        DBMASTER_ES_PASSWORD=<pass> python scripts/generate_es_test_data.py

开源剥离：凭据不入库，经 DBMASTER_ES_* 环境变量提供，缺参即退出。
"""

from elasticsearch import Elasticsearch
from elasticsearch.helpers import bulk
import os
import random
import datetime
import uuid
import sys

# ES 连接配置（环境变量注入）


def _require_env(name: str) -> str:
    value = os.environ.get(name, "")
    if not value:
        sys.stderr.write(
            f"需要环境变量 {name}（开源剥离：凭据不入库，缺参即退出）\n"
        )
        sys.exit(1)
    return value


ES_HOST = _require_env("DBMASTER_ES_HOST")
ES_USER = _require_env("DBMASTER_ES_USER")
ES_PASS = _require_env("DBMASTER_ES_PASSWORD")

# 要创建的索引前缀
INDEX_PREFIX = "dbmaster"

# 删除旧数据开关
DELETE_EXISTING = True


def get_es_client():
    """创建 Elasticsearch 客户端（跳过自签名证书验证）"""
    return Elasticsearch(
        [ES_HOST],
        basic_auth=(ES_USER, ES_PASS),
        verify_certs=False,
        ssl_show_warn=False,
        request_timeout=60,
    )


def delete_existing_indices(es):
    """删除之前由脚本创建的索引"""
    indices = es.cat.indices(format="json", h="index")
    for idx in indices:
        name = idx["index"]
        if name.startswith(f"{INDEX_PREFIX}_"):
            print(f"  删除旧索引: {name}")
            es.indices.delete(index=name, ignore=[404])


def create_orders_index(es):
    """创建电商订单索引（含 nested 和 date 类型）"""
    index = f"{INDEX_PREFIX}_orders"
    mapping = {
        "mappings": {
            "properties": {
                "order_id": {"type": "keyword"},
                "customer_name": {"type": "text", "fields": {"keyword": {"type": "keyword", "ignore_above": 256}}},
                "amount": {"type": "double"},
                "status": {"type": "keyword"},
                "created_at": {"type": "date"},
                "items": {
                    "type": "nested",
                    "properties": {
                        "product_name": {"type": "keyword"},
                        "quantity": {"type": "integer"},
                        "unit_price": {"type": "double"},
                    }
                },
                "tags": {"type": "keyword"},
                "is_paid": {"type": "boolean"},
                "shipping_address": {
                    "type": "object",
                    "properties": {
                        "city": {"type": "keyword"},
                        "zip": {"type": "keyword"},
                    }
                },
            }
        }
    }
    es.indices.create(index=index, body=mapping, ignore=[400])
    print(f"  创建索引: {index}")
    return index


def generate_orders_data(count=200):
    """生成订单数据"""
    statuses = ["pending", "paid", "shipped", "delivered", "cancelled"]
    products = ["iPhone 15", "MacBook Pro", "AirPods", "iPad Air", "Apple Watch", "Magic Mouse", "USB-C Cable", "Screen Protector"]
    cities = ["Beijing", "Shanghai", "Shenzhen", "Guangzhou", "Hangzhou", "Chengdu", "Wuhan", "Nanjing"]
    customers = ["Alice", "Bob", "Charlie", "Diana", "Eve", "Frank", "Grace", "Henry", "Ivy", "Jack"]
    tags_pool = ["vip", "promotion", "wholesale", "retail", "new_customer", "recurring"]

    base_time = datetime.datetime(2024, 1, 1, 0, 0, 0)

    for i in range(count):
        num_items = random.randint(1, 4)
        items = []
        total = 0
        for _ in range(num_items):
            qty = random.randint(1, 5)
            price = round(random.uniform(9.9, 2999.0), 2)
            items.append({
                "product_name": random.choice(products),
                "quantity": qty,
                "unit_price": price,
            })
            total += qty * price

        created = base_time + datetime.timedelta(
            days=random.randint(0, 365),
            hours=random.randint(0, 23),
            minutes=random.randint(0, 59),
        )

        yield {
            "_index": f"{INDEX_PREFIX}_orders",
            "_source": {
                "order_id": f"ORD-{i+1:05d}",
                "customer_name": random.choice(customers),
                "amount": round(total, 2),
                "status": random.choice(statuses),
                "created_at": created.isoformat(),
                "items": items,
                "tags": random.sample(tags_pool, k=random.randint(0, 3)),
                "is_paid": random.choice([True, False]),
                "shipping_address": {
                    "city": random.choice(cities),
                    "zip": f"{random.randint(100000, 999999)}",
                },
            }
        }


def create_logs_index(es):
    """创建日志索引（含 geo_point、IP、text 类型）"""
    index = f"{INDEX_PREFIX}_logs"
    mapping = {
        "mappings": {
            "properties": {
                "timestamp": {"type": "date"},
                "level": {"type": "keyword"},
                "message": {"type": "text"},
                "source_ip": {"type": "ip"},
                "location": {"type": "geo_point"},
                "user_agent": {"type": "text", "index": False},
                "service": {"type": "keyword"},
                "duration_ms": {"type": "integer"},
                "error_code": {"type": "keyword"},
            }
        }
    }
    es.indices.create(index=index, body=mapping, ignore=[400])
    print(f"  创建索引: {index}")
    return index


def generate_logs_data(count=500):
    """生成日志数据"""
    levels = ["INFO", "WARN", "ERROR", "DEBUG"]
    services = ["api-gateway", "user-service", "order-service", "payment-service", "notification-service"]
    messages = [
        "Request processed successfully",
        "Database connection timeout",
        "Invalid authentication token",
        "Cache miss for key",
        "Retry attempt failed",
        "Payment webhook received",
        "User session expired",
        "Rate limit exceeded",
        "Background job completed",
        "Email sent successfully",
    ]
    cities_coords = [
        {"lat": 39.9042, "lon": 116.4074},   # Beijing
        {"lat": 31.2304, "lon": 121.4737},   # Shanghai
        {"lat": 22.5431, "lon": 114.0579},   # Shenzhen
        {"lat": 23.1291, "lon": 113.2644},   # Guangzhou
        {"lat": 30.2741, "lon": 120.1551},   # Hangzhou
    ]

    base_time = datetime.datetime(2024, 6, 1, 0, 0, 0)

    for i in range(count):
        level = random.choice(levels)
        has_error = level == "ERROR"

        yield {
            "_index": f"{INDEX_PREFIX}_logs",
            "_source": {
                "timestamp": (base_time + datetime.timedelta(
                    days=random.randint(0, 30),
                    hours=random.randint(0, 23),
                    minutes=random.randint(0, 59),
                    seconds=random.randint(0, 59),
                )).isoformat(),
                "level": level,
                "message": f"{random.choice(messages)} #{i+1}",
                "source_ip": f"192.168.{random.randint(1, 254)}.{random.randint(1, 254)}",
                "location": random.choice(cities_coords),
                "user_agent": "Mozilla/5.0 (compatible; DbMasterBot/1.0)",
                "service": random.choice(services),
                "duration_ms": random.randint(5, 5000) if level != "ERROR" else random.randint(5000, 30000),
                "error_code": f"ERR-{random.randint(1000, 9999)}" if has_error else None,
            }
        }


def create_products_index(es):
    """创建产品目录索引（含 text + keyword 子字段、object）"""
    index = f"{INDEX_PREFIX}_products"
    mapping = {
        "mappings": {
            "properties": {
                "sku": {"type": "keyword"},
                "name": {"type": "text", "fields": {"keyword": {"type": "keyword", "ignore_above": 256}}},
                "description": {"type": "text"},
                "category": {"type": "keyword"},
                "price": {"type": "double"},
                "rating": {"type": "float"},
                "in_stock": {"type": "boolean"},
                "stock_count": {"type": "integer"},
                "specs": {
                    "type": "object",
                    "properties": {
                        "color": {"type": "keyword"},
                        "weight_kg": {"type": "double"},
                        "dimensions": {"type": "keyword"},
                    }
                },
                "created_at": {"type": "date"},
                "tags": {"type": "keyword"},
            }
        }
    }
    es.indices.create(index=index, body=mapping, ignore=[400])
    print(f"  创建索引: {index}")
    return index


def generate_products_data(count=100):
    """生成产品数据"""
    categories = ["Electronics", "Clothing", "Food", "Books", "Home", "Sports"]
    colors = ["Black", "White", "Red", "Blue", "Silver", "Gold"]
    names = [
        ("Wireless Mouse", "Electronics"),
        ("Running Shoes", "Sports"),
        ("Organic Coffee Beans", "Food"),
        ("Sci-Fi Novel Collection", "Books"),
        ("Smart LED Bulb", "Home"),
        ("Cotton T-Shirt", "Clothing"),
        ("Bluetooth Speaker", "Electronics"),
        ("Yoga Mat", "Sports"),
        ("Green Tea Set", "Food"),
        ("Cookbook", "Books"),
    ]

    for i in range(count):
        name, category = random.choice(names)
        yield {
            "_index": f"{INDEX_PREFIX}_products",
            "_source": {
                "sku": f"SKU-{i+1:04d}",
                "name": f"{name} {random.randint(1, 99)}",
                "description": f"High quality {name.lower()} with excellent reviews. Perfect for everyday use.",
                "category": category,
                "price": round(random.uniform(9.99, 999.99), 2),
                "rating": round(random.uniform(1.0, 5.0), 1),
                "in_stock": random.choice([True, False]),
                "stock_count": random.randint(0, 1000),
                "specs": {
                    "color": random.choice(colors),
                    "weight_kg": round(random.uniform(0.1, 5.0), 2),
                    "dimensions": f"{random.randint(10, 50)}x{random.randint(10, 50)}x{random.randint(5, 20)}cm",
                },
                "created_at": (datetime.datetime(2024, 1, 1) + datetime.timedelta(days=random.randint(0, 180))).isoformat(),
                "tags": random.sample(["new", "sale", "bestseller", "limited", "eco"], k=random.randint(1, 3)),
            }
        }


def create_users_index(es):
    """创建用户索引（测试多种 nullable 场景）"""
    index = f"{INDEX_PREFIX}_users"
    mapping = {
        "mappings": {
            "properties": {
                "username": {"type": "keyword"},
                "email": {"type": "keyword"},
                "age": {"type": "integer"},
                "gender": {"type": "keyword"},
                "register_date": {"type": "date"},
                "last_login": {"type": "date"},
                "is_active": {"type": "boolean"},
                "score": {"type": "float"},
                "preferences": {
                    "type": "object",
                    "properties": {
                        "theme": {"type": "keyword"},
                        "notifications": {"type": "boolean"},
                        "language": {"type": "keyword"},
                    }
                },
                "bio": {"type": "text"},
                "phone": {"type": "keyword"},
                "tags": {"type": "keyword"},
            }
        }
    }
    es.indices.create(index=index, body=mapping, ignore=[400])
    print(f"  创建索引: {index}")
    return index


def generate_users_data(count=150):
    """生成用户数据（部分字段故意留空/null）"""
    genders = ["male", "female", "other", None]
    themes = ["dark", "light", "auto"]
    languages = ["zh-CN", "en-US", "ja-JP", "de-DE", "fr-FR"]

    for i in range(count):
        has_bio = random.random() > 0.3
        has_phone = random.random() > 0.4
        gender = random.choice(genders)

        yield {
            "_index": f"{INDEX_PREFIX}_users",
            "_source": {
                "username": f"user_{i+1:04d}",
                "email": f"user_{i+1:04d}@example.com",
                "age": random.randint(18, 80) if random.random() > 0.1 else None,
                "gender": gender,
                "register_date": (datetime.datetime(2023, 1, 1) + datetime.timedelta(days=random.randint(0, 500))).isoformat(),
                "last_login": (datetime.datetime(2024, 6, 1) + datetime.timedelta(days=random.randint(0, 30))).isoformat() if random.random() > 0.2 else None,
                "is_active": random.choice([True, False]),
                "score": round(random.uniform(0, 100), 2) if random.random() > 0.15 else None,
                "preferences": {
                    "theme": random.choice(themes),
                    "notifications": random.choice([True, False]),
                    "language": random.choice(languages),
                } if random.random() > 0.1 else {},
                "bio": f"I am a passionate user of DbMaster. Love working with databases!" if has_bio else None,
                "phone": f"138{random.randint(10000000, 99999999)}" if has_phone else None,
                "tags": random.sample(["developer", "dba", "analyst", "manager", "student"], k=random.randint(0, 2)),
            }
        }


def main():
    print("=" * 60)
    print("Elasticsearch 测试数据生成脚本")
    print("=" * 60)

    es = get_es_client()
    info = es.info()
    print(f"\n✅ 已连接到 Elasticsearch {info['version']['number']}")
    print(f"   集群: {info['cluster_name']}")
    print(f"   节点: {info['name']}")

    if DELETE_EXISTING:
        print("\n🧹 清理旧测试数据...")
        delete_existing_indices(es)

    print("\n📦 创建索引...")
    create_orders_index(es)
    create_logs_index(es)
    create_products_index(es)
    create_users_index(es)

    print("\n📝 写入订单数据 (200 条)...")
    success, errors = bulk(es, generate_orders_data(200), refresh=True)
    print(f"   成功: {success}, 失败: {len(errors)}")

    print("\n📝 写入日志数据 (500 条)...")
    success, errors = bulk(es, generate_logs_data(500), refresh=True)
    print(f"   成功: {success}, 失败: {len(errors)}")

    print("\n📝 写入产品数据 (100 条)...")
    success, errors = bulk(es, generate_products_data(100), refresh=True)
    print(f"   成功: {success}, 失败: {len(errors)}")

    print("\n📝 写入用户数据 (150 条)...")
    success, errors = bulk(es, generate_users_data(150), refresh=True)
    print(f"   成功: {success}, 失败: {len(errors)}")

    print("\n📊 数据统计:")
    for idx_name in ["orders", "logs", "products", "users"]:
        full = f"{INDEX_PREFIX}_{idx_name}"
        count = es.count(index=full)["count"]
        print(f"   {full}: {count} 文档")

    print("\n✅ 测试数据准备完成!")
    print("=" * 60)


if __name__ == "__main__":
    main()
