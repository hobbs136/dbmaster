import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/models/database_models.dart';

class DatabaseToolRegistry {
  static final Map<DatabaseType, List<Map<String, dynamic>>> _toolSets = {
    DatabaseType.mysql: [..._sqlTools, ..._sqlWriteTools],
    DatabaseType.postgresql: [..._sqlTools, ..._sqlWriteTools],
    DatabaseType.sqlite: [..._sqlTools, ..._sqlWriteTools],
    DatabaseType.doris: [..._sqlTools, ..._sqlWriteTools],
    DatabaseType.tdengine: [..._sqlTools, ..._tdengineTools, ..._sqlWriteTools],
    DatabaseType.sqlserver: [..._sqlTools, ..._sqlWriteTools],
    // Mongo 同时注册只读 + 写/运维工具（research D11）。
    DatabaseType.mongodb: [..._mongoTools, ..._mongoWriteTools],
    DatabaseType.redis: _redisTools,
  };

  static List<Map<String, dynamic>> getToolsFor(DatabaseType type) {
    return _toolSets[type] ?? _sqlTools;
  }

  /// Read-only toolset
  static final List<Map<String, dynamic>> _sqlTools = [
    {
      'type': 'function',
      'function': {
        'name': 'get_table_schema',
        'description':
            'Get schema information for a specified table, including column names, data types, primary keys, indexes, and foreign key relationships (outgoing + incoming). Used to generate accurate SQL statements.',
        'parameters': {
          'type': 'object',
          'properties': {
            'table': {'type': 'string', 'description': 'Table name'},
          },
          'required': ['table'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_table_relationships',
        'description':
            'Get bidirectional foreign key relationships for a table: outgoing foreign keys (this table references others) '
            'and incoming references (other tables reference this table, with ON DELETE actions). '
            'Use this FIRST when analyzing which related data must be handled before deleting or updating rows.',
        'parameters': {
          'type': 'object',
          'properties': {
            'table': {'type': 'string', 'description': 'Table name'},
          },
          'required': ['table'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'run_readonly_query',
        'description':
            'Execute a single READ-ONLY SQL statement (SELECT / WITH ... SELECT / SHOW / EXPLAIN / DESCRIBE, '
            'PRAGMA for SQLite) and return up to 50 result rows. '
            'Use it to explore data samples, verify row counts before suggesting DELETE/UPDATE, '
            'or query metadata (information_schema). Write statements are rejected. '
            'Prefer get_table_schema / get_table_relationships for plain schema lookups (cheaper).',
        'parameters': {
          'type': 'object',
          'properties': {
            'sql': {
              'type': 'string',
              'description': 'A single read-only SQL statement',
            },
          },
          'required': ['sql'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'list_tables',
        'description': 'List all tables in the current database.',
        'parameters': {'type': 'object', 'properties': {}},
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'explain_query',
        'description':
            'Execute EXPLAIN on a SQL query and return raw execution plan data. Use this as the first step before analyze_query_performance.',
        'parameters': {
          'type': 'object',
          'properties': {
            'sql': {
              'type': 'string',
              'description': 'SQL statement to analyze',
            },
          },
          'required': ['sql'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'analyze_query_performance',
        'description':
            'Analyze query performance by parsing EXPLAIN results and providing actionable optimization recommendations. '
            'This tool identifies bottlenecks, recommends indexes, and suggests query rewrites. '
            'Use this AFTER calling explain_query to get the raw execution plan. '
            'Returns a comprehensive performance report with severity levels and estimated improvements.',
        'parameters': {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description': 'The original SQL query being analyzed',
            },
            'database_type': {
              'type': 'string',
              'description':
                  'Database type: mysql, postgresql, sqlite, doris, or tdengine',
            },
          },
          'required': ['query', 'database_type'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'search_query_history',
        'description':
            'Search through query history to find previously executed queries. '
            'Useful when users want to find queries they ran before, or to discover query patterns. '
            'Returns matching queries with metadata (execution time, row count, timestamp).',
        'parameters': {
          'type': 'object',
          'properties': {
            'keywords': {
              'type': 'string',
              'description': 'Search keywords to match against SQL statements',
            },
            'table_filter': {
              'type': 'string',
              'description': 'Filter by table name mentioned in the query',
            },
            'time_range': {
              'type': 'string',
              'description':
                  'Time range: today, week, month, or all (default: all)',
              'enum': ['today', 'week', 'month', 'all'],
            },
            'limit': {
              'type': 'integer',
              'description':
                  'Maximum number of results to return (default: 10)',
            },
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'recommend_similar_queries',
        'description':
            'Recommend similar or related queries based on current input or selected table. '
            'Helps users discover queries they have used before that might be relevant to their current task. '
            'Returns ranked recommendations with similarity scores and reasons.',
        'parameters': {
          'type': 'object',
          'properties': {
            'current_query': {
              'type': 'string',
              'description': 'Current SQL query being typed or edited',
            },
            'current_table': {
              'type': 'string',
              'description': 'Currently selected table name (optional)',
            },
            'limit': {
              'type': 'integer',
              'description': 'Maximum number of recommendations (default: 5)',
            },
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'analyze_schema_impact',
        'description':
            'Analyze the impact of a DDL (Data Definition Language) statement before execution. '
            'This tool detects dependencies (views, triggers, foreign keys), assesses risk levels, '
            'and generates rollback scripts. Use this BEFORE executing any DDL to understand the consequences. '
            'Returns a comprehensive impact report with warnings and recommendations.',
        'parameters': {
          'type': 'object',
          'properties': {
            'ddl_statement': {
              'type': 'string',
              'description':
                  'The DDL statement to analyze (e.g., ALTER TABLE, DROP TABLE, CREATE INDEX)',
            },
            'database_type': {
              'type': 'string',
              'description':
                  'Database type: mysql, postgresql, sqlite, doris, or tdengine',
            },
          },
          'required': ['ddl_statement', 'database_type'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_database_summary',
        'description':
            'Get an overview of the current database, including database type, version, table count, and most used tables.',
        'parameters': {'type': 'object', 'properties': {}},
      },
    },
  ];

  static final List<Map<String, dynamic>> _tdengineTools = [
    {
      'type': 'function',
      'function': {
        'name': 'list_super_tables',
        'description':
            'List all super tables in the current TDengine database.',
        'parameters': {'type': 'object', 'properties': {}},
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_super_table_schema',
        'description':
            'Get the schema of a TDengine super table, including column definitions and tag definitions.',
        'parameters': {
          'type': 'object',
          'properties': {
            'table': {'type': 'string', 'description': 'Super table name'},
          },
          'required': ['table'],
        },
      },
    },
  ];

  /// Write tools for SQL-based databases (require user confirmation)
  static final List<Map<String, dynamic>> _sqlWriteTools = [
    {
      'type': 'function',
      'function': {
        'name': 'smart_import',
        'description':
            'Smart import file into database. Analyze file structure (CSV/JSON), infer field types, check target table status.'
            'Return file analysis results and table status for generating CREATE TABLE statements.'
            'If the target table already exists with data, a warning will be returned and user confirmation is required before continuing import.',
        'parameters': {
          'type': 'object',
          'properties': {
            'file_path': {
              'type': 'string',
              'description': 'Absolute path of the file to import',
            },
            'target_table': {
              'type': 'string',
              'description':
                  'Target table name (optional, AI will auto-infer a suitable table name)',
            },
          },
          'required': ['file_path'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'analyze_export',
        'description':
            'Analyze data export requirements for a table. Returns table structure, row count, and estimated export size. '
            'Use this tool to help users understand what they are about to export before creating the export task. '
            'The actual export will be created as a background task after user confirmation.',
        'parameters': {
          'type': 'object',
          'properties': {
            'table': {'type': 'string', 'description': 'Table name to export'},
            'where_clause': {
              'type': 'string',
              'description':
                  'Optional WHERE clause to filter data (e.g., "created_at > DATE_SUB(NOW(), INTERVAL 1 MONTH)")',
            },
          },
          'required': ['table'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'generate_test_data',
        'description':
            'Generate realistic test data for a specified table. Supports all SQL databases with multi-language faker data. '
            'Can auto-execute INSERT statements or return SQL for manual execution. '
            'For large datasets (>100 rows), use multiple calls with 1000 rows per call.',
        'parameters': {
          'type': 'object',
          'properties': {
            'table': {
              'type': 'string',
              'description': 'Table name to generate data for',
            },
            'count': {
              'type': 'integer',
              'description': 'Number of rows to generate (max 1000 per call)',
            },
            'locale': {
              'type': 'string',
              'description':
                  'Locale for realistic data: en, zh, de, fr, ru (default: auto-detect from app settings)',
            },
            'realistic_mode': {
              'type': 'boolean',
              'description':
                  'Use realistic faker data (names, emails, addresses) instead of random values (default: true)',
            },
            'auto_execute': {
              'type': 'boolean',
              'description':
                  'Auto-execute INSERT statements (default: false, returns SQL for confirmation)',
            },
          },
          'required': ['table', 'count'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_table_row_count',
        'description':
            'Get the current row count of a specified table. Used to check batch insertion progress.',
        'parameters': {
          'type': 'object',
          'properties': {
            'table': {'type': 'string', 'description': 'Table name'},
          },
          'required': ['table'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'execute_import',
        'description':
            'Execute a full import workflow: analyze file, create table if not exists, and import data. '
            'Use this after analyzing with smart_import and getting user confirmation. '
            'Returns import results including success/failed row counts.',
        'parameters': {
          'type': 'object',
          'properties': {
            'file_path': {
              'type': 'string',
              'description': 'Absolute path of the file to import',
            },
            'target_table': {
              'type': 'string',
              'description':
                  'Target table name (optional, will be inferred from filename if not provided)',
            },
            'conflict_resolution': {
              'type': 'string',
              'description':
                  'How to handle duplicate keys: skip (default), update, or abort',
              'enum': ['skip', 'update', 'abort'],
            },
          },
          'required': ['file_path'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'create_export_task',
        'description':
            'Create a background export task for a table. Use this after analyzing with analyze_export and getting user confirmation. '
            'The task will run in the background and can be monitored in the Task Panel.',
        'parameters': {
          'type': 'object',
          'properties': {
            'table': {'type': 'string', 'description': 'Table name to export'},
            'format': {
              'type': 'string',
              'description': 'Export format: csv, json, or sql',
              'enum': ['csv', 'json', 'sql'],
            },
            'output_path': {
              'type': 'string',
              'description': 'Absolute file path for the exported file',
            },
            'where_clause': {
              'type': 'string',
              'description': 'Optional WHERE clause to filter data',
            },
          },
          'required': ['table', 'format', 'output_path'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'analyze_data_quality',
        'description':
            'Analyze data quality of a file before import. Detects missing values, format errors, duplicates, and whitespace issues. '
            'Returns a quality report with cleaning recommendations.',
        'parameters': {
          'type': 'object',
          'properties': {
            'file_path': {
              'type': 'string',
              'description': 'Absolute path of the file to analyze',
            },
          },
          'required': ['file_path'],
        },
      },
    },
  ];

  /// MongoDB只读工具
  static final List<Map<String, dynamic>> _mongoTools = [
    {
      'type': 'function',
      'function': {
        'name': 'list_collections',
        'description': 'List all collections in the current MongoDB database.',
        'parameters': {'type': 'object', 'properties': {}},
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_collection_schema',
        'description':
            'Infer the Schema structure of a specified collection through sampling.',
        'parameters': {
          'type': 'object',
          'properties': {
            'collection': {'type': 'string', 'description': 'Collection name'},
          },
          'required': ['collection'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'find_documents_mongo',
        'description':
            'Read documents from a MongoDB collection with an optional query filter, '
            'projection and limit (max 50), plus the total matching document count. '
            'Use it to inspect data samples or verify how many documents a change would affect. '
            'Read-only; write operations are not available through this tool.',
        'parameters': {
          'type': 'object',
          'properties': {
            'collection': {'type': 'string', 'description': 'Collection name'},
            'filter': {
              'type': 'object',
              'description': 'MongoDB query filter (e.g. {"status": "active"})',
            },
            'projection': {
              'type': 'object',
              'description': 'Optional projection (e.g. {"name": 1})',
            },
            'limit': {
              'type': 'integer',
              'description': 'Max documents to return (default 20, max 50)',
            },
          },
          'required': ['collection'],
        },
      },
    },
  ];

  /// MongoDB 写/运维工具（镜像 _sqlWriteTools，但面向 Mongo 原语）。
  static final List<Map<String, dynamic>> _mongoWriteTools = [
    {
      'type': 'function',
      'function': {
        'name': 'import_documents_mongo',
        'description':
            'Import (insert) JSON documents into a MongoDB collection. '
            'Use this when the user wants to insert a batch of documents.',
        'parameters': {
          'type': 'object',
          'properties': {
            'collection': {
              'type': 'string',
              'description': 'Target collection name',
            },
            'documents': {
              'type': 'array',
              'description': 'JSON documents to insert',
              'items': {'type': 'object'},
            },
          },
          'required': ['collection', 'documents'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'generate_test_data_mongo',
        'description':
            'Generate realistic test documents for a MongoDB collection by inferring its schema, '
            'then inserting the synthesized documents. Returns the number of documents inserted.',
        'parameters': {
          'type': 'object',
          'properties': {
            'collection': {
              'type': 'string',
              'description': 'Collection name to generate data for',
            },
            'count': {
              'type': 'integer',
              'description': 'Number of documents to generate',
            },
          },
          'required': ['collection', 'count'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'export_collection_mongo',
        'description':
            'Export documents from a MongoDB collection as JSON or CSV text. '
            'Returns the serialized data preview for the user.',
        'parameters': {
          'type': 'object',
          'properties': {
            'collection': {
              'type': 'string',
              'description': 'Collection name to export',
            },
            'format': {
              'type': 'string',
              'description': 'Export format',
              'enum': ['json', 'csv'],
            },
            'filter': {
              'type': 'object',
              'description':
                  'Optional Mongo filter object to limit exported documents',
            },
            'limit': {
              'type': 'integer',
              'description': 'Optional max number of documents to export',
            },
          },
          'required': ['collection', 'format'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'analyze_export_mongo',
        'description':
            'Analyze a MongoDB collection before export using native Mongo stats and a small document sample '
            '(NOT SQL SELECT COUNT(*)). Returns document count, storage size, index count, and a few sample documents.',
        'parameters': {
          'type': 'object',
          'properties': {
            'collection': {
              'type': 'string',
              'description': 'Collection name to analyze',
            },
            'sample_limit': {
              'type': 'integer',
              'description':
                  'Number of sample documents to return (default: 3)',
            },
          },
          'required': ['collection'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'analyze_data_quality_mongo',
        'description':
            'Analyze data quality of a MongoDB collection by sampling documents. '
            'Reports per-field completeness, type consistency, and null ratio.',
        'parameters': {
          'type': 'object',
          'properties': {
            'collection': {
              'type': 'string',
              'description': 'Collection name to analyze',
            },
          },
          'required': ['collection'],
        },
      },
    },
  ];

  /// Redis只读工具
  static final List<Map<String, dynamic>> _redisTools = [
    {
      'type': 'function',
      'function': {
        'name': 'get_keyspace_summary',
        'description':
            'Get keyspace overview and memory usage for the current Redis DB.',
        'parameters': {'type': 'object', 'properties': {}},
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'scan_keys',
        'description':
            'Scan Redis keys matching a pattern (default "*"), up to a limit. '
            'Use it to discover keys before inspecting them with get_key.',
        'parameters': {
          'type': 'object',
          'properties': {
            'pattern': {
              'type': 'string',
              'description': 'Glob-style key pattern (default "*")',
            },
            'limit': {
              'type': 'integer',
              'description': 'Max keys to return (default 100, max 1000)',
            },
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_key',
        'description':
            'Inspect a single Redis key: its type, TTL and a value preview '
            '(string value, hash fields, list/set/zset members). Read-only.',
        'parameters': {
          'type': 'object',
          'properties': {
            'key': {'type': 'string', 'description': 'Redis key name'},
          },
          'required': ['key'],
        },
      },
    },
  ];
}
