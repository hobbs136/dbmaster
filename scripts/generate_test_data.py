#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
DbMaster 自动化测试数据生成脚本
使用 dbmaster_connections.yaml 中的连接信息，为所有数据库生成测试数据。

支持的数据库:
- MySQL (含 MySQL 8.0, MySQL 5.7, Doris)
- PostgreSQL
- MongoDB
- Redis
- SQL Server
- Oracle
- Elasticsearch

使用方法:
    cd /Users/jacky/development/dbmaster-flutter
    source .venv_es/bin/activate
    python scripts/generate_test_data.py
"""

import yaml
import random
import string
import datetime
import uuid
import sys
import json
from pathlib import Path
from typing import Dict, List, Any, Optional
from dataclasses import dataclass, field

# Database drivers
import pymysql
import psycopg2
import redis as redis_lib
from pymongo import MongoClient
import pyodbc
import oracledb
from elasticsearch import Elasticsearch

# ============================================================================
# Configuration
# ============================================================================

PROJECT_ROOT = Path(__file__).parent.parent
CONNECTIONS_FILE = PROJECT_ROOT / "dbmaster_connections.yaml"
TEST_DB_NAME = "dbmaster_test"
TEST_DATA_COUNT = {
    "users": 100,
    "orders": 500,
    "products": 50,
}

# ============================================================================
# Data Generators
# ============================================================================

class DataGenerator:
    """生成逼真的测试数据"""

    FIRST_NAMES = [
        "James", "Mary", "John", "Patricia", "Robert", "Jennifer", "Michael", "Linda",
        "William", "Elizabeth", "David", "Barbara", "Richard", "Susan", "Joseph", "Jessica",
        "Thomas", "Sarah", "Charles", "Karen", "Christopher", "Nancy", "Daniel", "Lisa",
        "Matthew", "Betty", "Anthony", "Margaret", "Mark", "Sandra", "Donald", "Ashley",
        "Steven", "Kimberly", "Paul", "Emily", "Andrew", "Donna", "Joshua", "Michelle",
        "Kenneth", "Dorothy", "Kevin", "Carol", "Brian", "Amanda", "George", "Melissa",
        "Edward", "Deborah", "Ronald", "Stephanie", "Timothy", "Rebecca", "Jason", "Sharon",
        "Jeffrey", "Laura", "Ryan", "Cynthia", "Jacob", "Kathleen", "Gary", "Amy",
        "Nicholas", "Shirley", "Eric", "Angela", "Jonathan", "Helen", "Stephen", "Anna",
        "Larry", "Brenda", "Justin", "Pamela", "Scott", "Nicole", "Brandon", "Emma",
        "Benjamin", "Samantha", "Samuel", "Katherine", "Frank", "Christine", "Gregory", "Debra",
        "Raymond", "Rachel", "Alexander", "Catherine", "Patrick", "Carolyn", "Jack", "Janet",
        "Dennis", "Ruth", "Jerry", "Maria", "Tyler", "Heather", "Aaron", "Diane",
        "Jose", "Virginia", "Adam", "Julie", "Henry", "Joyce", "Nathan", "Victoria",
        "Zachary", "Olivia", "Douglas", "Kelly", "Peter", "Christina", "Kyle", "Lauren",
        "Noah", "Joan", "Ethan", "Evelyn", "Christian", "Olivia", "Walter", "Judith",
        "Jeremy", "Megan", "Keith", "Cheryl", "Austin", "Andrea", "Roger", "Hannah",
        "Terry", "Martha", "Sean", "Jacqueline", "Gerald", "Frances", "Carl", "Gloria",
        "Dylan", "Ann", "Harold", "Teresa", "Jordan", "Kathryn", "Jesse", "Sara",
        "Bryan", "Janice", "Lawrence", "Jean", "Arthur", "Alice", "Gabriel", "Madison",
        "Bruce", "Doris", "Logan", "Abigail", "Billy", "Julia", "Joe", "Judy",
        "Alan", "Grace", "Juan", "Denise", "Elijah", "Amber", "Willie", "Marilyn",
        "Albert", "Beverly", "Wayne", "Danielle", "Randy", "Theresa", "Mason", "Sophia",
        "Vincent", "Marie", "Liam", "Diana", "Roy", "Brittany", "Bobby", "Natalie",
        "Caleb", "Isabella", "Bradley", "Charlotte", "Russell", "Rose", "Lucas", "Alexis",
        "Alex", "Kayla", "Johnny", "Lori", "Philip", "张", "王", "李", "刘", "陈",
        "杨", "赵", "黄", "周", "吴", "徐", "孙", "胡", "朱", "高", "林", "何",
        "郭", "马", "罗", "梁", "宋", "郑", "谢", "韩", "唐", "冯", "于", "董",
        "萧", "程", "曹", "袁", "邓", "许", "傅", "沈", "曾", "彭", "吕", "苏",
        "卢", "蒋", "蔡", "贾", "丁", "魏", "薛", "叶", "阎", "余", "潘", "杜",
        "戴", "夏", "钟", "汪", "田", "任", "姜", "范", "方", "石", "姚", "谭",
        "廖", "邹", "熊", "金", "陆", "郝", "孔", "白", "崔", "康", "毛", "邱",
        "秦", "江", "史", "顾", "侯", "邵", "孟", "龙", "万", "段", "雷", "钱",
        "汤", "尹", "黎", "易", "常", "武", "乔", "贺", "赖", "龚", "文", "庞",
    ]

    LAST_NAMES = [
        "Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis",
        "Rodriguez", "Martinez", "Hernandez", "Lopez", "Gonzalez", "Wilson", "Anderson",
        "Thomas", "Taylor", "Moore", "Jackson", "Martin", "Lee", "Perez", "Thompson",
        "White", "Harris", "Sanchez", "Clark", "Ramirez", "Lewis", "Robinson", "Walker",
        "Young", "Allen", "King", "Wright", "Scott", "Torres", "Nguyen", "Hill", "Flores",
        "Green", "Adams", "Nelson", "Baker", "Hall", "Rivera", "Campbell", "Mitchell",
        "Carter", "Roberts", "Gomez", "Phillips", "Evans", "Turner", "Diaz", "Parker",
        "Cruz", "Edwards", "Collins", "Reyes", "Stewart", "Morris", "Morales", "Murphy",
        "Cook", "Rogers", "Gutierrez", "Ortiz", "Morgan", "Cooper", "Peterson", "Bailey",
        "Reed", "Kelly", "Howard", "Ramos", "Kim", "Cox", "Ward", "Richardson", "Watson",
        "Brooks", "Chavez", "Wood", "James", "Bennett", "Gray", "Mendoza", "Ruiz", "Hughes",
        "Price", "Alvarez", "Castillo", "Sanders", "Patel", "Myers", "Long", "Ross",
        "Foster", "Jimenez", "伟", "芳", "娜", "敏", "静", "丽", "强", "磊", "军",
        "洋", "勇", "艳", "杰", "娟", "涛", "明", "超", "秀", "霞", "平", "刚",
        "桂英", "华", "志强", "秀英", "博", "文", "建华", "桂兰", "建国", "秀珍",
        "敏华", "秀芳", "丽华", "桂珍", "秀兰", "建平", "桂芳", "玉梅", "桂香", "秀英",
    ]

    PRODUCT_NAMES = [
        "Wireless Mouse", "Mechanical Keyboard", "USB-C Hub", "4K Monitor", "Webcam 1080p",
        "Noise Cancelling Headphones", "Bluetooth Speaker", "Portable SSD 1TB", "Gaming Laptop",
        "Smartphone Stand", "Laptop Cooling Pad", "Ergonomic Chair", "Standing Desk",
        "Desk Lamp LED", "Power Bank 20000mAh", "Wireless Charger", "Graphics Tablet",
        "VR Headset", "Smart Watch", "Fitness Tracker", "Drone 4K", "Action Camera",
        "Digital Camera", "Tripod", "Ring Light", "Microphone USB", "Audio Interface",
        "Studio Monitors", " MIDI Controller", "Synthesizer", "Electric Guitar",
        "Acoustic Guitar", "Ukulele", "Keyboard Piano", "Digital Piano", "Violin",
        "Cello", "Flute", "Saxophone", "Trumpet", "Drum Set", "Cajon", "Bongos",
        "Tambourine", "Maracas", "Harmonica", "Recorder", "Ocarina", "Kalimba",
        "Coffee Maker", "Espresso Machine", "Blender", "Juicer", "Air Fryer",
        "Rice Cooker", "Slow Cooker", "Pressure Cooker", "Toaster Oven", "Microwave",
        "Refrigerator", "Dishwasher", "Washing Machine", "Dryer", "Vacuum Cleaner",
        "Robot Vacuum", "Air Purifier", "Humidifier", "Dehumidifier", "Fan",
        "Heater", "Air Conditioner", "Thermostat", "Smart Bulb", "Smart Plug",
        "Security Camera", "Video Doorbell", "Smart Lock", "Smoke Detector",
        "CO Detector", "Water Leak Sensor", "Motion Sensor", "Door Sensor",
        "Window Sensor", "Smart Switch", "Smart Hub", "Router WiFi 6", "Mesh WiFi",
        "Network Switch", "NAS Storage", "External HDD 4TB", "SD Card 128GB",
        "USB Flash Drive 64GB", "HDMI Cable", "Ethernet Cable", "DisplayPort Cable",
        "USB-C Cable", "Lightning Cable", "Audio Cable", "Adapter USB-C to HDMI",
        "Docking Station", "Laptop Bag", "Backpack", "Sleeve", "Screen Protector",
        "Keyboard Cover", "Mouse Pad", "Cable Organizer", "Desk Mat", "Phone Case",
        "Tablet Case", "Laptop Stand", "Monitor Arm", "Cable Management Tray",
    ]

    PRODUCT_CATEGORIES = [
        "Electronics", "Computers", "Audio", "Musical Instruments", "Kitchen",
        "Home Appliances", "Smart Home", "Accessories", "Office", "Photography",
    ]

    CITIES = [
        "New York", "Los Angeles", "Chicago", "Houston", "Phoenix", "Philadelphia",
        "San Antonio", "San Diego", "Dallas", "San Jose", "Austin", "Jacksonville",
        "Fort Worth", "Columbus", "Charlotte", "San Francisco", "Indianapolis",
        "Seattle", "Denver", "Washington", "Boston", "El Paso", "Nashville",
        "Detroit", "Oklahoma City", "Portland", "Las Vegas", "Louisville", "Baltimore",
        "Milwaukee", "Albuquerque", "Tucson", "Fresno", "Mesa", "Sacramento",
        "Atlanta", "Kansas City", "Colorado Springs", "Omaha", "Raleigh",
        "Miami", "Long Beach", "Virginia Beach", "Oakland", "Minneapolis",
        "Tulsa", "Arlington", "Tampa", "New Orleans", "Wichita", "Cleveland",
        "Bakersfield", "Aurora", "Anaheim", "Honolulu", "Santa Ana", "Riverside",
        "Corpus Christi", "Lexington", "Stockton", "Henderson", "Saint Paul",
        "St. Louis", "Cincinnati", "Pittsburgh", "Greensboro", "Anchorage",
        "Plano", "Lincoln", "Orlando", "Irvine", "Newark", "Toledo", "Durham",
        "Chula Vista", "Fort Wayne", "Jersey City", "St. Petersburg", "Laredo",
        "Madison", "Chandler", "Buffalo", "Lubbock", "Scottsdale", "Reno",
        "Glendale", "Gilbert", "Winston-Salem", "North Las Vegas", "Norfolk",
        "Chesapeake", "Garland", "Irving", "Hialeah", "Fremont", "Boise",
        "Richmond", "Baton Rouge", "Spokane", "Des Moines", "Tacoma", "San Bernardino",
        "Modesto", "Fontana", "Santa Clarita", "Birmingham", "Oxnard", "Fayetteville",
        "Moreno Valley", "Rochester", "Glendale", "Huntington Beach", "Salt Lake City",
        "Grand Rapids", "Amarillo", "Yonkers", "Aurora", "Montgomery", "Akron",
        "Little Rock", "Huntsville", "Augusta", "Port St. Lucie", "Grand Prairie",
        "Columbus", "Tallahassee", "Overland Park", "Tempe", "McKinney", "Mobile",
        "Cape Coral", "Shreveport", "Frisco", "Knoxville", "Worcester", "Brownsville",
        "Vancouver", "Fort Lauderdale", "Sioux Falls", "Ontario", "Chattanooga",
        "Providence", "Newport News", "Rancho Cucamonga", "Santa Rosa", "Oceanside",
        "Salem", "Elk Grove", "Garden Grove", "Pembroke Pines", "Eugene", "Corona",
        "Cary", "Springfield", "Fort Collins", "Jackson", "Alexandria", "Hayward",
        "Lancaster", "Lakewood", "Clarksville", "Palmdale", "Salinas", "Springfield",
        "Hollywood", "Pasadena", "Sunnyvale", "Macon", "Pomona", "Escondido",
        "Killeen", "Naperville", "Joliet", "Bellevue", "Vallejo", "East Los Angeles",
        "Charleston", "Costa Mesa", "Concord", "Thornton", "Roseville", "Miami Gardens",
        "Midland", "Menifee", "Westminster", "Santa Maria", "Daly City", "Green Bay",
        "Boulder", "Palm Bay", "West Jordan", "Wichita Falls", "Gresham", "Lewisville",
        "Inglewood", "Cambridge", "Clearwater", "Waterbury", "Manchester", "Lafayette",
        "Lowell", "West Covina", "Billings", "Fairfield", "Murrieta", "High Point",
        "Broken Arrow", "Berkeley", "Richmond", "West Palm Beach", "Antioch",
        "Carlsbad", "Rialto", "Davenport", "Richardson", "Pueblo", "North Charleston",
        "Norwalk", "Elgin", "Provo", "Erie", "Murfreesboro", "Denton", "Beaumont",
        "Flint", "Surprise", "Lansing", "Beijing", "Shanghai", "Guangzhou", "Shenzhen",
        "Chengdu", "Hangzhou", "Wuhan", "Xi'an", "Nanjing", "Chongqing", "Tianjin",
        "Suzhou", "Dalian", "Qingdao", "Zhengzhou", "Changsha", "Shenyang", "Ningbo",
        "Kunming", "Fuzhou", "Wuxi", "Jinan", "Xiamen", "Harbin", "Changchun",
        "Hefei", "Shijiazhuang", "Nanning", "Guiyang", "Lanzhou", "Haikou",
        "Urumqi", "Hohhot", "Yinchuan", "Xining", "Lhasa", "Taiyuan", "Nanchang",
        "GuiLin", "Wenzhou", "Nantong", "Yantai", "Shaoxing", "Jiaxing", "Taizhou",
        "Jinhua", "Zhoushan", "Huzhou", "Quzhou", "Lishui", "Yangzhou", "Zhenjiang",
        "Taizhou", "Suqian", "Lianyungang", "Xuzhou", "Huaian", "Yancheng",
    ]

    @classmethod
    def random_name(cls) -> str:
        first = random.choice(cls.FIRST_NAMES)
        last = random.choice(cls.LAST_NAMES)
        return f"{first} {last}"

    @classmethod
    def random_email(cls, name: str) -> str:
        domains = ["gmail.com", "yahoo.com", "outlook.com", "qq.com", "163.com",
                   "hotmail.com", "icloud.com", "protonmail.com", "foxmail.com",
                   "aliyun.com", "sina.com", "sohu.com", "live.com", "me.com"]
        user = name.lower().replace(" ", ".").replace("'", "")
        # 添加随机数字避免重复
        user = f"{user}{random.randint(1, 9999)}"
        return f"{user}@{random.choice(domains)}"

    @classmethod
    def random_phone(cls) -> str:
        prefixes = ["138", "139", "137", "136", "135", "134", "150", "151",
                    "152", "157", "158", "159", "182", "183", "187", "188",
                    "130", "131", "132", "155", "156", "185", "186", "133",
                    "153", "180", "189", "177", "176", "173", "181", "178"]
        return random.choice(prefixes) + "".join(random.choices("0123456789", k=8))

    @classmethod
    def random_address(cls) -> str:
        streets = ["Main St", "Oak Ave", "Maple Rd", "Cedar Ln", "Pine St",
                   "Elm St", "Washington St", "Lake Shore Dr", "Park Ave",
                   "Broadway", "5th Ave", "Wall St", "Madison Ave", "Lexington Ave",
                   "Changan Ave", "Jianguo Rd", "Xidan St", "Wangfujing St",
                   "Nanjing Rd", "Huaihai Rd", "Binjiang Ave", "Renmin Rd"]
        return f"{random.randint(1, 9999)} {random.choice(streets)}, {random.choice(cls.CITIES)}"

    @classmethod
    def random_date(cls, start: datetime.date, end: datetime.date) -> datetime.date:
        delta = end - start
        return start + datetime.timedelta(days=random.randint(0, delta.days))

    @classmethod
    def generate_users(cls, count: int) -> List[Dict[str, Any]]:
        users = []
        today = datetime.date.today()
        for i in range(count):
            name = cls.random_name()
            birth_date = cls.random_date(datetime.date(1960, 1, 1), datetime.date(2005, 12, 31))
            users.append({
                "id": i + 1,
                "username": f"user_{i+1:04d}",
                "name": name,
                "email": cls.random_email(name),
                "phone": cls.random_phone(),
                "address": cls.random_address(),
                "birth_date": birth_date,
                "gender": random.choice(["M", "F", "O", None]),
                "status": random.choice(["active", "inactive", "pending", "banned"]),
                "created_at": datetime.datetime.now() - datetime.timedelta(days=random.randint(1, 365*3)),
                "updated_at": datetime.datetime.now() - datetime.timedelta(days=random.randint(0, 30)),
                "balance": round(random.uniform(0, 10000), 2),
                "points": random.randint(0, 100000),
                "is_vip": random.random() < 0.1,
            })
        return users

    @classmethod
    def generate_products(cls, count: int) -> List[Dict[str, Any]]:
        products = []
        for i in range(count):
            products.append({
                "id": i + 1,
                "sku": f"SKU-{random.randint(100000, 999999)}",
                "name": random.choice(cls.PRODUCT_NAMES),
                "category": random.choice(cls.PRODUCT_CATEGORIES),
                "price": round(random.uniform(5.99, 2999.99), 2),
                "cost": round(random.uniform(2.0, 1500.0), 2),
                "stock": random.randint(0, 10000),
                "description": f"High quality {random.choice(cls.PRODUCT_NAMES).lower()} with excellent performance.",
                "status": random.choice(["active", "discontinued", "out_of_stock", "pre_order"]),
                "created_at": datetime.datetime.now() - datetime.timedelta(days=random.randint(1, 365*2)),
                "updated_at": datetime.datetime.now() - datetime.timedelta(days=random.randint(0, 30)),
                "weight_kg": round(random.uniform(0.1, 50.0), 2),
                "rating": round(random.uniform(1.0, 5.0), 1),
                "review_count": random.randint(0, 5000),
                "tags": random.sample(["new", "sale", "hot", "limited", "featured"], k=random.randint(0, 3)),
            })
        return products

    @classmethod
    def generate_orders(cls, count: int, user_ids: List[int], product_ids: List[int]) -> List[Dict[str, Any]]:
        orders = []
        statuses = ["pending", "processing", "shipped", "delivered", "cancelled", "refunded"]
        for i in range(count):
            created_at = datetime.datetime.now() - datetime.timedelta(days=random.randint(0, 365*2), hours=random.randint(0, 23))
            status = random.choice(statuses)
            qty = random.randint(1, 10)
            price = round(random.uniform(5.99, 2999.99), 2)
            orders.append({
                "id": i + 1,
                "order_no": f"ORD-{datetime.datetime.now().year}-{random.randint(100000, 999999)}-{uuid.uuid4().hex[:6].upper()}",
                "user_id": random.choice(user_ids),
                "product_id": random.choice(product_ids),
                "quantity": qty,
                "unit_price": price,
                "total_amount": round(qty * price, 2),
                "status": status,
                "shipping_address": cls.random_address(),
                "created_at": created_at,
                "updated_at": created_at + datetime.timedelta(hours=random.randint(1, 72)) if status != "pending" else created_at,
                "paid_at": created_at + datetime.timedelta(minutes=random.randint(5, 60)) if status in ["processing", "shipped", "delivered"] else None,
                "shipped_at": created_at + datetime.timedelta(hours=random.randint(2, 48)) if status in ["shipped", "delivered"] else None,
                "delivered_at": created_at + datetime.timedelta(days=random.randint(1, 7)) if status == "delivered" else None,
                "notes": random.choice([None, "Please handle with care", "Gift wrap requested", "Call before delivery", "Leave at door"]),
            })
        return orders


# ============================================================================
# Connection Parser
# ============================================================================

def parse_uri(uri: str) -> Dict[str, Any]:
    """解析数据库 URI，正确处理密码中的 @ 符号"""
    import urllib.parse

    # Handle edge case: passwords with @ symbol
    # Find the last @ before host to split credentials and host
    # Pattern: scheme://[user[:password]@]host[:port][/dbname]
    rest = uri
    scheme = ""
    if "://" in rest:
        scheme, rest = rest.split("://", 1)

    # Find credentials part - everything before the last @ in the credentials section
    # But be careful: host might not have @ at all
    credentials = ""
    host_port_db = rest

    if "@" in rest:
        # Split from the right for the last @
        # But we need to find where credentials end and host begins
        # Heuristic: the host part starts with an alphanumeric/IPv4/IPv6 char
        # So we split at the last @ before a known host-like pattern
        parts = rest.rsplit("@", 1)
        # Check if the second part looks like a host (contains : or . or is alphanumeric)
        if len(parts) == 2:
            credentials, host_port_db = parts

    username = ""
    password = ""
    if credentials:
        if ":" in credentials:
            username, password = credentials.split(":", 1)
        else:
            username = credentials

    # Parse host:port/db from remaining
    host = "localhost"
    port = 0
    database = ""

    if "/" in host_port_db:
        host_port, database = host_port_db.split("/", 1)
    else:
        host_port = host_port_db

    if ":" in host_port:
        # IPv6 handling
        if host_port.startswith("["):
            end_bracket = host_port.find("]")
            if end_bracket != -1:
                host = host_port[:end_bracket + 1]
                port_str = host_port[end_bracket + 1:]
                if port_str.startswith(":"):
                    port = int(port_str[1:])
            else:
                host = host_port
        else:
            host_part, port_str = host_port.rsplit(":", 1)
            host = host_part
            try:
                port = int(port_str)
            except ValueError:
                pass
    else:
        host = host_port

    # Unquote username/password
    username = urllib.parse.unquote(username)
    password = urllib.parse.unquote(password)

    return {
        "scheme": scheme,
        "username": username,
        "password": password,
        "host": host,
        "port": port,
        "database": database,
    }


def load_connections() -> List[Dict[str, Any]]:
    """从 YAML 文件加载数据库连接配置"""
    with open(CONNECTIONS_FILE, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f)

    connections = []
    for server_name, server_info in data.get("servers", {}).items():
        for db in server_info.get("databases", []):
            conn_info = parse_uri(db["uri"])
            conn_info.update({
                "name": db["name"],
                "type": db["type"],
                "note": db.get("note", ""),
                "server": server_name,
                "ssl": db.get("ssl", False),
            })
            connections.append(conn_info)
    return connections


# ============================================================================
# Database Inserters
# ============================================================================

class BaseInserter:
    def __init__(self, conn_info: Dict[str, Any]):
        self.info = conn_info
        self.name = conn_info["name"]
        self.type = conn_info["type"]

    def connect(self):
        raise NotImplementedError

    def create_test_db(self):
        raise NotImplementedError

    def create_tables(self):
        raise NotImplementedError

    def insert_data(self, users, products, orders):
        raise NotImplementedError

    def cleanup(self):
        raise NotImplementedError

    def run(self):
        print(f"\n{'='*60}")
        print(f"Processing: {self.name} ({self.type})")
        print(f"{'='*60}")
        try:
            self.connect()
            self.create_test_db()
            self.create_tables()
            users = DataGenerator.generate_users(TEST_DATA_COUNT["users"])
            products = DataGenerator.generate_products(TEST_DATA_COUNT["products"])
            orders = DataGenerator.generate_orders(
                TEST_DATA_COUNT["orders"],
                [u["id"] for u in users],
                [p["id"] for p in products]
            )
            self.insert_data(users, products, orders)
            print(f"✅ {self.name}: Successfully inserted {len(users)} users, {len(products)} products, {len(orders)} orders")
        except Exception as e:
            print(f"❌ {self.name}: Error - {e}")
            import traceback
            traceback.print_exc()
        finally:
            self.cleanup()


class MySQLInserter(BaseInserter):
    """MySQL / Doris 数据插入器"""

    def connect(self):
        import ssl as ssl_mod
        connect_kwargs = {
            "host": self.info["host"],
            "port": self.info["port"],
            "user": self.info["username"],
            "password": self.info["password"],
            "charset": "utf8mb4",
            "connect_timeout": 10,
        }
        if self.info.get("ssl"):
            ctx = ssl_mod.create_default_context()
            ctx.check_hostname = False
            ctx.verify_mode = ssl_mod.CERT_NONE
            connect_kwargs["ssl"] = ctx
        self.conn = pymysql.connect(**connect_kwargs)
        self.cursor = self.conn.cursor()

    def create_test_db(self):
        # For Doris, avoid creating database with complex statements
        self.cursor.execute(f"DROP DATABASE IF EXISTS `{TEST_DB_NAME}`")
        self.cursor.execute(f"CREATE DATABASE `{TEST_DB_NAME}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci")
        self.cursor.execute(f"USE `{TEST_DB_NAME}`")
        self.conn.commit()

    def create_tables(self):
        # Users table
        self.cursor.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id INT PRIMARY KEY,
                username VARCHAR(50) NOT NULL UNIQUE,
                name VARCHAR(100) NOT NULL,
                email VARCHAR(100) NOT NULL,
                phone VARCHAR(20),
                address VARCHAR(255),
                birth_date DATE,
                gender CHAR(1),
                status VARCHAR(20) DEFAULT 'active',
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                balance DECIMAL(12,2) DEFAULT 0.00,
                points INT DEFAULT 0,
                is_vip BOOLEAN DEFAULT FALSE,
                INDEX idx_status (status),
                INDEX idx_email (email),
                INDEX idx_created_at (created_at)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """)

        # Products table
        self.cursor.execute("""
            CREATE TABLE IF NOT EXISTS products (
                id INT PRIMARY KEY,
                sku VARCHAR(20) NOT NULL UNIQUE,
                name VARCHAR(200) NOT NULL,
                category VARCHAR(50),
                price DECIMAL(10,2) NOT NULL,
                cost DECIMAL(10,2),
                stock INT DEFAULT 0,
                description TEXT,
                status VARCHAR(20) DEFAULT 'active',
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                weight_kg DECIMAL(6,2),
                rating DECIMAL(2,1),
                review_count INT DEFAULT 0,
                tags JSON,
                INDEX idx_category (category),
                INDEX idx_status (status),
                INDEX idx_price (price)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """)

        # Orders table
        self.cursor.execute("""
            CREATE TABLE IF NOT EXISTS orders (
                id INT PRIMARY KEY,
                order_no VARCHAR(30) NOT NULL UNIQUE,
                user_id INT NOT NULL,
                product_id INT NOT NULL,
                quantity INT NOT NULL DEFAULT 1,
                unit_price DECIMAL(10,2) NOT NULL,
                total_amount DECIMAL(12,2) NOT NULL,
                status VARCHAR(20) DEFAULT 'pending',
                shipping_address VARCHAR(255),
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                paid_at DATETIME,
                shipped_at DATETIME,
                delivered_at DATETIME,
                notes TEXT,
                INDEX idx_user_id (user_id),
                INDEX idx_status (status),
                INDEX idx_created_at (created_at),
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
                FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """)
        self.conn.commit()

    def insert_data(self, users, products, orders):
        # Insert users
        for user in users:
            self.cursor.execute("""
                INSERT INTO users (id, username, name, email, phone, address, birth_date,
                    gender, status, created_at, updated_at, balance, points, is_vip)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            """, (
                user["id"], user["username"], user["name"], user["email"],
                user["phone"], user["address"], user["birth_date"],
                user["gender"], user["status"], user["created_at"], user["updated_at"],
                user["balance"], user["points"], user["is_vip"]
            ))

        # Insert products
        for product in products:
            self.cursor.execute("""
                INSERT INTO products (id, sku, name, category, price, cost, stock,
                    description, status, created_at, updated_at, weight_kg, rating, review_count, tags)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            """, (
                product["id"], product["sku"], product["name"], product["category"],
                product["price"], product["cost"], product["stock"], product["description"],
                product["status"], product["created_at"], product["updated_at"],
                product["weight_kg"], product["rating"], product["review_count"],
                json.dumps(product["tags"], ensure_ascii=False)
            ))

        # Insert orders
        for order in orders:
            self.cursor.execute("""
                INSERT INTO orders (id, order_no, user_id, product_id, quantity, unit_price,
                    total_amount, status, shipping_address, created_at, updated_at,
                    paid_at, shipped_at, delivered_at, notes)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            """, (
                order["id"], order["order_no"], order["user_id"], order["product_id"],
                order["quantity"], order["unit_price"], order["total_amount"],
                order["status"], order["shipping_address"], order["created_at"],
                order["updated_at"], order["paid_at"], order["shipped_at"],
                order["delivered_at"], order["notes"]
            ))
        self.conn.commit()

    def cleanup(self):
        try:
            if hasattr(self, "cursor") and self.cursor:
                self.cursor.close()
            if hasattr(self, "conn") and self.conn:
                self.conn.close()
        except Exception:
            pass


