import 'package:flutter/foundation.dart';
import '../services/recent_tables_service.dart';

class RecentTablesProvider extends ChangeNotifier {
  final RecentTablesService _service = RecentTablesService();
  List<RecentTableEntry> _entries = [];
  bool _isLoaded = false;

  List<RecentTableEntry> get entries => List.unmodifiable(_entries);
  bool get isLoaded => _isLoaded;

  Future<void> load() async {
    _entries = await _service.getRecentTables();
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> recordTableAccess({
    required String connectionId,
    required String databaseName,
    required String tableName,
  }) async {
    await _service.recordTableAccess(
      connectionId: connectionId,
      databaseName: databaseName,
      tableName: tableName,
    );
    _entries = await _service.getRecentTables();
    notifyListeners();
  }

  Future<void> clear() async {
    await _service.clear();
    _entries = [];
    notifyListeners();
  }

  Future<void> clearForConnection(
    String connectionId, {
    String? databaseName,
  }) async {
    await _service.clearForConnection(connectionId, databaseName: databaseName);
    _entries = await _service.getRecentTables();
    notifyListeners();
  }
}
