enum TriggerTiming { before, after }

enum TriggerEvent { insert, update, delete }

extension TriggerTimingExtension on TriggerTiming {
  String get value => this == TriggerTiming.before ? 'BEFORE' : 'AFTER';

  static TriggerTiming fromString(String value) {
    return value.toUpperCase() == 'BEFORE'
        ? TriggerTiming.before
        : TriggerTiming.after;
  }
}

extension TriggerEventExtension on TriggerEvent {
  String get value {
    switch (this) {
      case TriggerEvent.insert:
        return 'INSERT';
      case TriggerEvent.update:
        return 'UPDATE';
      case TriggerEvent.delete:
        return 'DELETE';
    }
  }

  static List<TriggerEvent> fromString(String value) {
    final upperValue = value.toUpperCase();
    final events = <TriggerEvent>[];

    if (upperValue.contains('INSERT')) events.add(TriggerEvent.insert);
    if (upperValue.contains('UPDATE')) events.add(TriggerEvent.update);
    if (upperValue.contains('DELETE')) events.add(TriggerEvent.delete);

    return events;
  }
}

class DatabaseTrigger {
  final String name;
  final TriggerTiming timing;
  final List<TriggerEvent> events;
  final String tableName;
  final String definition;
  final String? definer;
  final DateTime? createdAt;
  final DateTime? modifiedAt;
  final String? body;
  final bool enabled;

  DatabaseTrigger({
    required this.name,
    required this.timing,
    required this.events,
    required this.tableName,
    this.definition = '',
    this.definer,
    this.createdAt,
    this.modifiedAt,
    this.body,
    this.enabled = true,
  });

  DatabaseTrigger copyWith({
    String? name,
    TriggerTiming? timing,
    List<TriggerEvent>? events,
    String? tableName,
    String? definition,
    String? definer,
    DateTime? createdAt,
    DateTime? modifiedAt,
    String? body,
    bool? enabled,
  }) {
    return DatabaseTrigger(
      name: name ?? this.name,
      timing: timing ?? this.timing,
      events: events ?? this.events,
      tableName: tableName ?? this.tableName,
      definition: definition ?? this.definition,
      definer: definer ?? this.definer,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      body: body ?? this.body,
      enabled: enabled ?? this.enabled,
    );
  }

  String get eventString {
    return events.map((e) => e.value).join(' OR ');
  }

  @override
  String toString() {
    return 'DatabaseTrigger{name: $name, timing: $timing, events: $events, table: $tableName}';
  }
}