class DorisInserter(MySQLInserter):
    """Doris 数据插入器 - 使用 Doris 特定的建表语法"""

    def create_test_db(self):
        self.cursor.execute(f"DROP DATABASE IF EXISTS `{TEST_DB_NAME}`")
        self.cursor.execute(f"CREATE DATABASE `{TEST_DB_NAME}`")
        self.cursor.execute(f"USE `{TEST_DB_NAME}`")
        self.conn.commit()

    def create_tables(self):
        # Doris uses DUPLICATE KEY model for flexibility
        self.cursor.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id INT,
                username VARCHAR(50),
                name VARCHAR(100),
                email VARCHAR(100),
                phone VARCHAR(20),
                address VARCHAR(255),
                birth_date DATE,
                gender CHAR(1),
                status VARCHAR(20),
                created_at DATETIME,
                updated_at DATETIME,
                balance DECIMAL(12,2),
                points INT,
                is_vip BOOLEAN
            )
            DUPLICATE KEY(id)
            DISTRIBUTED BY HASH(id) BUCKETS 10
            PROPERTIES ("replication_num" = "1")
        """)

        self.cursor.execute("""
            CREATE TABLE IF NOT EXISTS products (
                id INT,
                sku VARCHAR(20),
                name VARCHAR(200),
                category VARCHAR(50),
                price DECIMAL(10,2),
                cost DECIMAL(10,2),
                stock INT,
                description STRING,
                status VARCHAR(20),
                created_at DATETIME,
                updated_at DATETIME,
                weight_kg DECIMAL(6,2),
                rating DECIMAL(2,1),
                review_count INT,
                tags STRING
            )
            DUPLICATE KEY(id)
            DISTRIBUTED BY HASH(id) BUCKETS 10
            PROPERTIES ("replication_num" = "1")
        """)

        self.cursor.execute("""
            CREATE TABLE IF NOT EXISTS orders (
                id INT,
                order_no VARCHAR(30),
                user_id INT,
                product_id INT,
                quantity INT,
                unit_price DECIMAL(10,2),
                total_amount DECIMAL(12,2),
                status VARCHAR(20),
                shipping_address VARCHAR(255),
                created_at DATETIME,
                updated_at DATETIME,
                paid_at DATETIME,
                shipped_at DATETIME,
                delivered_at DATETIME,
                notes STRING
            )
            DUPLICATE KEY(id)
            DISTRIBUTED BY HASH(id) BUCKETS 10
            PROPERTIES ("replication_num" = "1")
        """)
        self.conn.commit()


class PostgreSQLInserter(BaseInserter):
    """PostgreSQL 数据插入器"""

    def connect(self):
        self.conn = psycopg2.connect(
            host=self.info["host"],
            port=self.info["port"],
            user=self.info["username"],
            password=self.info["password"],
            database=self.info["database"] or "postgres",
            connect_timeout=10,
        )
        self.conn.autocommit = True
        self.cursor = self.conn.cursor()

    def create_test_db(self):
        # Check if db exists and drop/create
        self.cursor.execute(f"SELECT 1 FROM pg_database WHERE datname = '{TEST_DB_NAME}'")
        if self.cursor.fetchone():
            # Terminate connections first
            self.cursor.execute(f"""
                SELECT pg_terminate_backend(pid)
                FROM pg_stat_activity
                WHERE datname = '{TEST_DB_NAME}' AND pid <> pg_backend_pid()
            """)
            self.cursor.execute(f"DROP DATABASE {TEST_DB_NAME}")
        self.cursor.execute(f"CREATE DATABASE {TEST_DB_NAME} WITH ENCODING = 'UTF8'")
        self.conn.autocommit = False
        self.cursor.close()
        self.conn.close()

        # Reconnect to test database
        self.conn = psycopg2.connect(
            host=self.info["host"],
            port=self.info["port"],
            user=self.info["username"],
            password=self.info["password"],
            database=TEST_DB_NAME,
        )
        self.cursor = self.conn.cursor()

    def create_tables(self):
        self.cursor.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY,
                username VARCHAR(50) NOT NULL UNIQUE,
                name VARCHAR(100) NOT NULL,
                email VARCHAR(100) NOT NULL,
                phone VARCHAR(20),
                address VARCHAR(255),
                birth_date DATE,
                gender CHAR(1),
                status VARCHAR(20) DEFAULT 'active',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                balance NUMERIC(12,2) DEFAULT 0.00,
                points INTEGER DEFAULT 0,
                is_vip BOOLEAN DEFAULT FALSE
            )
        """)
        self.cursor.execute("CREATE INDEX idx_users_status ON users(status)")
        self.cursor.execute("CREATE INDEX idx_users_email ON users(email)")
        self.cursor.execute("CREATE INDEX idx_users_created_at ON users(created_at)")

        self.cursor.execute("""
            CREATE TABLE IF NOT EXISTS products (
                id INTEGER PRIMARY KEY,
                sku VARCHAR(20) NOT NULL UNIQUE,
                name VARCHAR(200) NOT NULL,
                category VARCHAR(50),
                price NUMERIC(10,2) NOT NULL,
                cost NUMERIC(10,2),
                stock INTEGER DEFAULT 0,
                description TEXT,
                status VARCHAR(20) DEFAULT 'active',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                weight_kg NUMERIC(6,2),
                rating NUMERIC(2,1),
                review_count INTEGER DEFAULT 0,
                tags JSONB
            )
        """)
        self.cursor.execute("CREATE INDEX idx_products_category ON products(category)")
        self.cursor.execute("CREATE INDEX idx_products_status ON products(status)")
        self.cursor.execute("CREATE INDEX idx_products_price ON products(price)")

        self.cursor.execute("""
            CREATE TABLE IF NOT EXISTS orders (
                id INTEGER PRIMARY KEY,
                order_no VARCHAR(30) NOT NULL UNIQUE,
                user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
                quantity INTEGER NOT NULL DEFAULT 1,
                unit_price NUMERIC(10,2) NOT NULL,
                total_amount NUMERIC(12,2) NOT NULL,
                status VARCHAR(20) DEFAULT 'pending',
                shipping_address VARCHAR(255),
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                paid_at TIMESTAMP,
                shipped_at TIMESTAMP,
                delivered_at TIMESTAMP,
                notes TEXT
            )
        """)
        self.cursor.execute("CREATE INDEX idx_orders_user_id ON orders(user_id)")
        self.cursor.execute("CREATE INDEX idx_orders_status ON orders(status)")
        self.cursor.execute("CREATE INDEX idx_orders_created_at ON orders(created_at)")
        self.conn.commit()

    def insert_data(self, users, products, orders):
        from psycopg2.extras import execute_values

        # Insert users
        user_values = [
            (u["id"], u["username"], u["name"], u["email"], u["phone"], u["address"],
             u["birth_date"], u["gender"], u["status"], u["created_at"], u["updated_at"],
             u["balance"], u["points"], u["is_vip"]) for u in users
        ]
        execute_values(self.cursor, """
            INSERT INTO users (id, username, name, email, phone, address, birth_date,
                gender, status, created_at, updated_at, balance, points, is_vip)
            VALUES %s
        """, user_values)

        # Insert products
        product_values = [
            (p["id"], p["sku"], p["name"], p["category"], p["price"], p["cost"],
             p["stock"], p["description"], p["status"], p["created_at"], p["updated_at"],
             p["weight_kg"], p["rating"], p["review_count"], json.dumps(p["tags"]))
            for p in products
        ]
        execute_values(self.cursor, """
            INSERT INTO products (id, sku, name, category, price, cost, stock,
                description, status, created_at, updated_at, weight_kg, rating, review_count, tags)
            VALUES %s
        """, product_values)

        # Insert orders
        order_values = [
            (o["id"], o["order_no"], o["user_id"], o["product_id"], o["quantity"],
             o["unit_price"], o["total_amount"], o["status"], o["shipping_address"],
             o["created_at"], o["updated_at"], o["paid_at"], o["shipped_at"],
             o["delivered_at"], o["notes"]) for o in orders
        ]
        execute_values(self.cursor, """
            INSERT INTO orders (id, order_no, user_id, product_id, quantity, unit_price,
                total_amount, status, shipping_address, created_at, updated_at,
                paid_at, shipped_at, delivered_at, notes)
            VALUES %s
        """, order_values)

        self.conn.commit()

    def cleanup(self):
        try:
            if hasattr(self, "cursor") and self.cursor:
                self.cursor.close()
            if hasattr(self, "conn") and self.conn:
                self.conn.close()
        except Exception:
            pass


