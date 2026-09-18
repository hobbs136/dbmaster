// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'explain_plan_tree.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ExplainPlanNode _$ExplainPlanNodeFromJson(Map<String, dynamic> json) =>
    ExplainPlanNode(
      stageType: json['stageType'] as String,
      label: json['label'] as String,
      executionStats: json['executionStats'] as Map<String, dynamic>?,
      children: (json['children'] as List<dynamic>)
          .map((e) => ExplainPlanNode.fromJson(e as Map<String, dynamic>))
          .toList(),
      isExpanded: json['isExpanded'] as bool? ?? false,
    );

Map<String, dynamic> _$ExplainPlanNodeToJson(ExplainPlanNode instance) =>
    <String, dynamic>{
      'stageType': instance.stageType,
      'label': instance.label,
      'executionStats': instance.executionStats,
      'children': instance.children,
      'isExpanded': instance.isExpanded,
    };

ExplainPlanTree _$ExplainPlanTreeFromJson(Map<String, dynamic> json) =>
    ExplainPlanTree(
      query: json['query'] as String,
      rootNode: json['rootNode'] == null
          ? null
          : ExplainPlanNode.fromJson(json['rootNode'] as Map<String, dynamic>),
      parseError: json['parseError'] as String?,
      executionTimeMillis: (json['executionTimeMillis'] as num?)?.toInt(),
    );

Map<String, dynamic> _$ExplainPlanTreeToJson(ExplainPlanTree instance) =>
    <String, dynamic>{
      'query': instance.query,
      'rootNode': instance.rootNode,
      'parseError': instance.parseError,
      'executionTimeMillis': instance.executionTimeMillis,
    };
