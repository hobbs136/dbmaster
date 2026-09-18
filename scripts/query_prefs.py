import sqlite3
conn = sqlite3.connect(r'C:\Users\hobbs\.mavis\sqlite.db')
cursor = conn.cursor()
keys = ['computer_use', 'allowed_tools', 'computer_use_toggle', 'cu_enabled', 'mcp_cu_enabled', 'renderer_computer_use']
for k in keys:
    cursor.execute('SELECT * FROM preferences WHERE key = ?', (k,))
    rows = cursor.fetchall()
    print(f'{k}: {rows}')

cursor.execute("SELECT * FROM preferences LIMIT 50")
rows = cursor.fetchall()
for r in rows:
    print(r)
conn.close()
