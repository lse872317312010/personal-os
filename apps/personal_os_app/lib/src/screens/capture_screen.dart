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
        TextField(
          key: const Key('blob-reference'),
          controller: _blobRef,
          decoration: const InputDecoration(
            labelText: 'Vault blob reference',
            helperText: '只接收 blob:// 引用，不接收或缓存原始照片字节',
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _context,
          decoration: const InputDecoration(labelText: '观察环境'),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          key: const Key('analysis-consent'),
          value: widget.controller.consentGranted,
          onChanged: widget.controller.setConsent,
          title: const Text('授权本次 D3 外貌派生分析'),
          subtitle: const Text('撤销后不得发起模型调用'),
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
          child: Text(busy ? '分析中…' : '分析引用'),
        ),
        if (widget.controller.errorCode case final error?) ...<Widget>[
          const SizedBox(height: 12),
          Text('未执行：$error', style: const TextStyle(color: Colors.red)),
        ],
      ],
    );
  }
}