class MongoDBInserter(BaseInserter):
    """MongoDB 数据插入器"""

    def connect(self):
        auth_part = ""
        if self.info["username"] and self.info["password"]:
            from urllib.parse import quote_plus
            user = quote_plus(self.info["username"])
            pwd = quote_plus(self.info["password"])
            auth_part = f"{user}:{pwd}@"
        uri = f"mongodb://{auth_part}{self.info['host']}:{self.info['port']}"
        self.client = MongoClient(uri, serverSelectionTimeoutMS=10000)
        self.db = self.client[TEST_DB_NAME]

    def create_test_db(self):
        # MongoDB creates db on first insert, just clean up
        self.client.drop_database(TEST_DB_NAME)
        self.db = self.client[TEST_DB_NAME]

    def create_tables(self):
        # Create collections and indexes
        self.db.users.create_index("id", unique=True)
        self.db.users.create_index("email", unique=True)
        self.db.users.create_index("username", unique=True)
        self.db.users.create_index("status")
        self.db.users.create_index("created_at")

        self.db.products.create_index("id", unique=True)
        self.db.products.create_index("sku", unique=True)
        self.db.products.create_index("category")
        self.db.products.create_index("status")

        self.db.orders.create_index("id", unique=True)
        self.db.orders.create_index("order_no", unique=True)
        self.db.orders.create_index("user_id")
        self.db.orders.create_index("status")
        self.db.orders.create_index("created_at")

    def insert_data(self, users, products, orders):
        # Convert datetime to proper format
        def fix_dates(doc):
            for k, v in doc.items():
                if isinstance(v, datetime.date) and not isinstance(v, datetime.datetime):
                    doc[k] = datetime.datetime.combine(v, datetime.time())
            return doc

        self.db.users.insert_many([fix_dates(u) for u in users])
        self.db.products.insert_many([fix_dates(p) for p in products])
        self.db.orders.insert_many([fix_dates(o) for o in orders])

    def cleanup(self):
        try:
            if hasattr(self, "client") and self.client:
                self.client.close()
        except Exception:
            pass


