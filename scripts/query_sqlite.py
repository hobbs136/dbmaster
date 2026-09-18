import sqlite3
conn = sqlite3.connect(r'C:\Users\hobbs\.mavis\sqlite.db')
cursor = conn.cursor()
cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
tables = cursor.fetchall()
print('Tables:', tables)
for (t,) in tables:
    print(f'\n--- {t} ---')
    cursor.execute(f'PRAGMA table_info({t})')
    cols = cursor.fetchall()
    print('Columns:', [c[1] for c in cols])
    cursor.execute(f'SELECT * FROM {t} LIMIT 5')
    rows = cursor.fetchall()
    for r in rows:
        print(r)
conn.close()
