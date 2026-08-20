import 'package:flutter/material.dart';

import '../controller/app_controller.dart';

final class CaptureScreen extends StatefulWidget {
  const CaptureScreen({required this.controller, super.key});

  final AppController controller;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

final class _CaptureScreenState extends State<CaptureScreen> {
  final _blobRef = TextEditingController(text: 'blob://vault/portrait-demo');
  final _context = TextEditingController(text: '自然光、正面、无滤镜');

  @override
  void dispose() {
    _blobRef.dispose();
    _context.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.controller.submission == SubmissionStatus.running;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Text('选择体验数据', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Card(
          child: ListTile(
            leading: Icon(Icons.science_outlined),
            title: Text('内置合成示例'),
            subtitle: Text('不会读取相册、不会联网；结果仅用于验证产品流程'),
            trailing: Icon(Icons.check_circle),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('blob-reference'),
          controller: _blobRef,
          decoration: const InputDecoration(
            labelText: '本地资料引用（高级）',
            helperText: '当前不开放相册导入，仅接受 blob:// 测试引用',
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _context,
          decoration: const InputDecoration(
            labelText: '观察说明',
            helperText: '例如：自然光、正面、无滤镜',
          ),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          key: const Key('analysis-consent'),
          value: widget.controller.consentGranted,
          onChanged: widget.controller.setConsent,
          title: const Text('我同意进行本次外貌分析'),
          subtitle: const Text('敏感等级 D3；仅用于本次离线体验，可随时关闭'),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('analyze-reference'),
          onPressed: busy
              ? null
              : () => widget.controller.analyzeBlobReference(
                    blobReference: _blobRef.text.trim(),
                    observationContext: _context.text.trim(),
                  ),
          child: Text(busy ? '正在生成示例建议…' : '生成离线示例建议'),
        ),
        if (widget.controller.errorCode case final error?) ...<Widget>[
          const SizedBox(height: 12),
          Text(_errorMessage(error), style: const TextStyle(color: Colors.red)),
        ],
      ],
    );
  }
}

String _errorMessage(String code) => switch (code) {
      'consent_required' => '请先勾选本次分析授权。',
      'blob_reference_required' => '资料引用必须以 blob:// 开头。',
      'vault_locked' => '本地保险库已锁定，请重新进入。',
      _ => '暂时无法生成（$code），请重试。',
    };
