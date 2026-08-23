import 'package:personal_os_storage_api/storage_api.dart';

/// Wave 17b pure-Dart delete-guard state machine for DeleteScreen.
///
/// Per ADR-0007 L1–L4 deletion checklist, the UI must prove the user has
/// acknowledged 3 irreversible facts AND typed the literal string "DELETE"
/// before the big red CTA becomes enabled. This class encapsulates that
/// logic so:
///
///   1. DeleteScreen only needs to call `guard.canDelete` to decide whether
///      to enable the button — no business logic in the widget tree.
///   2. The same state machine is unit-testable without Flutter.
///   3. The real Keystore.destroyKey() + SQLCipher file delete + blob dir
///      cleanup (Wave 18) can be wired by checking `guard.canDelete` first.
///
/// The guard is intentionally NOT a Command pattern: it doesn't perform the
/// deletion itself. The caller still owns the side-effecting call so that
/// error handling and UI feedback (snackbar / VaultLock redirect) stay in
/// the widget layer.
final class DeleteGuard {
  DeleteGuard();

  /// Three mandatory acknowledgements. Order matches the checklist card
  /// in DeleteScreen:
  ///   0 = "已在另一台设备验证过导出文件可恢复"
  ///   1 = "了解删除后本机事件、照片、结论都会消失"
  ///   2 = "了解 Keystore Master Key 将被永久销毁"
  final List<bool> _checklist = List<bool>.filled(3, false);
  String _typedConfirm = '';

  List<bool> get checklist => List<bool>.unmodifiable(_checklist);
  String get typedConfirm => _typedConfirm;

  void toggleChecklist(int index, bool value) {
    if (index < 0 || index >= _checklist.length) {
      throw RangeError.range(index, 0, _checklist.length - 1, 'index');
    }
    _checklist[index] = value;
  }

  void setTypedConfirm(String text) {
    _typedConfirm = text;
  }

  /// True only when all 3 checklist items are checked AND the typed text
  /// exactly equals "DELETE" (case-sensitive).
  bool get canDelete =>
      _checklist.every((bool v) => v) && _typedConfirm == 'DELETE';

  /// Which specific blockers remain, for UI hint text.
  List<DeleteBlocker> get blockers {
    final List<DeleteBlocker> result = <DeleteBlocker>[];
    for (int i = 0; i < _checklist.length; i++) {
      if (!_checklist[i]) {
        result.add(DeleteBlocker.checklistItemUnchecked(i));
      }
    }
    if (_typedConfirm != 'DELETE') {
      result.add(DeleteBlocker.typedConfirmMismatch);
    }
    return result;
  }
}

/// Reasons the delete CTA is still disabled. Used by DeleteScreen to show
/// inline hints.
final class DeleteBlocker {
  const DeleteBlocker._(this.code, this.detail);

  factory DeleteBlocker.checklistItemUnchecked(int index) =>
      DeleteBlocker._('checklist_$index', '第 ${index + 1} 项未勾选');

  static const DeleteBlocker typedConfirmMismatch =
      DeleteBlocker._('typed_confirm_mismatch', '请输入 DELETE');

  final String code;
  final String detail;

  @override
  String toString() => 'DeleteBlocker($code): $detail';
}