class RedisInserter(BaseInserter):
    """Redis 数据插入器"""

    def connect(self):
        self.client = redis_lib.Redis(
            host=self.info["host"],
            port=self.info["port"],
            password=self.info["password"] or None,
            db=15,  # Use db 15 for tests
            decode_responses=True,
            socket_connect_timeout=10,
        )
        self.client.ping()

    def create_test_db(self):
        self.client.flushdb()

    def create_tables(self):
        pass  # Redis is schemaless

    def insert_data(self, users, products, orders):
        pipe = self.client.pipeline()

        # Store users as hashes
        for user in users:
            key = f"user:{user['id']}"
            pipe.hset(key, mapping={
                "id": user["id"],
                "username": user["username"],
                "name": user["name"],
                "email": user["email"],
                "phone": user["phone"] or "",
                "address": user["address"] or "",
                "status": user["status"],
                "balance": str(user["balance"]),
                "points": user["points"],
                "is_vip": "1" if user["is_vip"] else "0",
            })
            pipe.sadd(f"users:status:{user['status']}", user["id"])

        # Store products as hashes
        for product in products:
            key = f"product:{product['id']}"
            pipe.hset(key, mapping={
                "id": product["id"],
                "sku": product["sku"],
                "name": product["name"],
                "category": product["category"],
                "price": str(product["price"]),
                "stock": product["stock"],
                "status": product["status"],
                "rating": str(product["rating"]),
            })
            pipe.sadd(f"products:category:{product['category']}", product["id"])
            pipe.sadd(f"products:status:{product['status']}", product["id"])

        # Store orders as hashes + sorted sets
        for order in orders:
            key = f"order:{order['id']}"
            pipe.hset(key, mapping={
                "id": order["id"],
                "order_no": order["order_no"],
                "user_id": order["user_id"],
                "product_id": order["product_id"],
                "quantity": order["quantity"],
                "total_amount": str(order["total_amount"]),
                "status": order["status"],
                "shipping_address": order["shipping_address"] or "",
            })
            pipe.sadd(f"orders:status:{order['status']}", order["id"])
            pipe.sadd(f"user:{order['user_id']}:orders", order["id"])
            # Add to sorted set by amount for leaderboard
            pipe.zadd("orders:by_amount", {order["id"]: order["total_amount"]})
            # Add to sorted set by time
            ts = order["created_at"].timestamp() if order["created_at"] else 0
            pipe.zadd("orders:by_time", {order["id"]: ts})

        # Add some lists for recent items
        recent_user_ids = [str(u["id"]) for u in users[:20]]
        pipe.lpush("recent:users", *recent_user_ids)
        pipe.ltrim("recent:users", 0, 99)

        recent_order_ids = [str(o["id"]) for o in sorted(orders, key=lambda x: x["created_at"], reverse=True)[:20]]
        pipe.lpush("recent:orders", *recent_order_ids)
        pipe.ltrim("recent:orders", 0, 99)

        # String values for stats
        pipe.set("stats:total_users", len(users))
        pipe.set("stats:total_products", len(products))
        pipe.set("stats:total_orders", len(orders))
        pipe.set("stats:generated_at", datetime.datetime.now().isoformat())

        pipe.execute()

    def cleanup(self):
        try:
            if hasattr(self, "client") and self.client:
                self.client.close()
        except Exception:
            pass


