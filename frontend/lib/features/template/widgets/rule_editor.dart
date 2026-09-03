import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_endpoints.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../models/template.dart';
import '../../../shared/widgets/confirm_dialog.dart';

class RuleEditor extends ConsumerStatefulWidget {
  const RuleEditor({
    required this.templateId,
    required this.rules,
    required this.nodeTypes,
    required this.isEditable,
    this.onChanged,
    super.key,
  });

  final String templateId;
  final List<NodeRule> rules;
  final List<NodeType> nodeTypes;
  final bool isEditable;
  final VoidCallback? onChanged;

  @override
  ConsumerState<RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends ConsumerState<RuleEditor> {
  late List<NodeRule> _rules;

  @override
  void initState() {
    super.initState();
    _rules = List<NodeRule>.from(widget.rules);
  }

  @override
  void didUpdateWidget(covariant RuleEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.templateId != widget.templateId) {
      _rules = List<NodeRule>.from(widget.rules);
    }
  }

  Future<void> _openEditor([NodeRule? rule]) async {
    final saved = await showDialog<NodeRule>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _RuleDialog(
        templateId: widget.templateId,
        nodeTypes: widget.nodeTypes,
        rule: rule,
      ),
    );
    if (saved == null || !mounted) return;
    setState(() {
      final index = _rules.indexWhere((item) => item.id == saved.id);
      if (index == -1) {
        _rules.add(saved);
      } else {
        _rules[index] = saved;
      }
    });
    widget.onChanged?.call();
  }

  Future<void> _delete(NodeRule rule) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除规则',
      message: '确认删除这条节点规则？',
      confirmLabel: '删除',
      cancelLabel: '取消',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref.read(apiClientProvider).delete<dynamic>(
            ApiEndpoints.templateRule(widget.templateId, rule.id),
          );
      setState(() => _rules.removeWhere((item) => item.id == rule.id));
      widget.onChanged?.call();
    } catch (error) {
      if (mounted) _showError('删除规则失败：$error');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  String _nodeName(String id) {
    for (final nodeType in widget.nodeTypes) {
      if (nodeType.id == id || nodeType.key == id) return nodeType.name;
    }
    return '未知节点';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('节点规则',
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 4),
                      const Text('规定哪些节点可以出现在哪里，以及出现次数。'),
                    ],
                  ),
                ),
                if (widget.isEditable)
                  FilledButton.icon(
                    onPressed:
                        widget.nodeTypes.isEmpty ? null : () => _openEditor(),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('添加规则'),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            if (_rules.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 46),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFD),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFD7DFEA)),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.device_hub_outlined, size: 38),
                    const SizedBox(height: 10),
                    Text(
                      widget.nodeTypes.isEmpty ? '请先创建节点类型' : '暂无节点规则',
                    ),
                  ],
                ),
              )
            else
              ..._rules.map((rule) {
                final root =
                    rule.isRootRule || (rule.parentNodeTypeId?.isEmpty ?? true);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: root
                        ? const Color(0xFFFFF7E6)
                        : const Color(0xFFF8FAFD),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: root
                            ? const Color(0xFFF1C36D)
                            : const Color(0xFFD7DFEA),
                      ),
                    ),
                    child: _RuleRow(
                      root: root,
                      parentName:
                          root ? '根节点' : _nodeName(rule.parentNodeTypeId!),
                      childName: _nodeName(rule.childNodeTypeId),
                      minCount: rule.minCount,
                      maxCount: rule.maxCount,
                      editable: widget.isEditable,
                      onEdit: () => _openEditor(rule),
                      onDelete: () => _delete(rule),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({
    required this.root,
    required this.parentName,
    required this.childName,
    required this.minCount,
    required this.maxCount,
    required this.editable,
    required this.onEdit,
    required this.onDelete,
  });

  final bool root;
  final String parentName;
  final String childName;
  final int minCount;
  final int maxCount;
  final bool editable;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final path = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: root ? const Color(0xFFFFE6B8) : const Color(0xFFE9F1FB),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(
            root ? Icons.home_outlined : Icons.subdirectory_arrow_right,
            size: 19,
          ),
        ),
        const SizedBox(width: 11),
        Flexible(
          child: Text(
            parentName,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Icon(Icons.arrow_forward_rounded, size: 18),
        ),
        Flexible(
          child: Text(
            childName,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
    final controls = Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _CountPill(label: '最少 $minCount'),
        _CountPill(label: maxCount == 0 ? '不限上限' : '最多 $maxCount'),
        if (editable)
          IconButton(
            tooltip: '编辑规则',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
        if (editable)
          IconButton(
            tooltip: '删除规则',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 650;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    path,
                    const SizedBox(height: 12),
                    controls,
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: path),
                    const SizedBox(width: 12),
                    controls,
                  ],
                ),
        );
      },
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFD7DFEA)),
        ),
        child: Text(label, style: Theme.of(context).textTheme.labelMedium),
      );
}

