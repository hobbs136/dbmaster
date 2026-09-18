#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
为 integration_test/mongodb_real_data_test.dart 准备 MongoDB 测试数据。

用法:
    .venv_mongo/Scripts/python scripts/populate_mongodb_real_data.py

开源剥离：凭据不入库，经 DBMASTER_MONGO_* 环境变量提供（与
integration_test/config/mongodb_test_config.dart 的 dart-define 键同名），
缺参即退出。
"""

from pymongo import MongoClient
from datetime import datetime
from bson import ObjectId
from urllib.parse import quote_plus
import os
import random
import string
import sys

HOST = os.environ.get("DBMASTER_MONGO_HOST", "")
PORT = int(os.environ.get("DBMASTER_MONGO_PORT", "27017"))
USER = os.environ.get("DBMASTER_MONGO_USER", "")
PASSWORD = os.environ.get("DBMASTER_MONGO_PASSWORD", "")
AUTH_DB = os.environ.get("DBMASTER_MONGO_AUTH_DB", "admin")
DB_NAME = "dbmaster_test"

if not (HOST and USER and PASSWORD):
    sys.stderr.write(
        "需要 DBMASTER_MONGO_HOST / DBMASTER_MONGO_USER / "
        "DBMASTER_MONGO_PASSWORD 环境变量（开源剥离：凭据不入库，缺参即退出）\n"
    )
    sys.exit(1)


def random_string(length=10):
    return "".join(random.choices(string.ascii_letters + string.digits, k=length))


def main():
    uri = f"mongodb://{quote_plus(USER)}:{quote_plus(PASSWORD)}@{HOST}:{PORT}/{AUTH_DB}"
    client = MongoClient(uri, serverSelectionTimeoutMS=10000)
    client.drop_database(DB_NAME)
    db = client[DB_NAME]

    print(f"Populating {DB_NAME} on {HOST}:{PORT}...")

    # 1. products: 10 docs
    products = []
    categories = ["electronics", "books", "clothing", "food", "sports"]
    statuses = ["active", "inactive", "draft"]
    for i in range(10):
        products.append({
            "_id": ObjectId(),
            "name": f"Product {i + 1}" if i != 5 else f"<script>alert('xss')</script> Product {i + 1}",
            "price": round(random.uniform(10, 1000), 2),
            "featured": i % 2 == 0,
            "created": datetime.utcnow(),
            "tags": [f"tag{i}", f"tag{i + 1}"],
            "specs": {"weight": random.randint(100, 1000), "color": random.choice(["red", "blue", "green"])},
            "category": categories[i % len(categories)],
            "status": statuses[i % len(statuses)],
        })
    # ensure at least one electronics and multiple active
    products[0]["category"] = "electronics"
    products[0]["status"] = "active"
    products[1]["status"] = "active"
    products[2]["status"] = "active"
    db.products.insert_many(products)
    db.products.create_index("category")
    db.products.create_index("status")
    print(f"  products: {len(products)}")

    # 2. customers: for $lookup
    customers = []
    for i in range(5):
        customers.append({
            "_id": ObjectId(),
            "name": f"Customer {i + 1}",
            "email": f"customer{i + 1}@example.com",
        })
    db.customers.insert_many(customers)
    print(f"  customers: {len(customers)}")

    # 3. orders: with customer referencing customer _id
    orders = []
    for i in range(20):
        orders.append({
            "_id": ObjectId(),
            "order_no": f"ORD-{i + 1:05d}",
            "customer": random.choice(customers)["_id"],
            "total": round(random.uniform(50, 500), 2),
            "created_at": datetime.utcnow(),
        })
    db.orders.insert_many(orders)
    db.orders.create_index("customer")
    print(f"  orders: {len(orders)}")

    # 4. bulk_users: 100,000 docs
    bulk_users = []
    for i in range(100_000):
        bulk_users.append({
            "_id": ObjectId(),
            "username": f"user_{i + 1:06d}",
            "email": f"user_{i + 1:06d}@test.com",
            "age": random.randint(18, 80),
            "score": random.randint(0, 1000),
        })
    db.bulk_users.insert_many(bulk_users, ordered=False)
    print(f"  bulk_users: {len(bulk_users)}")

    # 5. large_docs: 102 docs, each ~1MB
    big_payload = "x" * (1024 * 1024)
    large_docs = []
    for i in range(102):
        large_docs.append({
            "_id": ObjectId(),
            "seq": i,
            "data": big_payload,
        })
    db.large_docs.insert_many(large_docs)
    print(f"  large_docs: {len(large_docs)}")

    # 6. nested: deep nested docs
    nested_docs = [
        {
            "_id": ObjectId(),
            "user": {
                "profile": {
                    "address": {
                        "city": "Beijing",
                        "geo": {"lat": 39.9, "lng": 116.4},
                    }
                }
            }
        },
        {
            "_id": ObjectId(),
            "user": {"name": "Alice", "age": 30},
        },
    ]
    db.nested.insert_many(nested_docs)
    print(f"  nested: {len(nested_docs)}")

    # 7. arrays: 2D array and mixed array
    arrays_docs = [
        {
            "_id": ObjectId(),
            "title": "2D Array",
            "matrix": [[1, 2, 3], [4, 5, 6], [7, 8, 9]],
        },
        {
            "_id": ObjectId(),
            "title": "Mixed Array",
            "mixed": [1, "two", True, {"nested": "value"}, None],
        },
        {
            "_id": ObjectId(),
            "title": "Simple",
            "items": ["a", "b", "c"],
        },
    ]
    db.arrays.insert_many(arrays_docs)
    print(f"  arrays: {len(arrays_docs)}")

    # 8. special_keys: dot keys and Chinese keys
    special_docs = [
        {
            "_id": ObjectId(),
            "user.name": "dotted key",
            "user.age": 25,
            "中文键": "Chinese key value",
            "名称": "测试",
        },
        {
            "_id": ObjectId(),
            "meta.tag.name": "nested dot",
            "描述": "描述信息",
        },
    ]
    db.special_keys.insert_many(special_docs)
    print(f"  special_keys: {len(special_docs)}")

    # 9. active_products_view
    db.active_products_view.drop()
    db.create_collection(
        "active_products_view",
        viewOn="products",
        pipeline=[{"$match": {"status": "active"}}],
    )
    print("  active_products_view: created")

    # 10. extra collections to reach >=10 collections
    db.users.insert_many([
        {"_id": ObjectId(), "username": f"u{i}", "age": random.randint(18, 60)}
        for i in range(10)
    ])
    print("  users: 10")

    db.bson_types.insert_many([
        {"_id": ObjectId(), "label": "sample", "value": i}
        for i in range(5)
    ])
    print("  bson_types: 5")

    # Summary
    stats = db.command("dbStats")
    print(f"\nDone. Collections: {stats['collections']}, Documents: {stats['objects']}, Data size: {stats['dataSize']} bytes")

    client.close()


if __name__ == "__main__":
    main()
