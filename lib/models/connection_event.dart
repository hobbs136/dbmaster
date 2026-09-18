import 'database_models.dart';

/// Base class for connection lifecycle events emitted by DatabaseService.
sealed class ConnectionEvent {
  final String connectionId;
  const ConnectionEvent(this.connectionId);
}

class ConnectionEstablished extends ConnectionEvent {
  final DbServer server;
  const ConnectionEstablished(super.connectionId, this.server);
}

class ConnectionDisconnected extends ConnectionEvent {
  final DbServer? server;
  const ConnectionDisconnected(super.connectionId, this.server);
}

class DatabaseSwitched extends ConnectionEvent {
  final String databaseName;
  const DatabaseSwitched(super.connectionId, this.databaseName);
}

class ConnectionInfoLoaded extends ConnectionEvent {
  final Database database;
  const ConnectionInfoLoaded(super.connectionId, this.database);
}

class TransactionRolledBack extends ConnectionEvent {
  final String reason;
  const TransactionRolledBack(super.connectionId, this.reason);
}

class SessionRestored extends ConnectionEvent {
  final String? databaseName;
  final bool wasInTransaction;
  final List<String> restoredItems;
  final List<String> failedItems;

  const SessionRestored(
    super.connectionId, {
    this.databaseName,
    this.wasInTransaction = false,
    this.restoredItems = const [],
    this.failedItems = const [],
  });
}
