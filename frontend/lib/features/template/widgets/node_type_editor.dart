import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_endpoints.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../models/template.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/reorder_handle.dart';
import 'field_editor.dart';

class NodeTypeEditor extends ConsumerStatefulWidget {
  const NodeTypeEditor({
    required this.templateId,
    required this.nodeType,
    required this.isEditable,
    required this.onDeleted,
    required this.onChanged,
    super.key,
  });

  final String templateId;
  final NodeType nodeType;
  final bool isEditable;
  final VoidCallback onDeleted;
  final VoidCallback onChanged;

  @override
  ConsumerState<NodeTypeEditor> createState() => _NodeTypeEditorState();
}

class _NodeTypeEditorState extends ConsumerState<NodeTypeEditor> {
  late final TextEditingController _name;
  late final TextEditingController _key;
  late final TextEditingController _description;
  late List<Field> _fields;
  Timer? _debounce;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.nodeType.name);
    _key = TextEditingController(text: widget.nodeType.key);
    _description = TextEditingController(text: widget.nodeType.description);
    _fields = _ordered(widget.nodeType.fields);
  }

  @override
  void didUpdateWidget(covariant NodeTypeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodeType.id != widget.nodeType.id ||
        oldWidget.nodeType != widget.nodeType) {
      _debounce?.cancel();
      _name.text = widget.nodeType.name;
      _key.text = widget.nodeType.key;
      _description.text = widget.nodeType.description;
      _fields = _ordered(widget.nodeType.fields);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _key.dispose();
    _description.dispose();
    super.dispose();
  }

  void _scheduleSave() {
    if (!widget.isEditable) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _saveNodeType);
  }

  Future<void> _saveNodeType() async {
    if (_name.text.trim().isEmpty || _key.text.trim().isEmpty || _saving) {
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(apiClientProvider).put<dynamic>(
        ApiEndpoints.templateNodeType(
          widget.templateId,
          widget.nodeType.id,
        ),
        data: {
          'name': _name.text.trim(),
          'key': _key.text.trim(),
          'description': _description.text.trim(),
        },
      );
      widget.onChanged();
    } catch (error) {
      if (mounted) _showError('节点类型保存失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteNodeType() async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除节点类型',
      message: '确认删除“${widget.nodeType.name}”及其字段？',
      confirmLabel: '删除',
      cancelLabel: '取消',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref.read(apiClientProvider).delete<dynamic>(
            ApiEndpoints.templateNodeType(
              widget.templateId,
              widget.nodeType.id,
            ),
          );
      widget.onDeleted();
    } catch (error) {
      if (mounted) _showError('删除失败：$error');
    }
  }

  Future<void> _openFieldEditor([Field? field]) async {
    await showDialog<Field>(
      context: context,
      barrierDismissible: false,
      builder: (context) => FieldEditorDialog(
        templateId: widget.templateId,
        nodeTypeId: widget.nodeType.id,
        field: field,
        onSaved: (saved) {
          setState(() {
            final index = _fields.indexWhere((item) => item.id == saved.id);
            if (index == -1) {
              _fields.add(saved);
            } else {
              _fields[index] = saved;
            }
          });
          widget.onChanged();
        },
      ),
    );
  }

  Future<void> _deleteField(Field field) async {
    if (!field.deletable) return;
    final confirmed = await showConfirmDialog(
      context,
      title: '删除字段',
      message: '确认删除字段“${field.name}”？',
      confirmLabel: '删除',
      cancelLabel: '取消',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref.read(apiClientProvider).delete<dynamic>(
            ApiEndpoints.templateField(
              widget.templateId,
              widget.nodeType.id,
              field.id,
            ),
          );
      setState(() => _fields.removeWhere((item) => item.id == field.id));
      widget.onChanged();
    } catch (error) {
      if (mounted) _showError('删除字段失败：$error');
    }
  }

  Future<void> _reorderFields(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    await _moveField(oldIndex, newIndex);
  }

  Future<void> _moveField(int oldIndex, int newIndex) async {
    if (!widget.isEditable || oldIndex == newIndex) return;
    final previous = List<Field>.from(_fields);
    setState(() {
      final item = _fields.removeAt(oldIndex);
      _fields.insert(newIndex, item);
    });
    try {
      await ref.read(apiClientProvider).put<dynamic>(
        ApiEndpoints.templateFieldSort(
          widget.templateId,
          widget.nodeType.id,
        ),
        data: {'ids': _fields.map((item) => item.id).toList()},
      );
      widget.onChanged();
    } catch (error) {
      if (mounted) {
        setState(() => _fields = previous);
        _showError('字段排序失败：$error');
      }
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
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE9F1FB),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.account_tree_outlined,
                    color: Color(0xFF1565C0),
                    size: 21,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('节点类型设置',
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(
                        _saving ? '正在自动保存…' : '修改后自动保存',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (widget.isEditable)
                  IconButton(
                    tooltip: '删除节点类型',
                    onPressed: _deleteNodeType,
                    color: Theme.of(context).colorScheme.error,
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 700;
                final name = TextField(
                  controller: _name,
                  enabled: widget.isEditable,
                  onChanged: (_) => _scheduleSave(),
                  decoration: const InputDecoration(labelText: '节点类型名称'),
                );
                final key = TextField(
                  controller: _key,
                  enabled: widget.isEditable,
                  onChanged: (_) => _scheduleSave(),
                  decoration: const InputDecoration(labelText: '节点类型 Key'),
                );
                if (!wide) {
                  return Column(
                    children: [name, const SizedBox(height: 12), key],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: name),
                    const SizedBox(width: 12),
                    Expanded(child: key),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              enabled: widget.isEditable,
              onChanged: (_) => _scheduleSave(),
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '说明',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Text('字段列表', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(width: 10),
                Chip(label: Text('${_fields.length}')),
                const Spacer(),
                if (widget.isEditable)
                  FilledButton.tonalIcon(
                    onPressed: _openFieldEditor,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('添加字段'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_fields.isEmpty)
              const _EmptyFields()
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                primary: false,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                proxyDecorator: reorderProxyDecorator,
                itemCount: _fields.length,
                onReorder: _reorderFields,
                itemBuilder: (context, index) {
                  final field = _fields[index];
                  return Padding(
                    key: ValueKey(field.id),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _FieldRow(
                      index: index,
                      field: field,
                      isEditable: widget.isEditable,
                      onEdit: () => _openFieldEditor(field),
                      onDelete: () => _deleteField(field),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.index,
    required this.field,
    required this.isEditable,
    required this.onEdit,
    required this.onDelete,
  });

  final int index;
  final Field field;
  final bool isEditable;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF8FAFD),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: isEditable ? onEdit : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              if (isEditable)
                ReorderHandle(index: index)
              else
                Icon(
                  field.deletable ? Icons.drag_indicator : Icons.lock_outline,
                  size: 19,
                  color: const Color(0xFF8390A6),
                ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(field.name,
                        style: Theme.of(context).textTheme.titleSmall),
                    Text(field.key,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              Expanded(
                child: Text(_fieldTypeLabel(field.fieldType)),
              ),
              SizedBox(
                width: 52,
                child: field.required
                    ? const Tooltip(
                        message: '必填',
                        child: Icon(Icons.check_circle_outline,
                            color: Color(0xFF18794E), size: 20),
                      )
                    : const SizedBox.shrink(),
              ),
              if (isEditable) ...[
                IconButton(
                  tooltip: '编辑字段',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
                if (field.deletable)
                  IconButton(
                    tooltip: '删除字段',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                  )
                else
                  const SizedBox(width: 48),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyFields extends StatelessWidget {
  const _EmptyFields();

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFD7DFEA)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text('暂无字段', textAlign: TextAlign.center),
      );
}

List<Field> _ordered(List<Field> fields) {
  final result = List<Field>.from(fields);
  result.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  return result;
}

String _fieldTypeLabel(String value) => switch (value) {
      'textarea' => '多行文本',
      'select' => '单选',
      'multiselect' => '多选',
      'checkbox' => '复选框',
      'date' => '日期',
      _ => '单行文本',
    };
