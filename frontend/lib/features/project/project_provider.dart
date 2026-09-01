import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_endpoints.dart';
import '../../core/auth/auth_provider.dart';
import '../../models/node.dart';
import '../../models/project.dart';
import '../../models/template.dart';

final projectListProvider = FutureProvider<List<Project>>((ref) async {
  final response = await ref.read(apiClientProvider).get<dynamic>(
    ApiEndpoints.projects,
    queryParameters: const {'page': 1, 'page_size': 100},
  );
  final data = _responseData(response.data);
  return (data as List? ?? const [])
      .map((item) => Project.fromJson(Map<String, dynamic>.from(item as Map)))
      .toList();
});

final projectDetailProvider =
    FutureProvider.family<Project, String>((ref, id) async {
  final response =
      await ref.read(apiClientProvider).get<dynamic>(ApiEndpoints.project(id));
  return Project.fromJson(_responseMap(response.data));
});

final projectTreeProvider =
    FutureProvider.family<List<TreeNode>, String>((ref, projectId) async {
  final response = await ref
      .read(apiClientProvider)
      .get<dynamic>(ApiEndpoints.projectNodes(projectId));
  final data = _responseData(response.data);
  final nodes = (data as List? ?? const [])
      .map((item) => TreeNode.fromJson(Map<String, dynamic>.from(item as Map)))
      .toList();
  return _flattenNodes(nodes);
});

final projectTemplateProvider =
    FutureProvider.family<Template, String>((ref, templateId) async {
  final response = await ref
      .read(apiClientProvider)
      .get<dynamic>(ApiEndpoints.template(templateId));
  return Template.fromJson(_responseMap(response.data));
});

final selectedNodeProvider = StateProvider<TreeNode?>((ref) => null);

final projectTreeStateProvider = StateNotifierProvider.autoDispose
    .family<ProjectTreeNotifier, List<TreeNode>, String>(
  (ref, projectId) => ProjectTreeNotifier(),
);

class ProjectTreeNotifier extends StateNotifier<List<TreeNode>> {
  ProjectTreeNotifier() : super(const []);

  final Set<String> expandedNodeIds = <String>{};
  String? selectedNodeId;

  void load(List<TreeNode> flatNodes) {
    state = buildTree(flatNodes);
    final validIds = flatNodes.map((node) => node.id).toSet();
    expandedNodeIds.removeWhere((id) => !validIds.contains(id));
    if (selectedNodeId != null && !validIds.contains(selectedNodeId)) {
      selectedNodeId = null;
    }
    if (expandedNodeIds.isEmpty && state.isNotEmpty) {
      expandedNodeIds.add(state.first.id);
    }
  }

  List<TreeNode> buildTree(List<TreeNode> flatNodes) {
    final byParent = <String?, List<TreeNode>>{};
    final ids = flatNodes.map((node) => node.id).toSet();
    for (final node in flatNodes) {
      final parentId = ids.contains(node.parentId) ? node.parentId : null;
      byParent.putIfAbsent(parentId, () => []).add(node);
    }
    for (final siblings in byParent.values) {
      siblings.sort((a, b) {
        final order = a.sortOrder.compareTo(b.sortOrder);
        return order == 0 ? a.name.compareTo(b.name) : order;
      });
    }

    TreeNode build(TreeNode node, Set<String> ancestors) {
      if (ancestors.contains(node.id)) {
        return _copyNode(node, children: const []);
      }
      final nextAncestors = {...ancestors, node.id};
      final children = (byParent[node.id] ?? const <TreeNode>[])
          .map((child) => build(child, nextAncestors))
          .toList();
      return _copyNode(node, children: children);
    }

    return (byParent[null] ?? const <TreeNode>[])
        .map((node) => build(node, const <String>{}))
        .toList();
  }

  void toggleExpand(String nodeId) {
    expandedNodeIds.contains(nodeId)
        ? expandedNodeIds.remove(nodeId)
        : expandedNodeIds.add(nodeId);
    state = List<TreeNode>.from(state);
  }

  void expand(String nodeId) {
    if (expandedNodeIds.add(nodeId)) state = List<TreeNode>.from(state);
  }

  void selectNode(String? nodeId) {
    selectedNodeId = nodeId;
    state = List<TreeNode>.from(state);
  }

  void addNode(TreeNode node) {
    final flat = _flattenNodes(state)..add(node);
    load(flat);
    if (node.parentId != null) expandedNodeIds.add(node.parentId!);
  }

  void deleteNode(String nodeId) {
    final all = _flattenNodes(state);
    final deleted = <String>{nodeId};
    var changed = true;
    while (changed) {
      changed = false;
      for (final node in all) {
        if (node.parentId != null &&
            deleted.contains(node.parentId) &&
            deleted.add(node.id)) {
          changed = true;
        }
      }
    }
    load(all.where((node) => !deleted.contains(node.id)).toList());
  }

  void updateNode(TreeNode updated) {
    final flat = _flattenNodes(state);
    final index = flat.indexWhere((node) => node.id == updated.id);
    if (index < 0) return;
    flat[index] = updated;
    load(flat);
  }
}

dynamic _responseData(dynamic body) =>
    body is Map && body.containsKey('data') ? body['data'] : body;

Map<String, dynamic> _responseMap(dynamic body) =>
    Map<String, dynamic>.from(_responseData(body) as Map);

List<TreeNode> _flattenNodes(List<TreeNode> nodes) {
  final result = <TreeNode>[];
  void visit(TreeNode node) {
    result.add(_copyNode(node, children: const []));
    for (final child in node.children) {
      visit(child);
    }
  }

  for (final node in nodes) {
    visit(node);
  }
  return result;
}

TreeNode _copyNode(TreeNode source, {required List<TreeNode> children}) {
  return TreeNode(
    id: source.id,
    projectId: source.projectId,
    parentId: source.parentId,
    nodeTypeKey: source.nodeTypeKey,
    name: source.name,
    sortOrder: source.sortOrder,
    fieldValues: source.fieldValues,
    children: children,
    createdAt: source.createdAt,
    updatedAt: source.updatedAt,
  );
}
