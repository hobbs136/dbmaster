// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'aggregation_stage.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AggregationStage _$AggregationStageFromJson(Map<String, dynamic> json) =>
    AggregationStage(
      id: json['id'] as String,
      operator: json['operator'] as String,
      jsonBody: json['jsonBody'] as String,
      isValid: json['isValid'] as bool,
      errorMessage: json['errorMessage'] as String?,
    );

Map<String, dynamic> _$AggregationStageToJson(AggregationStage instance) =>
    <String, dynamic>{
      'id': instance.id,
      'operator': instance.operator,
      'jsonBody': instance.jsonBody,
      'isValid': instance.isValid,
      'errorMessage': instance.errorMessage,
    };
