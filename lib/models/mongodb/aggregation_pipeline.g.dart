// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'aggregation_pipeline.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AggregationPipeline _$AggregationPipelineFromJson(Map<String, dynamic> json) =>
    AggregationPipeline(
      collectionName: json['collectionName'] as String,
      stages: (json['stages'] as List<dynamic>)
          .map((e) => AggregationStage.fromJson(e as Map<String, dynamic>))
          .toList(),
      isRunning: json['isRunning'] as bool,
      result: json['result'] as String?,
    );

Map<String, dynamic> _$AggregationPipelineToJson(
  AggregationPipeline instance,
) => <String, dynamic>{
  'collectionName': instance.collectionName,
  'stages': instance.stages,
  'isRunning': instance.isRunning,
  'result': instance.result,
};