/// 父节点下拉框中代表“根节点”的虚拟选项，与真实节点类型 ID 不会冲突。
const _rootParentValue = '__root__';

class _RuleDialog extends ConsumerStatefulWidget {
  const _RuleDialog({
    required this.templateId,
    required this.nodeTypes,
    this.rule,
  });

  final String templateId;
  final List<NodeType> nodeTypes;
  final NodeRule? rule;

  @override
  ConsumerState<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends ConsumerState<_RuleDialog> {
  final _formKey = GlobalKey<FormState>();
  String? _parentId;
  String? _childId;
  late final TextEditingController _min;
  late final TextEditingController _max;
  bool _saving = false;
  String? _error;

  bool get _isRoot => _parentId == _rootParentValue;

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    _parentId = rule == null
        ? null
        : (rule.isRootRule ? _rootParentValue : rule.parentNodeTypeId);
    _childId = rule?.childNodeTypeId;
    _min = TextEditingController(text: '${rule?.minCount ?? 0}');
    _max = TextEditingController(text: '${rule?.maxCount ?? 0}');
  }

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final min = int.parse(_min.text);
    final max = int.parse(_max.text);
    try {
      final apiClient = ref.read(apiClientProvider);
      final response = widget.rule == null
          ? await apiClient.post<dynamic>(
              ApiEndpoints.templateRules(widget.templateId),
              data: {
                'parent_node_type_id': _isRoot ? '' : _parentId,
                'child_node_type_id': _childId,
                'min_count': min,
                'max_count': max,
                'is_root_rule': _isRoot,
              },
            )
          : await apiClient.put<dynamic>(
              ApiEndpoints.templateRule(
                widget.templateId,
                widget.rule!.id,
              ),
              data: {
                'child_node_type_id': _childId,
                'min_count': min,
                'max_count': max,
              },
            );
      final body = response.data as Map;
      final saved = NodeRule.fromJson(
        Map<String, dynamic>.from(body['data'] as Map? ?? body),
      );
      if (mounted) Navigator.pop(context, saved);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '保存失败：$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.rule != null;
    return AlertDialog(
      title: Text(editing ? '编辑节点规则' : '添加节点规则'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: _parentId,
                decoration: const InputDecoration(
                  labelText: '父节点类型',
                  helperText: '选择“根节点”即为文档树的起始节点规则',
                ),
                items: [
                  const DropdownMenuItem(
                    value: _rootParentValue,
                    child: Text('根节点'),
                  ),
                  ...widget.nodeTypes.map(
                    (nodeType) => DropdownMenuItem(
                      value: nodeType.id,
                      child: Text(nodeType.name),
                    ),
                  ),
                ],
                onChanged: editing
                    ? null
                    : (value) => setState(() => _parentId = value),
                validator: (value) => value == null ? '请选择父节点' : null,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: _childId,
                decoration: const InputDecoration(labelText: '子节点类型'),
                items: widget.nodeTypes
                    .map(
                      (nodeType) => DropdownMenuItem(
                        value: nodeType.id,
                        child: Text(nodeType.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _childId = value),
                validator: (value) => value == null ? '请选择子节点' : null,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _min,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '最少数量'),
                      validator: _countValidator,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _max,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '最多数量',
                        helperText: '0 表示不限制',
                      ),
                      validator: (value) {
                        final base = _countValidator(value);
                        if (base != null) return base;
                        final max = int.parse(value!);
                        final min = int.tryParse(_min.text) ?? 0;
                        return max != 0 && max < min ? '不能小于最少数量' : null;
                      },
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '保存中…' : '保存'),
        ),
      ],
    );
  }

  String? _countValidator(String? value) {
    final parsed = int.tryParse(value ?? '');
    if (parsed == null || parsed < 0) return '请输入非负整数';
    return null;
  }
}
