enum ProcedureType { procedure, function }

class StoredProcedure {
  final String name;
  final ProcedureType type;
  final List<ProcedureParameter> parameters;
  final String? returnType;
  final String? definition;
  final DateTime? createdAt;
  final DateTime? modifiedAt;
  final String? body;

  StoredProcedure({
    required this.name,
    required this.type,
    this.parameters = const [],
    this.returnType,
    this.definition,
    this.createdAt,
    this.modifiedAt,
    this.body,
  });

  StoredProcedure copyWith({
    String? name,
    ProcedureType? type,
    List<ProcedureParameter>? parameters,
    String? returnType,
    String? definition,
    DateTime? createdAt,
    DateTime? modifiedAt,
    String? body,
  }) {
    return StoredProcedure(
      name: name ?? this.name,
      type: type ?? this.type,
      parameters: parameters ?? this.parameters,
      returnType: returnType ?? this.returnType,
      definition: definition ?? this.definition,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      body: body ?? this.body,
    );
  }
}

class ProcedureParameter {
  final String name;
  final String dataType;
  final String mode; // IN, OUT, INOUT

  ProcedureParameter({
    required this.name,
    required this.dataType,
    this.mode = 'IN',
  });

  ProcedureParameter copyWith({String? name, String? dataType, String? mode}) {
    return ProcedureParameter(
      name: name ?? this.name,
      dataType: dataType ?? this.dataType,
      mode: mode ?? this.mode,
    );
  }

  @override
  String toString() {
    return '$mode $name $dataType';
  }
}