class SQLServerInserter(BaseInserter):
    """SQL Server 数据插入器"""

    def connect(self):
        # Try pymssql first (works without ODBC drivers), fallback to pyodbc
        self._use_pymssql = False
        try:
            import pymssql
            self.conn = pymssql.connect(
                server=self.info["host"],
                port=self.info["port"],
                user=self.info["username"],
                password=self.info["password"],
                database="master",
                login_timeout=10,
            )
            self.cursor = self.conn.cursor()
            self._use_pymssql = True
            return
        except Exception:
            pass

        conn_str = (
            f"DRIVER={{ODBC Driver 17 for SQL Server}};"
            f"SERVER={self.info['host']},{self.info['port']};"
            f"DATABASE=master;"
            f"UID={self.info['username']};"
            f"PWD={self.info['password']};"
            f"Timeout=10;"
        )
        self.conn = pyodbc.connect(conn_str, autocommit=True)
        self.cursor = self.conn.cursor()

    def create_test_db(self):
        if self._use_pymssql:
            # pymssql needs autocommit for DDL
            self.conn.autocommit(True)

        self.cursor.execute(f"""
            IF EXISTS (SELECT name FROM sys.databases WHERE name = N'{TEST_DB_NAME}')
            BEGIN
                ALTER DATABASE [{TEST_DB_NAME}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
                DROP DATABASE [{TEST_DB_NAME}];
            END
        """)
        self.cursor.execute(f"CREATE DATABASE [{TEST_DB_NAME}]")
        if not self._use_pymssql:
            self.conn.autocommit = False
        else:
            self.conn.autocommit(False)
        self.cursor.execute(f"USE [{TEST_DB_NAME}]")

    def create_tables(self):
        self.cursor.execute("""
            CREATE TABLE users (
                id INT PRIMARY KEY,
                username NVARCHAR(50) NOT NULL UNIQUE,
                name NVARCHAR(100) NOT NULL,
                email NVARCHAR(100) NOT NULL,
                phone NVARCHAR(20),
                address NVARCHAR(500),
                birth_date DATE,
                gender NCHAR(1),
                status NVARCHAR(20) DEFAULT 'active',
                created_at DATETIME2 DEFAULT GETDATE(),
                updated_at DATETIME2 DEFAULT GETDATE(),
                balance DECIMAL(12,2) DEFAULT 0.00,
                points INT DEFAULT 0,
                is_vip BIT DEFAULT 0
            )
        """)
        self.cursor.execute("CREATE INDEX idx_users_status ON users(status)")
        self.cursor.execute("CREATE INDEX idx_users_email ON users(email)")

        self.cursor.execute("""
            CREATE TABLE products (
                id INT PRIMARY KEY,
                sku NVARCHAR(20) NOT NULL UNIQUE,
                name NVARCHAR(200) NOT NULL,
                category NVARCHAR(50),
                price DECIMAL(10,2) NOT NULL,
                cost DECIMAL(10,2),
                stock INT DEFAULT 0,
                description NVARCHAR(2000),
                status NVARCHAR(20) DEFAULT 'active',
                created_at DATETIME2 DEFAULT GETDATE(),
                updated_at DATETIME2 DEFAULT GETDATE(),
                weight_kg DECIMAL(6,2),
                rating DECIMAL(2,1),
                review_count INT DEFAULT 0,
                tags NVARCHAR(1000)
            )
        """)
        self.cursor.execute("CREATE INDEX idx_products_category ON products(category)")
        self.cursor.execute("CREATE INDEX idx_products_status ON products(status)")

        self.cursor.execute("""
            CREATE TABLE orders (
                id INT PRIMARY KEY,
                order_no NVARCHAR(30) NOT NULL UNIQUE,
                user_id INT NOT NULL REFERENCES users(id),
                product_id INT NOT NULL REFERENCES products(id),
                quantity INT NOT NULL DEFAULT 1,
                unit_price DECIMAL(10,2) NOT NULL,
                total_amount DECIMAL(12,2) NOT NULL,
                status NVARCHAR(20) DEFAULT 'pending',
                shipping_address NVARCHAR(500),
                created_at DATETIME2 DEFAULT GETDATE(),
                updated_at DATETIME2 DEFAULT GETDATE(),
                paid_at DATETIME2,
                shipped_at DATETIME2,
                delivered_at DATETIME2,
                notes NVARCHAR(2000)
            )
        """)
        self.cursor.execute("CREATE INDEX idx_orders_user_id ON orders(user_id)")
        self.cursor.execute("CREATE INDEX idx_orders_status ON orders(status)")
        self.conn.commit()

    def insert_data(self, users, products, orders):
        # pymssql uses %s placeholders, pyodbc uses ?
        ph = "%s" if self._use_pymssql else "?"
        for user in users:
            self.cursor.execute(f"""
                INSERT INTO users (id, username, name, email, phone, address, birth_date,
                    gender, status, created_at, updated_at, balance, points, is_vip)
                VALUES ({','.join([ph]*14)})
            """, (
                user["id"], user["username"], user["name"], user["email"],
                user["phone"], user["address"], user["birth_date"],
                user["gender"], user["status"], user["created_at"], user["updated_at"],
                user["balance"], user["points"], 1 if user["is_vip"] else 0
            ))

        for product in products:
            self.cursor.execute(f"""
                INSERT INTO products (id, sku, name, category, price, cost, stock,
                    description, status, created_at, updated_at, weight_kg, rating, review_count, tags)
                VALUES ({','.join([ph]*15)})
            """, (
                product["id"], product["sku"], product["name"], product["category"],
                product["price"], product["cost"], product["stock"], product["description"],
                product["status"], product["created_at"], product["updated_at"],
                product["weight_kg"], product["rating"], product["review_count"],
                json.dumps(product["tags"])
            ))

        for order in orders:
            self.cursor.execute(f"""
                INSERT INTO orders (id, order_no, user_id, product_id, quantity, unit_price,
                    total_amount, status, shipping_address, created_at, updated_at,
                    paid_at, shipped_at, delivered_at, notes)
                VALUES ({','.join([ph]*15)})
            """, (
                order["id"], order["order_no"], order["user_id"], order["product_id"],
                order["quantity"], order["unit_price"], order["total_amount"],
                order["status"], order["shipping_address"], order["created_at"],
                order["updated_at"], order["paid_at"], order["shipped_at"],
                order["delivered_at"], order["notes"]
            ))
        self.conn.commit()

    def cleanup(self):
        try:
            if hasattr(self, "cursor") and self.cursor:
                self.cursor.close()
            if hasattr(self, "conn") and self.conn:
                self.conn.close()
        except Exception:
            pass


