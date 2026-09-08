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
    final busy = widget.controller.submission == SubmissionStatus.running ||
        widget.controller.credentialOperationRunning;
    final analysisReady = widget.controller.analysisPreflightReady;
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
        if (widget.mode == AppExperienceMode.secureVault) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            _modelCapabilityStatus(widget.controller),
            key: const Key('model-capability-status'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (widget.controller.canConfigureExternalCredential) ...<Widget>[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('configure-model-credential'),
              onPressed: busy
                  ? null
                  : widget.controller.configureExternalModelCredential,
              icon: const Icon(Icons.key_outlined),
              label: Text(
                widget.controller.externalProcessingAvailable
                    ? '更换一次性模型凭据'
                    : '配置一次性模型凭据',
              ),
            ),
            if (widget.controller.externalProcessingAvailable)
              TextButton(
                key: const Key('clear-model-credential'),
                onPressed: busy
                    ? null
                    : widget.controller.clearExternalModelCredential,
                child: const Text('立即清除模型凭据'),
              ),
          ],
          if (widget.controller.externalProcessingAvailable ||
              widget.controller.externalProcessingConsentGranted)
            SwitchListTile(
              key: const Key('external-processing-consent'),
              value: widget.controller.externalProcessingConsentGranted,
              onChanged: busy
                  ? null
                  : widget.controller.setExternalProcessingConsent,
              title: const Text('我允许使用外部模型处理照片'),
              subtitle: Text(
                widget.controller.externalProcessingAvailable
                    ? '独立持续授权；每次实际发送前仍会再次确认。'
                    : '外部模型当前不可用；'
                        '请关闭此授权以恢复安全拒绝状态。',
              ),
            ),
        ],
        if (!analysisReady) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            _analysisPreflightMessage(widget.controller),
            key: const Key('analysis-preflight-status'),
            style: const TextStyle(color: Colors.orange),
          ),
        ],
        if (widget.controller.sourceAvailable) ...<Widget>[
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('pick-photo-analyze'),
            onPressed: busy || !analysisReady ? null : _pickPhotoAndAnalyze,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('选择照片并分析'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('capture-photo-analyze'),
            onPressed: busy || !analysisReady ? null : _capturePhotoAndAnalyze,
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('拍照并分析'),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('analyze-reference'),
          onPressed: busy || !analysisReady ? null : _analyzeBlobReference,
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
          Text(captureErrorMessage(error),
              style: const TextStyle(color: Colors.red)),
        ],
      ],
    );
  }

  Future<void> _pickPhotoAndAnalyze() async {
    final confirmed = await _confirmExternalTransmission();
    if (!mounted || !confirmed) return;
    await widget.controller.pickPhotoAndAnalyze(
      observationContext: _context.text.trim(),
      externalTransmissionConfirmed: confirmed,
    );
  }

  Future<void> _capturePhotoAndAnalyze() async {
    final confirmed = await _confirmExternalTransmission();
    if (!mounted || !confirmed) return;
    await widget.controller.capturePhotoAndAnalyze(
      observationContext: _context.text.trim(),
      externalTransmissionConfirmed: confirmed,
    );
  }

  Future<void> _analyzeBlobReference() async {
    final confirmed = await _confirmExternalTransmission();
    if (!mounted || !confirmed) return;
    await widget.controller.analyzeBlobReference(
      blobReference: _blobRef.text.trim(),
      observationContext: _context.text.trim(),
      externalTransmissionConfirmed: confirmed,
    );
  }

  Future<bool> _confirmExternalTransmission() async {
    if (!widget.controller.externalTransmissionConfirmationRequired) {
      return true;
    }
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            key: const Key('external-transmission-confirmation'),
            title: const Text('确认发送到外部模型'),
            content: const Text(
              '本次照片和观察说明将离开设备，交给外部模型处理。'
              '服务商可能收取 API 费用；一次性凭据无论成功或失败都会被清除。'
              '应用不会把凭据或原始响应写入事件记录。',
            ),
            actions: <Widget>[
              TextButton(
                key: const Key('cancel-external-transmission'),
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                key: const Key('confirm-external-transmission'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('仅发送这一次'),
              ),
            ],
          ),
        ) ??
        false;
  }
}

String _analysisPreflightMessage(AppController controller) {
  if (!controller.consentGranted) return '下一步：先开启本次外貌分析授权。';
  if (!controller.modelConfigured) return '下一步：等待真实模型配置就绪。';
  if (controller.externalProcessingConfigured &&
      !controller.externalProcessingAvailable) {
    return '下一步：配置一次性模型凭据。凭据不会保存到事件或 Flutter。';
  }
  if (controller.externalProcessingAvailable &&
      !controller.externalProcessingConsentGranted &&
      !controller.onDeviceProcessingAvailable) {
    return '下一步：开启外部模型处理授权。每次发送前仍会单独确认。';
  }
  return '当前处理方式不可用，请检查模型能力。';
}

@visibleForTesting
String captureErrorMessage(String code) => switch (code) {
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
      // This code also covers HTTP/network failures after sending has begun.
      // A failed response does not prove that the provider received no photo.
      'model.adapter_unavailable' =>
        '模型当前不可用。请检查网络、模型配置及 API 凭据。'
            '若已确认外部发送，照片可能已发送；重试前请检查凭据状态。',
      'model.invalid_response' =>
        '未获得符合安全格式的分析结果。若已确认外部发送，照片可能已发送；'
            '请检查凭据状态后再决定是否重试。',
      'model.on_device_unavailable' => '当前模型不支持设备内处理。',
      'model.external_processing_unavailable' =>
        '外部模型或运行时凭据尚未就绪，照片未发送。',
      'model.credential_configuration_unavailable' =>
        '当前模型不支持运行时凭据配置。',
      'model.credential_configuration_failed' => '模型凭据配置失败，未保存任何值。',
      'model.runtime_credential_not_ready' => '模型凭据未就绪，请重新配置。',
      'model.credential_clear_failed' =>
        '模型凭据清除失败，请锁定保险库后重试。',
      'external_consent_persistence_failed' =>
        '外部处理授权未能安全保存，请重试。',
      'external_processing_consent_required' =>
        '当前仅配置了外部模型，请先完成独立授权。',
      'external_transmission_confirmation_required' =>
        '本次外部发送尚未确认，照片未读取也未发送。',
      'd4_persistence_forbidden' => '该资料不允许持久化。',
      _ => '暂时无法生成（$code），请重试。',
    };

String _modelCapabilityStatus(AppController controller) {
  if (!controller.modelConfigured) {
    return '真实模型尚未配置；系统会在读取照片前安全拒绝。';
  }
  if (controller.externalProcessingConfigured) {
    if (controller.externalProcessingAvailable) {
      return controller.onDeviceProcessingAvailable
          ? '设备内模型可用；外部模型和运行时凭据也已就绪。'
          : '外部模型和运行时凭据已就绪。';
    }
    return controller.onDeviceProcessingAvailable
        ? '设备内模型可用；外部模型已配置，但运行时凭据未就绪。'
        : '外部模型已配置，但运行时凭据未就绪。';
  }
  return '设备内安全模型已配置。';
}
