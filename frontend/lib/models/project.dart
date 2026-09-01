class Project {
  final String id;
  final String name;
  final String key;
  final String description;
  final String version;
  final String versionNote;
  final String status;
  final String templateId;
  final int? templateVersion;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Project({
    required this.id,
    required this.name,
    required this.key,
    this.description = '',
    required this.version,
    this.versionNote = '',
    required this.status,
    required this.templateId,
    this.templateVersion,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  factory Project.fromJson(Map<String, dynamic> json) => Project(
        id: json['id'] as String,
        name: json['name'] as String,
        key: json['key'] as String,
        description: json['description'] as String? ?? '',
        version: json['version']?.toString() ?? 'v1.0.0',
        versionNote: json['version_note'] as String? ?? '',
        status: json['status'] as String,
        templateId: json['template_id'] as String,
        templateVersion: _asNullableInt(json['template_version']),
        createdBy: (json['created_by'] ?? json['created_by_id']) as String?,
        createdAt: _asDateTime(json['created_at']),
        updatedAt: _asDateTime(json['updated_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'key': key,
        'description': description,
        'version': version,
        'version_note': versionNote,
        'status': status,
        'template_id': templateId,
        if (templateVersion != null) 'template_version': templateVersion,
        if (createdBy != null) 'created_by': createdBy,
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
        if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      };
}

int? _asNullableInt(dynamic value) => value == null ? null : _asInt(value);

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

DateTime? _asDateTime(dynamic value) =>
    value == null ? null : DateTime.tryParse(value.toString());
