import 'ai_response_parser.dart';

/// MongoDB 查询响应解析器
///
/// 从 AI 返回的文本中提取 MongoDB Shell 查询语句。
class MongoDbResponseParser extends AiResponseParser {
  MongoDbResponseParser({super.locale});

  @override
  List<String> extractExecutableStatements(String response) {
    final results = <String>[];
    final processedRanges = <List<int>>[];

    // 1. 提取 <sql>...</sql> 标签（最高优先级）
    final sqlTagPattern = RegExp(
      r'<sql>\s*([\s\S]*?)\s*</sql>',
      caseSensitive: false,
    );
    for (final match in sqlTagPattern.allMatches(response)) {
      final cmd = _cleanContent(match.group(1) ?? '');
      if (cmd.isNotEmpty && isValidCommand(cmd)) {
        results.add(cmd);
        processedRanges.add([match.start, match.end]);
      }
    }

    // 2. 提取 ```javascript/js/mongodb ... ``` 代码块
    final markdownPattern = RegExp(
      r'```(?:javascript|js|mongodb)?\s*\n?([\s\S]*?)```',
      caseSensitive: false,
    );
    for (final match in markdownPattern.allMatches(response)) {
      if (_isRangeOverlapping(match.start, match.end, processedRanges))
        continue;

      final cmd = _cleanContent(match.group(1) ?? '');
      if (cmd.isNotEmpty && isValidCommand(cmd)) {
        results.add(cmd);
        processedRanges.add([match.start, match.end]);
      }
    }

    // 3. 纯 MongoDB 查询回退
    if (results.isEmpty) {
      final mongoPattern = RegExp(
        r'(?:^|\n)\s*db\.[a-zA-Z_]\w*\.\w+\s*\(.*?\)(?:\s*\.\w+\s*\(.*?\))*\s*;?',
        caseSensitive: false,
        multiLine: true,
      );
      for (final match in mongoPattern.allMatches(response)) {
        final cmd = _cleanContent(match.group(0) ?? '');
        if (cmd.isNotEmpty &&
            isValidCommand(cmd) &&
            !_isDuplicate(cmd, results)) {
          results.add(cmd);
        }
      }
    }

    return results;
  }

  @override
  bool isValidCommand(String command) {
    final trimmed = command.trim();
    if (!trimmed.startsWith('db.')) return false;

    final mongoMethods = RegExp(
      r'\b(find|findOne|aggregate|insertOne|insertMany|updateOne|updateMany|deleteOne|deleteMany|countDocuments|estimatedDocumentCount|distinct|replaceOne|findOneAndUpdate|findOneAndReplace|findOneAndDelete|bulkWrite|createIndex|dropIndex|dropIndexes|listIndexes|renameCollection|drop)\s*\(',
      caseSensitive: false,
    );
    return mongoMethods.hasMatch(trimmed);
  }

  String _cleanContent(String content) {
    content = content.replaceAll(RegExp(r'^\s*```\w*\s*', multiLine: true), '');
    content = content.replaceAll(RegExp(r'\s*```\s*$', multiLine: true), '');

    final lines = content.split('\n');
    final cleanedLines = lines.where((line) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) return false;
      if (RegExp(r'^[\u4e00-\u9fa5\s：:]+$').hasMatch(trimmed)) return false;
      return true;
    }).toList();

    return cleanedLines.join('\n').trim();
  }

  bool _isRangeOverlapping(int start, int end, List<List<int>> ranges) {
    for (final range in ranges) {
      if (start < range[1] && end > range[0]) {
        return true;
      }
    }
    return false;
  }

  bool _isDuplicate(String cmd, List<String> existing) {
    final normalized = cmd.replaceAll(RegExp(r'\s+'), ' ').trim();
    for (final existingCmd in existing) {
      final existingNormalized = existingCmd
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (normalized == existingNormalized) return true;
    }
    return false;
  }
}
