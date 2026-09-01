import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_endpoints.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../models/template.dart';

class FieldEditorDialog extends ConsumerStatefulWidget {
  const FieldEditorDialog({
    required this.templateId,
    required this.nodeTypeId,
    required this.onSaved,
    this.field,
    super.key,
  });

  final String templateId;
  final String nodeTypeId;
  final Field? field;
  final ValueChanged<Field> onSaved;

  @override
  ConsumerState<FieldEditorDialog> createState() => _FieldEditorDialogState();
}

class _FieldEditorDialogState extends ConsumerState<FieldEditorDialog> {
  static const _types = <String, String>{
    'text': '单行文本',
    'textarea': '多行文本',
    'select': '单选',
    'multiselect': '多选',
    'checkbox': '复选框',
    'date': '日期',
  };

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _key;
  late final TextEditingController _defaultValue;
  late final TextEditingController _description;
  late String _fieldType;
  late bool _required;
  late List<String> _options;
  bool _saving = false;
  String? _error;

  bool get _hasOptions => _fieldType == 'select' || _fieldType == 'multiselect';

  @override
  void initState() {
    super.initState();
    final field = widget.field;
    _name = TextEditingController(text: field?.name ?? '');
    _key = TextEditingController(text: field?.key ?? '');
    _defaultValue = TextEditingController(
      text: field?.defaultValue?.toString() ?? '',
    );
    _description = TextEditingController(text: field?.description ?? '');
    _fieldType = field?.fieldType ?? 'text';
    _required = field?.required ?? false;
    _options = List<String>.from(field?.options ?? const []);
  }

  @override
  void dispose() {
    _name.dispose();
    _key.dispose();
    _defaultValue.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final payload = <String, dynamic>{
      'name': _name.text.trim(),
      'key': _key.text.trim(),
      'field_type': _fieldType,
      'required': _required,
      'default_value': _defaultValue.text,
      'description': _description.text.trim(),
      'options': _hasOptions ? jsonEncode(_options) : '',
    };
    try {
      final apiClient = ref.read(apiClientProvider);
      final response = widget.field == null
          ? await apiClient.post<dynamic>(
              ApiEndpoints.templateFields(
                widget.templateId,
                widget.nodeTypeId,
              ),
              data: payload,
            )
          : await apiClient.put<dynamic>(
              ApiEndpoints.templateField(
                widget.templateId,
                widget.nodeTypeId,
                widget.field!.id,
              ),
              data: payload,
            );
      final body = response.data as Map;
      final saved = Field.fromJson(
        Map<String, dynamic>.from(body['data'] as Map? ?? body),
      );
      widget.onSaved(saved);
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
    final isEditing = widget.field != null;
    return AlertDialog(
      title: Text(isEditing ? '编辑字段' : '添加字段'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _name,
                        autofocus: !isEditing,
                        decoration: const InputDecoration(labelText: '字段名称'),
                        validator: _requiredText,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _key,
                        decoration: const InputDecoration(labelText: '字段 Key'),
                        validator: _requiredText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: _fieldType,
                  decoration: const InputDecoration(labelText: '字段类型'),
                  items: _types.entries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _fieldType = value);
                  },
                ),
                const SizedBox(height: 14),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('必填字段'),
                  subtitle: const Text('创建节点时必须填写此字段'),
                  value: _required,
                  onChanged: (value) => setState(() => _required = value),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _defaultValue,
                  decoration: const InputDecoration(labelText: '默认值'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _description,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '填写说明',
                    alignLabelWithHint: true,
                  ),
                ),
                if (_hasOptions) ...[
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Text(
                        '选项',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => setState(() => _options.add('')),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('添加选项'),
                      ),
                    ],
                  ),
                  if (_options.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('至少添加一个可选值'),
                    ),
                  ...List.generate(_options.length, (index) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: _options[index],
                              decoration: InputDecoration(
                                labelText: '选项 ${index + 1}',
                              ),
                              onChanged: (value) => _options[index] = value,
                              validator: (value) => _hasOptions &&
                                      (value == null || value.trim().isEmpty)
                                  ? '选项不能为空'
                                  : null,
                            ),
                          ),
                          IconButton(
                            tooltip: '删除选项',
                            onPressed: () =>
                                setState(() => _options.removeAt(index)),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_rounded),
          label: Text(_saving ? '保存中' : '保存'),
        ),
      ],
    );
  }

  String? _requiredText(String? value) =>
      value == null || value.trim().isEmpty ? '此项不能为空' : null;
}
