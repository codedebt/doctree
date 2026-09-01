class TreeNode {
  final String id;
  final String projectId;
  final String? parentId;
  final String nodeTypeKey;
  final String name;
  final int sortOrder;
  final List<NodeFieldValue> fieldValues;
  final List<TreeNode> children;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const TreeNode({
    required this.id,
    required this.projectId,
    this.parentId,
    required this.nodeTypeKey,
    required this.name,
    this.sortOrder = 0,
    this.fieldValues = const [],
    this.children = const [],
    this.createdAt,
    this.updatedAt,
  });

  factory TreeNode.fromJson(Map<String, dynamic> json) => TreeNode(
        id: json['id'] as String,
        projectId: json['project_id'] as String,
        parentId: json['parent_id'] as String?,
        nodeTypeKey: json['node_type_key'] as String,
        name: json['name'] as String,
        sortOrder: _asInt(json['sort_order']),
        fieldValues: _asMapList(json['field_values'])
            .map(NodeFieldValue.fromJson)
            .toList(),
        children: _asMapList(json['children']).map(TreeNode.fromJson).toList(),
        createdAt: _asDateTime(json['created_at']),
        updatedAt: _asDateTime(json['updated_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'project_id': projectId,
        'parent_id': parentId,
        'node_type_key': nodeTypeKey,
        'name': name,
        'sort_order': sortOrder,
        'field_values': fieldValues.map((item) => item.toJson()).toList(),
        'children': children.map((item) => item.toJson()).toList(),
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
        if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      };
}

class NodeFieldValue {
  final String id;
  final String nodeId;
  final String fieldKey;
  final dynamic value;

  const NodeFieldValue({
    required this.id,
    required this.nodeId,
    required this.fieldKey,
    this.value,
  });

  factory NodeFieldValue.fromJson(Map<String, dynamic> json) => NodeFieldValue(
        id: json['id'] as String,
        nodeId: json['node_id'] as String,
        fieldKey: json['field_key'] as String,
        value: json['value'],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'node_id': nodeId,
        'field_key': fieldKey,
        'value': value,
      };
}

class NodePermission {
  final String id;
  final String nodeId;
  final String userId;
  final String permissionType;

  const NodePermission({
    required this.id,
    required this.nodeId,
    required this.userId,
    required this.permissionType,
  });

  factory NodePermission.fromJson(Map<String, dynamic> json) => NodePermission(
        id: json['id'] as String,
        nodeId: json['node_id'] as String,
        userId: json['user_id'] as String,
        permissionType: json['permission_type'] as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'node_id': nodeId,
        'user_id': userId,
        'permission_type': permissionType,
      };
}

List<Map<String, dynamic>> _asMapList(dynamic value) =>
    (value as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

DateTime? _asDateTime(dynamic value) =>
    value == null ? null : DateTime.tryParse(value.toString());
