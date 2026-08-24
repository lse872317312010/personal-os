import 'package:flutter/material.dart';

import '../composition/app_composition.dart';
import '../controller/app_controller.dart';
import 'observation_history_card.dart';

final class CaptureScreen extends StatefulWidget {
  const CaptureScreen(
      {required this.controller, required this.mode, super.key});

  final AppController controller;
  final AppExperienceMode mode;

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
        Card(
          child: ListTile(
            leading: const Icon(Icons.science_outlined),
            title: Text(
              widget.mode == AppExperienceMode.syntheticDemo
                  ? '内置合成示例'
                  : '安全保险库资料',
            ),
            subtitle: Text(
              widget.mode == AppExperienceMode.syntheticDemo
                  ? '不会读取相册、不会联网；结果仅用于验证产品流程'
                  : '资料只通过安全保险库引用；不会把原始内容交给 UI',
            ),
            trailing: const Icon(Icons.check_circle),
          ),
        ),
        const SizedBox(height: 16),
        ObservationHistoryCard(
            controller: widget.controller, mode: widget.mode),
        if (widget.controller.sourceAvailable) ...<Widget>[
          FilledButton.icon(
            key: const Key('pick-photo-analyze'),
            onPressed: busy
                ? null
                : () => widget.controller.pickPhotoAndAnalyze(
                      observationContext: _context.text.trim(),
                    ),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('选择照片并分析'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('capture-photo-analyze'),
            onPressed: busy
                ? null
                : () => widget.controller.capturePhotoAndAnalyze(
                      observationContext: _context.text.trim(),
                    ),
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('拍照并分析'),
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 16),
        TextField(
          key: const Key('blob-reference'),
          controller: _blobRef,
          decoration: InputDecoration(
            labelText: '资料引用（opaque）',
            helperText: widget.mode == AppExperienceMode.syntheticDemo
                ? '当前不开放相册导入；合成体验使用内部测试引用'
                : '仅接受安全保险库提供的 opaque 引用',
          ),
          obscureText: true,
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
          subtitle: Text(
            widget.mode == AppExperienceMode.syntheticDemo
                ? '敏感等级 D3；仅用于本次合成体验，可随时关闭'
                : '敏感等级 D3；仅用于本次安全会话，可随时关闭',
          ),
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
          child: Text(
            busy
                ? '正在生成建议…'
                : widget.mode == AppExperienceMode.syntheticDemo
                    ? '生成合成示例建议'
                    : '生成安全会话建议',
          ),
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
      'consent_persistence_failed' => '授权状态未能保存，请解锁后重试。',
      'blob_reference_required' => '资料引用格式无效，请使用安全会话提供的引用。',
      'vault_locked' => '本地保险库已锁定，请重新进入。',
      'source_unavailable' => '暂时无法选择照片，请稍后重试。',
      'source_denied' => '照片选择未获允许。',
      'source_cancelled' => '已取消选择资料。',
      'source_expired' => '资料选择已过期，请重新选择。',
      'source_consumed' => '资料已使用，请重新选择。',
      'source_release_failed' => '安全资料会话未能完整关闭，请重试。',
      'security.vault_locked' => '本地保险库已锁定，请重新进入。',
      'security.unlock_cancelled' => '已取消解锁。',
      'security.unlock_denied' => '解锁未获授权。',
      'security.unlock_unavailable' => '当前无法使用解锁验证。',
      'security.unlock_expired' => '解锁会话已过期，请重新进入。',
      'security.provider_unavailable' => '安全存储暂时不可用，请稍后重试。',
      'd4_persistence_forbidden' => '该资料不允许持久化。',
      _ => '暂时无法生成（$code），请重试。',
    };
