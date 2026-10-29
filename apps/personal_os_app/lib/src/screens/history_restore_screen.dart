import 'dart:async';
import 'package:flutter/material.dart';
import '../agent_interop/automatic_agent_gateway.dart';
import '../agent_interop/history_file_picker.dart';
import '../agent_interop/web_history_restore.dart';

/// Runs before composition can create a session or resume AI requests.
final class HistoryRestoreScreen extends StatefulWidget {
  const HistoryRestoreScreen(
      {required this.gateway,
      required this.onContinue,
      this.pickFile = pickHistoryFile,
      super.key});
  final AutomaticAgentGateway gateway;
  final Future<void> Function() onContinue;
  final Future<String?> Function() pickFile;
  @override
  State<HistoryRestoreScreen> createState() => _HistoryRestoreScreenState();
}

final class _HistoryRestoreScreenState extends State<HistoryRestoreScreen> {
  late final WebHistoryRestore _restore = WebHistoryRestore(widget.gateway);
  PreparedHistoryRestore? _prepared;
  bool _busy = true, _empty = false, _restored = false;
  String? _message;
  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  Future<void> _check() async {
    try {
      final value = await _restore.status();
      if (!mounted) return;
      setState(() {
        _empty = value['empty'] == true;
        _message = _empty ? null : '此网关已有历史，不能覆盖。请使用空白网关恢复。';
      });
    } on Object {
      if (mounted) setState(() => _message = '无法确认网关是否为空，请检查连接后重新打开。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _prepared = null;
      _message = null;
    });
    try {
      final source = await widget.pickFile();
      if (!mounted || source == null) return;
      final prepared = await _restore.prepare(source);
      if (mounted) setState(() => _prepared = prepared);
    } on AgentGatewayException {
      if (mounted)
        setState(() {
          _empty = false;
          _message = '网关状态已变化或暂不可用，请重新打开检查；历史未写入。';
        });
    } on Object {
      if (mounted) setState(() => _message = '文件无法通过校验：请检查格式、大小及事件版本顺序。历史未写入。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    if (_busy) return;
    final prepared = _prepared;
    if (prepared == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _restore.restore(prepared);
      if (mounted)
        setState(() {
          _restored = true;
          _prepared = null;
        });
    } on AgentGatewayException catch (error) {
      if (mounted)
        setState(() {
          _prepared = null;
          _empty = false;
          _message = error.code == 'history_conflict'
              ? '网关已有历史、修订号已变化或正在写入，恢复已拒绝。请重新打开检查。'
              : '未能确认恢复结果，请先重新打开应用核对；不要重复导入。';
        });
    } on Object {
      if (mounted)
        setState(() {
          _prepared = null;
          _empty = false;
          _message = '未能确认恢复结果，请先重新打开应用核对；不要重复导入。';
        });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _continue() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onContinue();
    } on Object {
      if (mounted) setState(() => _message = '无法打开应用，请检查网关后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      body: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(24),
                  children: <Widget>[
                    Text(_restored ? '历史已恢复' : '开始或恢复个人历史',
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 16),
                    const Text(
                        '恢复仅写入空白网关。文件先在此设备校验，确认后才发送到你的网关；不会恢复 AI 连接或登录凭据，也不会调用 AI。'),
                    if (_message != null) ...<Widget>[
                      const SizedBox(height: 16),
                      Text(_message!,
                          key: const Key('history-restore-message')),
                    ],
                    if (_busy) const LinearProgressIndicator(),
                    if (_prepared != null) ...<Widget>[
                      const SizedBox(height: 20),
                      Text(
                          '校验通过：${_prepared!.preview.events.length} 个事件，${_prepared!.preview.projections.length} 个对象。',
                          key: const Key('history-restore-preview')),
                      Text(
                          '导出时间：${_prepared!.preview.exportedAt.toIso8601String()}\n源历史修订号：${_prepared!.preview.sourceRevision}'),
                      const Text('兼容性校验不证明文件来源或内容真实。仅恢复你信任的文件。'),
                      const SizedBox(height: 12),
                      FilledButton(
                          onPressed: _busy ? null : _confirm,
                          key: const Key('history-restore-confirm'),
                          child: const Text('确认恢复到空白网关')),
                    ],
                    if (_empty && !_restored) ...<Widget>[
                      const SizedBox(height: 16),
                      OutlinedButton(
                          onPressed: _busy ? null : _pick,
                          key: const Key('history-restore-select'),
                          child: const Text('选择历史 JSON 文件')),
                    ],
                    const SizedBox(height: 20),
                    if (_restored || !_empty)
                      const Text('进入应用后，待完成的复盘或下一轮计划可能使用所选 AI 的额度。请确认后继续。'),
                    FilledButton(
                        onPressed: _busy ? null : _continue,
                        key: const Key('history-restore-continue'),
                        child:
                            Text(_restored || !_empty ? '确认，进入应用' : '开始新的记录')),
                  ]))));
}