class OracleInserter(BaseInserter):
    """Oracle 数据插入器"""

    def connect(self):
        dsn = oracledb.makedsn(self.info["host"], self.info["port"], sid=self.info.get("database", "FREE"))
        self.conn = oracledb.connect(
            user=self.info["username"],
            password=self.info["password"],
            dsn=dsn,
        )
        self.cursor = self.conn.cursor()

    def create_test_db(self):
        # Oracle doesn't have "create database" like MySQL. Use a test user/schema instead.
        # Check if we're in CDB mode (Oracle 12c+ requires C## prefix for common users)
        self.cursor.execute("SELECT CDB FROM V$DATABASE")
        row = self.cursor.fetchone()
        is_cdb = row and row[0] == "YES"

        self.test_user = "C##DBMASTER_TEST" if is_cdb else "DBMASTER_TEST"
        try:
            self.cursor.execute(f"DROP USER {self.test_user} CASCADE")
        except oracledb.DatabaseError:
            pass
        self.cursor.execute(f"CREATE USER {self.test_user} IDENTIFIED BY TestPass123")
        self.cursor.execute(f"GRANT CREATE SESSION TO {self.test_user}")
        self.cursor.execute(f"GRANT CREATE TABLE TO {self.test_user}")
        self.cursor.execute(f"GRANT CREATE SEQUENCE TO {self.test_user}")
        self.cursor.execute(f"GRANT CREATE TRIGGER TO {self.test_user}")
        self.cursor.execute(f"GRANT UNLIMITED TABLESPACE TO {self.test_user}")
        self.conn.commit()

        # Reconnect as test user
        dsn = oracledb.makedsn(self.info["host"], self.info["port"], sid=self.info.get("database", "FREE"))
        self.conn.close()
        self.conn = oracledb.connect(user=self.test_user, password="TestPass123", dsn=dsn)
        self.cursor = self.conn.cursor()

    def create_tables(self):
        # Oracle uses DEFAULT SYSTIMESTAMP instead of DEFAULT CURRENT_TIMESTAMP
        self.cursor.execute("""
            CREATE TABLE users (
                id NUMBER(10) PRIMARY KEY,
                username VARCHAR2(50) NOT NULL UNIQUE,
                name VARCHAR2(100) NOT NULL,
                email VARCHAR2(100) NOT NULL,
                phone VARCHAR2(20),
                address VARCHAR2(500),
                birth_date DATE,
                gender CHAR(1),
                status VARCHAR2(20) DEFAULT 'active',
                created_at TIMESTAMP DEFAULT SYSTIMESTAMP,
                updated_at TIMESTAMP DEFAULT SYSTIMESTAMP,
                balance NUMBER(12,2) DEFAULT 0,
                points NUMBER(10) DEFAULT 0,
                is_vip NUMBER(1) DEFAULT 0
            )
        """)
        self.cursor.execute("CREATE INDEX idx_users_status ON users(status)")

        self.cursor.execute("""
            CREATE TABLE products (
                id NUMBER(10) PRIMARY KEY,
                sku VARCHAR2(20) NOT NULL UNIQUE,
                name VARCHAR2(200) NOT NULL,
                category VARCHAR2(50),
                price NUMBER(10,2) NOT NULL,
                cost NUMBER(10,2),
                stock NUMBER(10) DEFAULT 0,
                description CLOB,
                status VARCHAR2(20) DEFAULT 'active',
                created_at TIMESTAMP DEFAULT SYSTIMESTAMP,
                updated_at TIMESTAMP DEFAULT SYSTIMESTAMP,
                weight_kg NUMBER(6,2),
                rating NUMBER(2,1),
                review_count NUMBER(10) DEFAULT 0,
                tags CLOB
            )
        """)
        self.cursor.execute("CREATE INDEX idx_products_category ON products(category)")

        self.cursor.execute("""
            CREATE TABLE orders (
                id NUMBER(10) PRIMARY KEY,
                order_no VARCHAR2(30) NOT NULL UNIQUE,
                user_id NUMBER(10) NOT NULL,
                product_id NUMBER(10) NOT NULL,
                quantity NUMBER(10) DEFAULT 1 NOT NULL,
                unit_price NUMBER(10,2) NOT NULL,
                total_amount NUMBER(12,2) NOT NULL,
                status VARCHAR2(20) DEFAULT 'pending',
                shipping_address VARCHAR2(500),
                created_at TIMESTAMP DEFAULT SYSTIMESTAMP,
                updated_at TIMESTAMP DEFAULT SYSTIMESTAMP,
                paid_at TIMESTAMP,
                shipped_at TIMESTAMP,
                delivered_at TIMESTAMP,
                notes CLOB
            )
        """)
        self.cursor.execute("CREATE INDEX idx_orders_user_id ON orders(user_id)")
        self.cursor.execute("CREATE INDEX idx_orders_status ON orders(status)")
        self.conn.commit()

    def insert_data(self, users, products, orders):
        for user in users:
            self.cursor.execute("""
                INSERT INTO users (id, username, name, email, phone, address, birth_date,
                    gender, status, created_at, updated_at, balance, points, is_vip)
                VALUES (:1, :2, :3, :4, :5, :6, :7, :8, :9, :10, :11, :12, :13, :14)
            """, (
                user["id"], user["username"], user["name"], user["email"],
                user["phone"], user["address"], user["birth_date"],
                user["gender"], user["status"], user["created_at"], user["updated_at"],
                user["balance"], user["points"], 1 if user["is_vip"] else 0
            ))

        for product in products:
            self.cursor.execute("""
                INSERT INTO products (id, sku, name, category, price, cost, stock,
                    description, status, created_at, updated_at, weight_kg, rating, review_count, tags)
                VALUES (:1, :2, :3, :4, :5, :6, :7, :8, :9, :10, :11, :12, :13, :14, :15)
            """, (
                product["id"], product["sku"], product["name"], product["category"],
                product["price"], product["cost"], product["stock"], product["description"],
                product["status"], product["created_at"], product["updated_at"],
                product["weight_kg"], product["rating"], product["review_count"],
                json.dumps(product["tags"])
            ))

        for order in orders:
            self.cursor.execute("""
                INSERT INTO orders (id, order_no, user_id, product_id, quantity, unit_price,
                    total_amount, status, shipping_address, created_at, updated_at,
                    paid_at, shipped_at, delivered_at, notes)
                VALUES (:1, :2, :3, :4, :5, :6, :7, :8, :9, :10, :11, :12, :13, :14, :15)
            """, (
                order["id"], order["order_no"], order["user_id"], order["product_id"],
                order["quantity"], order["unit_price"], order["total_amount"],
                order["status"], order["shipping_address"], order["created_at"],
                order["updated_at"], order["paid_at"], order["shipped_at"],
                order["delivered_at"], order["notes"]
            ))
        self.conn.commit()

    def cleanup(self):
        try:
            if hasattr(self, "cursor") and self.cursor:
                self.cursor.close()
            if hasattr(self, "conn") and self.conn:
                self.conn.close()
        except Exception:
            pass


