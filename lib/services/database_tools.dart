class DatabaseTools {
  static List<Map<String, dynamic>> get tools => [
    {
      'type': 'function',
      'function': {
        'name': 'execute_sql',
        'description': '执行SQL语句，返回查询结果。用于执行SELECT、INSERT、UPDATE、DELETE等SQL语句。',
        'parameters': {
          'type': 'object',
          'properties': {
            'sql': {'type': 'string', 'description': '要执行的SQL语句'},
          },
          'required': ['sql'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_table_schema',
        'description': '获取指定表的结构信息，包括列名、类型、约束等。',
        'parameters': {
          'type': 'object',
          'properties': {
            'table': {'type': 'string', 'description': '表名'},
          },
          'required': ['table'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'list_tables',
        'description': '列出当前数据库中的所有表。',
        'parameters': {'type': 'object', 'properties': {}},
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_table_data',
        'description': '获取表中的数据，默认返回前100行。',
        'parameters': {
          'type': 'object',
          'properties': {
            'table': {'type': 'string', 'description': '表名'},
            'limit': {'type': 'integer', 'description': '返回的行数，默认100'},
            'offset': {'type': 'integer', 'description': '偏移量，默认0'},
          },
          'required': ['table'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'explain_query',
        'description': '分析SQL查询的执行计划，帮助优化查询性能。',
        'parameters': {
          'type': 'object',
          'properties': {
            'sql': {'type': 'string', 'description': '要分析的SQL语句'},
          },
          'required': ['sql'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'optimize_sql',
        'description': '优化SQL语句，提供优化建议和更好的写法。',
        'parameters': {
          'type': 'object',
          'properties': {
            'sql': {'type': 'string', 'description': '需要优化的SQL语句'},
          },
          'required': ['sql'],
        },
      },
    },
  ];
}
