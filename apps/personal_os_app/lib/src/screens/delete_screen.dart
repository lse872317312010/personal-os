import 'package:flutter/material.dart';

import 'package:personal_os_storage_api/storage_api.dart';

import '../controller/app_controller.dart';

/// Wave 19c: irreversible-vault-deletion screen wired to the Wave 17b
/// [DeleteGuard] state machine.
///
/// Per ADR-0007 L1–L4 deletion checklist, the user must:
///   1. Check all 3 acknowledgement boxes (export verified, data will be
///      lost, Keystore Master Key will be destroyed).
///   2. Type the literal string "DELETE" (case-sensitive).
///
/// Only then does the big red CTA become enabled. The CTA does NOT perform
/// the deletion itself — it invokes the [onConfirmDelete] callback the
/// caller supplied at construction. That callback owns the actual
/// Keystore.destroyKey() + SQLCipher file delete + blob dir cleanup
/// side-effects (Wave 18 will wire those). The screen's job is purely to
/// gate the CTA via [DeleteGuard.canDelete] and to surface the guard's
/// `blockers` as inline hints.
///
/// Why a separate widget (not just inline in ExportScreen or settings):
/// deletion is a one-way ratchet — the user must not be able to trip it
/// accidentally from any other screen. Dedicated route = dedicated intent.
class DeleteScreen extends StatefulWidget {
  const DeleteScreen({
    required this.controller,
    required this.onConfirmDelete,
    super.key,
  });

  final AppController controller;

  /// Caller-owned side-effecting callback. Invoked only when
  /// [DeleteGuard.canDelete] is true. The callback should perform the
  /// real deletion (Wave 18 wires Keystore + SQLCipher + blob dir).
  /// Returning `true` redirects to VaultLockScreen; `false` surfaces an
  /// inline error.
  final Future<bool> Function() onConfirmDelete;

  @override
  State<DeleteScreen> createState() => _DeleteScreenState();
}

final class _DeleteScreenState extends State<DeleteScreen> {
  final DeleteGuard _guard = DeleteGuard();
  final TextEditingController _typedConfirm = TextEditingController();
  bool _deleting = false;
  String? _errorText;

  static const List<String> _acknowledgements = <String>[
    '已在另一台设备验证过导出文件可恢复',
    '了解删除后本机事件、照片、结论都会消失',
    '了解 Keystore Master Key 将被永久销毁',
  ];

  @override
  void dispose() {
    _typedConfirm.dispose();
    super.dispose();
  }

  Future<void> _onConfirmDelete() async {
    setState(() {
      _deleting = true;
      _errorText = null;
    });
    try {
      final ok = await widget.onConfirmDelete();
      if (!ok) {
        setState(() {
          _errorText = 'delete_failed:回调返回 false';
        });
      }
    } catch (ex) {
      setState(() {
        _errorText = 'delete_failed:$ex';
      });
    } finally {
      if (mounted) {
        setState(() {
          _deleting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('删除 Vault')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Icon(Icons.warning_amber_outlined,
                        size: 56,
                        color: Theme.of(context).colorScheme.error),
                    const SizedBox(height: 16),
                    const Text(
                      '此操作不可撤销。删除 Vault 将永久销毁本机 Keystore '
                      '主密钥、所有事件、blob 和结论。仅在已成功导出并在'
                      '另一台设备验证可恢复后执行。',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 24),
                    for (int i = 0; i < _acknowledgements.length; i++)
                      CheckboxListTile(
                        key: Key('delete-check-$i'),
                        value: _guard.checklist[i],
                        onChanged: (v) => setState(() {
                          _guard.toggleChecklist(i, v ?? false);
                        }),
                        title: Text(_acknowledgements[i]),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('delete-typed-confirm'),
                      controller: _typedConfirm,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: '请输入 DELETE 以确认',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) => setState(() {
                        _guard.setTypedConfirm(value);
                      }),
                    ),
                    const SizedBox(height: 16),
                    if (_guard.blockers.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _guard.blockers.map((b) => b.detail).join('；'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    FilledButton.icon(
                      key: const Key('delete-cta'),
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            Theme.of(context).colorScheme.error,
                        foregroundColor:
                            Theme.of(context).colorScheme.onError,
                      ),
                      onPressed: (_guard.canDelete && !_deleting)
                          ? _onConfirmDelete
                          : null,
                      icon: _deleting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.delete_forever),
                      label: Text(_deleting ? '删除中…' : '永久删除 Vault'),
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
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