class ElasticsearchInserter(BaseInserter):
    """Elasticsearch 数据插入器"""

    def connect(self):
        self.es = Elasticsearch(
            [f"https://{self.info['host']}:{self.info['port']}"],
            basic_auth=(self.info["username"], self.info["password"]),
            verify_certs=False,
            request_timeout=30,
        )

    def create_test_db(self):
        # Delete existing indices
        for index in ["dbmaster_test_users", "dbmaster_test_products", "dbmaster_test_orders"]:
            if self.es.indices.exists(index=index):
                self.es.indices.delete(index=index)

    def create_tables(self):
        # Users index
        self.es.indices.create(index="dbmaster_test_users", body={
            "settings": {"number_of_shards": 1, "number_of_replicas": 0},
            "mappings": {
                "properties": {
                    "id": {"type": "integer"},
                    "username": {"type": "keyword"},
                    "name": {"type": "text"},
                    "email": {"type": "keyword"},
                    "phone": {"type": "keyword"},
                    "address": {"type": "text"},
                    "birth_date": {"type": "date"},
                    "gender": {"type": "keyword"},
                    "status": {"type": "keyword"},
                    "created_at": {"type": "date"},
                    "updated_at": {"type": "date"},
                    "balance": {"type": "float"},
                    "points": {"type": "integer"},
                    "is_vip": {"type": "boolean"},
                }
            }
        })

        # Products index
        self.es.indices.create(index="dbmaster_test_products", body={
            "settings": {"number_of_shards": 1, "number_of_replicas": 0},
            "mappings": {
                "properties": {
                    "id": {"type": "integer"},
                    "sku": {"type": "keyword"},
                    "name": {"type": "text"},
                    "category": {"type": "keyword"},
                    "price": {"type": "float"},
                    "cost": {"type": "float"},
                    "stock": {"type": "integer"},
                    "description": {"type": "text"},
                    "status": {"type": "keyword"},
                    "created_at": {"type": "date"},
                    "updated_at": {"type": "date"},
                    "weight_kg": {"type": "float"},
                    "rating": {"type": "float"},
                    "review_count": {"type": "integer"},
                    "tags": {"type": "keyword"},
                }
            }
        })

        # Orders index
        self.es.indices.create(index="dbmaster_test_orders", body={
            "settings": {"number_of_shards": 1, "number_of_replicas": 0},
            "mappings": {
                "properties": {
                    "id": {"type": "integer"},
                    "order_no": {"type": "keyword"},
                    "user_id": {"type": "integer"},
                    "product_id": {"type": "integer"},
                    "quantity": {"type": "integer"},
                    "unit_price": {"type": "float"},
                    "total_amount": {"type": "float"},
                    "status": {"type": "keyword"},
                    "shipping_address": {"type": "text"},
                    "created_at": {"type": "date"},
                    "updated_at": {"type": "date"},
                    "paid_at": {"type": "date"},
                    "shipped_at": {"type": "date"},
                    "delivered_at": {"type": "date"},
                    "notes": {"type": "text"},
                }
            }
        })

    def insert_data(self, users, products, orders):
        def to_es_doc(doc):
            """Convert document for Elasticsearch"""
            result = {}
            for k, v in doc.items():
                if isinstance(v, datetime.datetime):
                    result[k] = v.isoformat()
                elif isinstance(v, datetime.date):
                    result[k] = v.isoformat()
                elif isinstance(v, list):
                    result[k] = v
                else:
                    result[k] = v
            return result

        # Bulk insert users
        from elasticsearch.helpers import bulk
        user_actions = [
            {"_index": "dbmaster_test_users", "_id": u["id"], "_source": to_es_doc(u)}
            for u in users
        ]
        bulk(self.es, user_actions, refresh=True)

        product_actions = [
            {"_index": "dbmaster_test_products", "_id": p["id"], "_source": to_es_doc(p)}
            for p in products
        ]
        bulk(self.es, product_actions, refresh=True)

        order_actions = [
            {"_index": "dbmaster_test_orders", "_id": o["id"], "_source": to_es_doc(o)}
            for o in orders
        ]
        bulk(self.es, order_actions, refresh=True)

    def cleanup(self):
        try:
            if hasattr(self, "es") and self.es:
                self.es.close()
        except Exception:
            pass


