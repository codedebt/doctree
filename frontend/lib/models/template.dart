import 'dart:convert';

class Template {
  final String id;
  final String name;
  final String key;
  final String description;
  final String version;
  final String versionNote;
  final String status;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<NodeType> nodeTypes;
  final List<NodeRule> nodeRules;

  const Template({
    required this.id,
    required this.name,
    required this.key,
    this.description = '',
    required this.version,
    this.versionNote = '',
    required this.status,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
    this.nodeTypes = const [],
    this.nodeRules = const [],
  });

  factory Template.fromJson(Map<String, dynamic> json) => Template(
        id: json['id'] as String,
        name: json['name'] as String,
        key: json['key'] as String,
        description: json['description'] as String? ?? '',
        version: json['version']?.toString() ?? 'v1.0.0',
        versionNote: json['version_note'] as String? ?? '',
        status: json['status'] as String,
        createdBy: json['created_by'] as String?,
        createdAt: _asDateTime(json['created_at']),
        updatedAt: _asDateTime(json['updated_at']),
        nodeTypes:
            _asMapList(json['node_types']).map(NodeType.fromJson).toList(),
        nodeRules:
            _asMapList(json['node_rules']).map(NodeRule.fromJson).toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'key': key,
        'description': description,
        'version': version,
        'version_note': versionNote,
        'status': status,
        if (createdBy != null) 'created_by': createdBy,
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
        if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
        'node_types': nodeTypes.map((item) => item.toJson()).toList(),
        'node_rules': nodeRules.map((item) => item.toJson()).toList(),
      };
}

class NodeType {
  final String id;
  final String templateId;
  final String name;
  final String key;
  final String description;
  final String icon;
  final String color;
  final int sortOrder;
  final List<Field> fields;

  const NodeType({
    required this.id,
    required this.templateId,
    required this.name,
    required this.key,
    this.description = '',
    this.icon = '',
    this.color = '',
    this.sortOrder = 0,
    this.fields = const [],
  });

  factory NodeType.fromJson(Map<String, dynamic> json) => NodeType(
        id: json['id'] as String,
        templateId: json['template_id'] as String? ?? '',
        name: json['name'] as String,
        key: json['key'] as String,
        description: json['description'] as String? ?? '',
        icon: json['icon'] as String? ?? '',
        color: json['color'] as String? ?? '',
        sortOrder: _asInt(json['sort_order']),
        fields: _asMapList(json['fields']).map(Field.fromJson).toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'template_id': templateId,
        'name': name,
        'key': key,
        'description': description,
        'icon': icon,
        'color': color,
        'sort_order': sortOrder,
        'fields': fields.map((item) => item.toJson()).toList(),
      };
}

class Field {
  final String id;
  final String nodeTypeId;
  final String name;
  final String key;
  final String description;
  final String fieldType;
  final bool required;
  final dynamic defaultValue;
  final List<String> options;
  final Map<String, dynamic> validation;
  final String placeholder;
  final int sortOrder;
  final bool deletable;

  const Field({
    required this.id,
    required this.nodeTypeId,
    required this.name,
    required this.key,
    this.description = '',
    required this.fieldType,
    this.required = false,
    this.defaultValue,
    this.options = const [],
    this.validation = const {},
    this.placeholder = '',
    this.sortOrder = 0,
    this.deletable = true,
  });

  factory Field.fromJson(Map<String, dynamic> json) => Field(
        id: json['id'] as String,
        nodeTypeId: json['node_type_id'] as String? ?? '',
        name: json['name'] as String,
        key: json['key'] as String,
        description: json['description'] as String? ?? '',
        fieldType: json['field_type'] as String,
        required: json['required'] as bool? ?? false,
        defaultValue: json['default_value'],
        options: _asStringList(json['options']),
        validation: Map<String, dynamic>.from(
          json['validation'] as Map? ?? const {},
        ),
        placeholder: json['placeholder'] as String? ?? '',
        sortOrder: _asInt(json['sort_order']),
        deletable: json['deletable'] as bool? ??
            !const {'name', 'key'}.contains(json['key']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'node_type_id': nodeTypeId,
        'name': name,
        'key': key,
        'description': description,
        'field_type': fieldType,
        'required': required,
        'default_value': defaultValue,
        'options': options,
        'validation': validation,
        'placeholder': placeholder,
        'sort_order': sortOrder,
        'deletable': deletable,
      };
}

class NodeRule {
  final String id;
  final String templateId;
  final String? parentNodeTypeId;
  final String childNodeTypeId;
  final int minCount;
  final int maxCount;
  final bool isRootRule;

  const NodeRule({
    required this.id,
    required this.templateId,
    this.parentNodeTypeId,
    required this.childNodeTypeId,
    this.minCount = 0,
    this.maxCount = 0,
    this.isRootRule = false,
  });

  factory NodeRule.fromJson(Map<String, dynamic> json) => NodeRule(
        id: json['id'] as String,
        templateId: json['template_id'] as String? ?? '',
        parentNodeTypeId: _nullableString(
          json['parent_node_type_id'] ??
              json['parent_node_type_key'] ??
              json['parent_type_key'],
        ),
        childNodeTypeId: (json['child_node_type_id'] ??
                json['child_node_type_key'] ??
                json['child_type_key'])
            .toString(),
        minCount: _asInt(json['min_count'] ?? json['min_children']),
        maxCount: _asInt(json['max_count'] ?? json['max_children']),
        isRootRule: json['is_root_rule'] as bool? ??
            _nullableString(json['parent_node_type_id']) == null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'template_id': templateId,
        'parent_node_type_id': parentNodeTypeId ?? '',
        'child_node_type_id': childNodeTypeId,
        'min_count': minCount,
        'max_count': maxCount,
        'is_root_rule': isRootRule,
      };
}

List<Map<String, dynamic>> _asMapList(dynamic value) =>
    (value as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();

int _asInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

String? _nullableString(dynamic value) {
  final text = value?.toString();
  return text == null || text.isEmpty ? null : text;
}

List<String> _asStringList(dynamic value) {
  if (value is List) return value.map((item) => item.toString()).toList();
  if (value is! String || value.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(value);
    if (decoded is List) {
      return decoded.map((item) => item.toString()).toList();
    }
  } on FormatException {
    return const [];
  }
  return const [];
}

DateTime? _asDateTime(dynamic value) =>
    value == null ? null : DateTime.tryParse(value.toString());
