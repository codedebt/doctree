import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_endpoints.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../models/node.dart';
import '../../../models/template.dart';

class NodeDetailPanel extends ConsumerStatefulWidget {
  const NodeDetailPanel({
    required this.node,
    required this.template,
    required this.projectId,
    required this.isEditable,
    required this.onNodeUpdated,
    super.key,
  });

  final TreeNode node;
  final Template template;
  final String projectId;
  final bool isEditable;
  final VoidCallback onNodeUpdated;

  @override
  ConsumerState<NodeDetailPanel> createState() => _NodeDetailPanelState();
}

class _NodeDetailPanelState extends ConsumerState<NodeDetailPanel> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _name;
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, dynamic> _values = {};
  bool _saving = false;

  NodeType? get _nodeType => widget.template.nodeTypes
      .where((item) => item.key == widget.node.nodeTypeKey)
      .firstOrNull;

  @override
  void initState() {
    super.initState();
    _loadNode();
  }

  @override
  void didUpdateWidget(covariant NodeDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.id != widget.node.id ||
        oldWidget.node.updatedAt != widget.node.updatedAt) {
      _disposeControllers();
      _loadNode();
    }
  }

  void _loadNode() {
    _name = TextEditingController(text: widget.node.name);
    _values.clear();
    final existing = {
      for (final value in widget.node.fieldValues) value.fieldKey: value.value,
    };
    for (final field in _nodeType?.fields ?? const <Field>[]) {
      final value = existing.containsKey(field.key)
          ? existing[field.key]
          : field.defaultValue;
      if (field.fieldType == 'multiselect') {
        _values[field.key] = _asStringList(value);
      } else if (field.fieldType == 'checkbox') {
        _values[field.key] = _asBool(value);
      } else {
        _values[field.key] = value?.toString() ?? '';
      }
      if (const {'text', 'textarea', 'date'}.contains(field.fieldType)) {
        _controllers[field.key] =
            TextEditingController(text: _values[field.key]?.toString() ?? '');
      }
    }
  }

  void _disposeControllers() {
    _name.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    setState(() => _saving = true);
    try {
      final values = <String, String>{};
      for (final field in _nodeType!.fields) {
        final value = _values[field.key];
        values[field.key] = switch (field.fieldType) {
          'multiselect' => jsonEncode(value ?? const <String>[]),
          'checkbox' => (value == true).toString(),
          _ => value?.toString() ?? '',
        };
      }
      await ref.read(apiClientProvider).put<dynamic>(
        ApiEndpoints.projectNode(widget.projectId, widget.node.id),
        data: {
          'name': _name.text.trim(),
          'field_values': values,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('节点已保存')),
      );
      widget.onNodeUpdated();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败：$error'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nodeType = _nodeType;
    if (nodeType == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('当前模板中找不到此节点类型，无法显示节点详情。'),
        ),
      );
    }
    final fields = List<Field>.from(nodeType.fields)
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text('节点详情',
                                  style:
                                      Theme.of(context).textTheme.titleLarge),
                            ),
                            Chip(
                              avatar:
                                  const Icon(Icons.category_outlined, size: 17),
                              label: Text(nodeType.name),
                              side: BorderSide.none,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text('创建时间：${_formatDateTime(widget.node.createdAt)}'),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _name,
                          enabled: widget.isEditable,
                          decoration: const InputDecoration(
                            labelText: '节点名称 *',
                            prefixIcon: Icon(Icons.title_rounded),
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                                  ? '节点名称不能为空'
                                  : null,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('字段内容',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 20),
                        if (fields.isEmpty)
                          const Text('此节点类型没有自定义字段。')
                        else
                          ...fields.map(
                            (field) => Padding(
                              padding: const EdgeInsets.only(bottom: 18),
                              child: _buildField(field),
                            ),
                          ),
                        if (widget.isEditable) ...[
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                              onPressed: _saving ? null : _save,
                              icon: _saving
                                  ? const SizedBox.square(
                                      dimension: 17,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.save_outlined),
                              label: const Text('保存'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(Field field) {
    final label = '${field.name}${field.required ? ' *' : ''}';
    switch (field.fieldType) {
      case 'textarea':
        return TextFormField(
          controller: _controllers[field.key],
          enabled: widget.isEditable,
          maxLines: 5,
          decoration: InputDecoration(
            labelText: label,
            hintText: field.placeholder.isEmpty ? null : field.placeholder,
            alignLabelWithHint: true,
          ),
          validator: (value) => _validateRequired(field, value),
          onSaved: (value) => _values[field.key] = value?.trim() ?? '',
        );
      case 'select':
        final options = field.options;
        final current = _values[field.key]?.toString() ?? '';
        return DropdownButtonFormField<String>(
          value: options.contains(current) ? current : null,
          decoration: InputDecoration(labelText: label),
          items: options
              .map((option) =>
                  DropdownMenuItem(value: option, child: Text(option)))
              .toList(),
          onChanged: widget.isEditable
              ? (value) => setState(() => _values[field.key] = value ?? '')
              : null,
          validator: (value) => _validateRequired(field, value),
        );
      case 'multiselect':
        final selected = _values[field.key] as List<String>? ?? <String>[];
        return FormField<List<String>>(
          initialValue: selected,
          validator: (value) =>
              field.required && (value == null || value.isEmpty)
                  ? '请选择至少一项'
                  : null,
          builder: (state) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 7,
                children: field.options.map((option) {
                  final isSelected = selected.contains(option);
                  return FilterChip(
                    label: Text(option),
                    selected: isSelected,
                    onSelected: widget.isEditable
                        ? (checked) {
                            setState(() {
                              checked
                                  ? selected.add(option)
                                  : selected.remove(option);
                              _values[field.key] = selected;
                            });
                            state.didChange(selected);
                          }
                        : null,
                  );
                }).toList(),
              ),
              if (state.hasError)
                Padding(
                  padding: const EdgeInsets.only(top: 7, left: 12),
                  child: Text(
                    state.errorText!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        );
      case 'checkbox':
        final checked = _values[field.key] == true;
        return SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          title: Text(label),
          subtitle: field.description.isEmpty ? null : Text(field.description),
          value: checked,
          onChanged: widget.isEditable
              ? (value) => setState(() => _values[field.key] = value)
              : null,
        );
      case 'date':
        return TextFormField(
          controller: _controllers[field.key],
          readOnly: true,
          enabled: true,
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: const Icon(Icons.calendar_month_outlined),
          ),
          validator: (value) => _validateRequired(field, value),
          onTap: widget.isEditable ? () => _pickDate(field) : null,
          onSaved: (value) => _values[field.key] = value?.trim() ?? '',
        );
      default:
        return TextFormField(
          controller: _controllers[field.key],
          enabled: widget.isEditable,
          decoration: InputDecoration(
            labelText: label,
            hintText: field.placeholder.isEmpty ? null : field.placeholder,
          ),
          validator: (value) => _validateRequired(field, value),
          onSaved: (value) => _values[field.key] = value?.trim() ?? '',
        );
    }
  }

  Future<void> _pickDate(Field field) async {
    final controller = _controllers[field.key]!;
    final initial = DateTime.tryParse(controller.text) ?? DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      helpText: '选择日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (selected == null) return;
    final value = _formatDate(selected);
    setState(() {
      controller.text = value;
      _values[field.key] = value;
    });
  }

  String? _validateRequired(Field field, String? value) =>
      field.required && (value == null || value.trim().isEmpty)
          ? '${field.name}不能为空'
          : null;
}

List<String> _asStringList(dynamic value) {
  if (value is List) return value.map((item) => item.toString()).toList();
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return <String>[];
  try {
    final decoded = jsonDecode(text);
    if (decoded is List) {
      return decoded.map((item) => item.toString()).toList();
    }
  } on FormatException {
    return text.split(',').map((item) => item.trim()).toList();
  }
  return <String>[];
}

bool _asBool(dynamic value) =>
    value == true || value?.toString().toLowerCase() == 'true' || value == '1';

String _formatDate(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}';
}

String _formatDateTime(DateTime? value) {
  if (value == null) return '未知';
  String two(int number) => number.toString().padLeft(2, '0');
  return '${_formatDate(value)} ${two(value.hour)}:${two(value.minute)}';
}
