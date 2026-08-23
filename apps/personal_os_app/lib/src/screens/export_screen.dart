import 'package:flutter/material.dart';

import '../composition/app_composition.dart';
import '../controller/app_controller.dart';
import 'package:personal_os_storage_api/storage_api.dart';

/// Lets the user export the in-memory vault to a tamper-evident JSON envelope.
///
/// The actual heavy lifting lives in [VaultExporter] (Wave 17a). This screen
/// is the wiring layer:
/// - It reads events straight out of the [InMemoryEventStore] (Wave 19b uses
///   the synchronous `readEvents()` API; once Wave 18b's `readAll()` port
///   lands we will swap to it).
/// - It builds a [VaultExportRequest] from the user's UI selections
///   (passphrase, includeBlobs).
/// - It calls [VaultExporter.exportFromSnapshot] and surfaces the resulting
///   `sha256Hex` / `signatureHex` so the user can verify the export matches
///   what the recovery side will accept.
/// - The CTA is disabled until `canExport` is true (i.e. there is at least
///   one event in the store and no export is in flight).
class ExportScreen extends StatefulWidget {
  const ExportScreen({
    required this.controller,
    required this.composition,
    super.key,
  });

  final AppController controller;
  final AppComposition composition;

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

final class _ExportScreenState extends State<ExportScreen> {
  final TextEditingController _passphrase = TextEditingController();
  bool _includeBlobs = false;
  bool _exporting = false;
  VaultExportEnvelope? _lastEnvelope;
  String? _errorText;

  bool get _canExport =>
      !_exporting &&
      widget.composition.eventStore.readEvents().isNotEmpty;

  Future<void> _onExport() async {
    setState(() {
      _exporting = true;
      _errorText = null;
      _lastEnvelope = null;
    });
    try {
      final events = widget.composition.eventStore
          .readEvents()
          .map((stored) => stored.event)
          .toList(growable: false);
      final envelope = await widget.composition.vaultExporter.exportFromSnapshot(
        request: VaultExportRequest(
          compositionMode: widget.composition.compositionMode,
          includeBlobs: _includeBlobs,
          passphrase:
              _passphrase.text.isNotEmpty ? _passphrase.text : null,
        ),
        events: events,
      );
      setState(() {
        _lastEnvelope = envelope;
      });
    } on VaultExportRejected catch (ex) {
      setState(() {
        _errorText = 'export_rejected:${ex.reasonCode}: ${ex.detail}';
      });
    } catch (ex) {
      setState(() {
        _errorText = 'export_failed:$ex';
      });
    } finally {
      setState(() {
        _exporting = false;
      });
    }
  }

  @override
  void dispose() {
    _passphrase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('导出 Vault')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Icon(Icons.ios_share, size: 56),
                    const SizedBox(height: 16),
                    const Text(
                      '将当前 Vault 内容打包为带签名的离线 JSON 包。'
                      '导出文件包含全部事件、模式标签和 SHA-256 / HMAC-SHA256 '
                      '校验值，便于在恢复端验证完整性。',
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      key: const Key('export-passphrase'),
                      controller: _passphrase,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: '可选口令（用于签名校验）',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      key: const Key('export-include-blobs'),
                      title: const Text('包含 blob 元数据清单'),
                      value: _includeBlobs,
                      onChanged: (v) => setState(() => _includeBlobs = v),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      key: const Key('export-cta'),
                      onPressed: _canExport ? _onExport : null,
                      icon: _exporting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.archive_outlined),
                      label: Text(_exporting ? '导出中…' : '导出 Vault'),
                    ),
                    if (_errorText != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _errorText!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    if (_lastEnvelope != null) ...[
                      const SizedBox(height: 24),
                      const Divider(),
                      const SizedBox(height: 8),
                      _ResultRow(
                        label: 'SHA-256',
                        value: _lastEnvelope!.sha256Hex,
                        keyPrefix: 'export-sha256',
                      ),
                      const SizedBox(height: 8),
                      _ResultRow(
                        label: 'HMAC 签名',
                        value: _lastEnvelope!.signatureHex,
                        keyPrefix: 'export-signature',
                      ),
                      const SizedBox(height: 8),
                      _ResultRow(
                        label: '字节数',
                        value: '${_lastEnvelope!.bytes.length}',
                        keyPrefix: 'export-bytes',
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

final class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.label,
    required this.value,
    required this.keyPrefix,
  });

  final String label;
  final String value;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Expanded(
            child: SelectableText(
              value,
              key: Key(keyPrefix),
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ],
      );
}
