import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/auth/auth_provider.dart';
import '../../models/template.dart';

final templateListProvider =
    FutureProvider.family<List<Template>, String>((ref, status) async {
  final apiClient = ref.read(apiClientProvider);
  final response = await apiClient.get<dynamic>(
    ApiEndpoints.templates,
    queryParameters: {
      if (status.isNotEmpty) 'status': status,
      'page': 1,
      'page_size': 100,
    },
  );
  final body = response.data;
  final data = body is Map ? body['data'] : body;
  return (data as List? ?? const [])
      .map((item) => Template.fromJson(Map<String, dynamic>.from(item as Map)))
      .toList();
});

// autoDispose：离开模板编辑页后释放缓存，重新进入时拉取最新的节点类型/字段排序，
// 避免展示上一次进入时的旧快照。
final templateDetailProvider = FutureProvider.autoDispose
    .family<Template, String>((ref, id) async {
  final apiClient = ref.read(apiClientProvider);
  final response = await apiClient.get<dynamic>(ApiEndpoints.template(id));
  return Template.fromJson(_responseMap(response.data));
});

final templateEditorProvider = StateNotifierProvider.autoDispose
    .family<TemplateEditorNotifier, Template?, String>((ref, id) {
  return TemplateEditorNotifier(ref.read(apiClientProvider));
});

class TemplateEditorNotifier extends StateNotifier<Template?> {
  TemplateEditorNotifier(this.apiClient) : super(null);

  final ApiClient apiClient;
  Timer? _debounceTimer;
  final Map<String, dynamic> _pendingChanges = {};
  bool _isSaving = false;

  void loadTemplate(Template template) {
    if (state?.id == template.id && _pendingChanges.isNotEmpty) return;
    state = template;
  }

  void updateField(String field, dynamic value) {
    final current = state;
    if (current == null || current.status != 'draft') return;
    if (field != 'name' && field != 'version_note') return;

    state = _copyTemplate(
      current,
      name: field == 'name' ? value.toString() : null,
      versionNote: field == 'version_note' ? value.toString() : null,
    );
    _pendingChanges[field] = value;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), _save);
  }

  Future<void> flush() async {
    _debounceTimer?.cancel();
    await _save();
  }

  Future<void> _save() async {
    final current = state;
    if (current == null || _pendingChanges.isEmpty || _isSaving) return;
    if (_pendingChanges['name']?.toString().trim().isEmpty ?? false) return;
    _isSaving = true;
    var failed = false;
    final changes = Map<String, dynamic>.from(_pendingChanges);
    _pendingChanges.clear();
    try {
      final response = await apiClient.put<dynamic>(
        ApiEndpoints.template(current.id),
        data: changes,
      );
      if (_pendingChanges.isEmpty) {
        state = Template.fromJson(_responseMap(response.data));
      }
    } catch (_) {
      failed = true;
      _pendingChanges.addAll(changes);
    } finally {
      _isSaving = false;
      if (_pendingChanges.isNotEmpty && !failed) {
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(milliseconds: 500), _save);
      }
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    final current = state;
    if (current != null && _pendingChanges.isNotEmpty) {
      final changes = Map<String, dynamic>.from(_pendingChanges);
      if (!(changes['name']?.toString().trim().isEmpty ?? false)) {
        unawaited(
          apiClient
              .put<dynamic>(
                ApiEndpoints.template(current.id),
                data: changes,
              )
              .then<void>((_) {}, onError: (_) {}),
        );
      }
    }
    super.dispose();
  }
}

Map<String, dynamic> _responseMap(dynamic body) {
  final dynamic data =
      body is Map && body.containsKey('data') ? body['data'] : body;
  return Map<String, dynamic>.from(data as Map);
}

Template _copyTemplate(
  Template source, {
  String? name,
  String? versionNote,
}) {
  return Template(
    id: source.id,
    name: name ?? source.name,
    key: source.key,
    description: source.description,
    version: source.version,
    versionNote: versionNote ?? source.versionNote,
    status: source.status,
    createdBy: source.createdBy,
    createdAt: source.createdAt,
    updatedAt: source.updatedAt,
    nodeTypes: source.nodeTypes,
    nodeRules: source.nodeRules,
  );
}
