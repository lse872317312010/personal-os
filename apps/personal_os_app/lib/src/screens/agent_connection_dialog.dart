import 'package:flutter/material.dart';
import '../controller/automatic_agent_controller.dart';

/// One-time connection setup. Keys are entered here and sent to the protected
/// local service; summaries used for editing contain only has_api_key.
final class AgentConnectionDialog extends StatefulWidget {
  const AgentConnectionDialog({required this.agent, this.connection, super.key});
  final AutomaticAgentController agent;
  final Map<String, Object?>? connection;
  @override
  State<AgentConnectionDialog> createState() => _AgentConnectionDialogState();
}

final class _AgentConnectionDialogState extends State<AgentConnectionDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name, _url, _model;
  final _key = TextEditingController();
  late String _kind;
  bool _clearKey = false;
  @override
  void initState() {
    super.initState();
    final value = widget.connection;
    _kind = value?['kind'] as String? ?? 'chat-completions';
    _name = TextEditingController(text: value?['label'] as String? ?? '');
    _url = TextEditingController(text: (value?['agent_url'] as String?)?.isNotEmpty == true ? value!['agent_url'] as String : value?['base_url'] as String? ?? '');
    _model = TextEditingController(text: value?['model'] as String? ?? '');
  }
  @override
  void dispose() {
    _key.clear(); _key.dispose(); _name.dispose(); _url.dispose(); _model.dispose();
    super.dispose();
  }
  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final saved = await widget.agent.saveConnection(<String, Object?>{
      if (widget.connection != null) 'id': widget.connection!['id'],
      'label': _name.text.trim(), 'kind': _kind, 'model': _model.text.trim(),
      if (_kind == 'agent-http') 'agent_url': _url.text.trim() else 'base_url': _url.text.trim(),
      'api_key': _key.text.trim(), 'clear_api_key': _clearKey,
    });
    if (saved && mounted) { _key.clear(); Navigator.of(context).pop(); }
  }
  Future<void> _remove() async {
    if (await widget.agent.removeConnection(widget.connection!['id'] as String) && mounted) {
      _key.clear(); Navigator.of(context).pop();
    }
  }
  String? _required(String? value) => value?.trim().isNotEmpty == true ? null : '请填写这一项';
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.agent,
    builder: (context, _) => AlertDialog(
      title: Text(widget.connection == null ? '接入其他 AI' : '编辑 AI 连接'),
      content: SizedBox(width: 460, child: SingleChildScrollView(child: Form(
        key: _form,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          const Text('设置一次，之后计划和复盘自动发送与接收。'),
          const SizedBox(height: 16),
          TextFormField(key: const Key('connection-name'), controller: _name, enabled: !widget.agent.busy, maxLength: 80, validator: _required, decoration: const InputDecoration(labelText: '连接名称', hintText: '例如：我的本机模型', counterText: '')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(key: const Key('connection-kind'), initialValue: _kind, isExpanded: true,
            decoration: const InputDecoration(labelText: '服务类型'),
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem(value: 'chat-completions', child: Text('OpenAI 兼容 API')),
              DropdownMenuItem(value: 'responses', child: Text('Responses API')),
              DropdownMenuItem(value: 'agent-http', child: Text('自建 HTTP Agent')),
            ], onChanged: widget.agent.busy ? null : (value) => setState(() => _kind = value!),
          ),
          const SizedBox(height: 12),
          TextFormField(key: const Key('connection-url'), controller: _url, enabled: !widget.agent.busy,
            keyboardType: TextInputType.url, autocorrect: false, enableSuggestions: false, validator: _required,
            decoration: InputDecoration(labelText: _kind == 'agent-http' ? 'Agent 地址' : 'API 基础地址', hintText: _kind == 'agent-http' ? 'http://127.0.0.1:9000/agent' : 'https://api.example.com/v1', helperText: _kind == 'agent-http' ? '填写接收 Agent 请求的完整地址' : '填写基础地址，通常以 /v1 结尾'),
          ),
          const SizedBox(height: 12),
          TextFormField(key: const Key('connection-model'), controller: _model, enabled: !widget.agent.busy, validator: _required, autocorrect: false, enableSuggestions: false, decoration: const InputDecoration(labelText: '模型名称', hintText: '填写服务提供的模型 ID')),
          const SizedBox(height: 12),
          TextFormField(key: const Key('connection-key'), controller: _key, enabled: !widget.agent.busy, obscureText: true, autocorrect: false, enableSuggestions: false, autofillHints: const <String>[],
            decoration: InputDecoration(labelText: 'API Key（服务需要时填写）', helperMaxLines: 3, helperText: widget.connection?['has_api_key'] == true ? '已保存密钥，留空保持。地址或服务类型改变时请重新填写。' : '只填密钥，不带 Bearer。保存后加密留在本机。'),
          ),
          if (widget.connection?['has_api_key'] == true) CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('清除已保存的密钥'), value: _clearKey, onChanged: widget.agent.busy ? null : (value) => setState(() => _clearKey = value!)),
          const SizedBox(height: 12),
          const Text('生成计划时，会向这个服务发送当前目标、现状和相关历史。', style: TextStyle(fontSize: 12)),
          if (widget.agent.error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(widget.agent.error!, key: const Key('connection-error'))),
          if (widget.connection != null) TextButton(onPressed: widget.agent.busy ? null : _remove, child: const Text('删除连接（保留目标与历史）')),
        ]),
      ))),
      actions: <Widget>[
        TextButton(onPressed: widget.agent.busy ? null : () => Navigator.of(context).pop(), child: const Text('取消')),
        FilledButton(key: const Key('save-agent-connection'), onPressed: widget.agent.busy ? null : _save, child: Text(widget.agent.busy ? '保存中…' : '保存并使用')),
      ],
    ),
  );
}