# ============================================================================
# Main
# ============================================================================

INserter_MAP = {
    "mysql": MySQLInserter,
    "postgresql": PostgreSQLInserter,
    "mongodb": MongoDBInserter,
    "redis": RedisInserter,
    "mssql": SQLServerInserter,
    "oracle": OracleInserter,
    "elasticsearch": ElasticsearchInserter,
}


def main():
    print("=" * 70)
    print("DbMaster 自动化测试数据生成工具")
    print("=" * 70)
    print(f"配置文件: {CONNECTIONS_FILE}")
    print(f"测试数据库名: {TEST_DB_NAME}")
    print(f"测试数据量: Users={TEST_DATA_COUNT['users']}, Products={TEST_DATA_COUNT['products']}, Orders={TEST_DATA_COUNT['orders']}")
    print("=" * 70)

    connections = load_connections()
    print(f"\n从配置文件中加载了 {len(connections)} 个数据库连接:")
    for conn in connections:
        print(f"  - {conn['name']} ({conn['type']}) @ {conn['host']}:{conn['port']}")

    results = {"success": [], "failed": []}

    for conn in connections:
        db_type = conn["type"]
        inserter_class = INserter_MAP.get(db_type)

        if not inserter_class:
            print(f"\n⚠️  跳过不支持的类型: {conn['name']} ({db_type})")
            continue

        # Special handling: Doris uses MySQL protocol but needs different DDL
        if db_type == "mysql" and "doris" in conn["name"].lower():
            inserter_class = DorisInserter

        inserter = inserter_class(conn)
        try:
            inserter.run()
            results["success"].append(conn["name"])
        except Exception as e:
            results["failed"].append((conn["name"], str(e)))

    # Summary
    print("\n" + "=" * 70)
    print("执行结果汇总")
    print("=" * 70)
    print(f"成功: {len(results['success'])}")
    for name in results["success"]:
        print(f"  ✅ {name}")

    if results["failed"]:
        print(f"\n失败: {len(results['failed'])}")
        for name, error in results["failed"]:
            print(f"  ❌ {name}: {error}")

    print("=" * 70)

    return 0 if not results["failed"] else 1


if __name__ == "__main__":
    sys.exit(main())
