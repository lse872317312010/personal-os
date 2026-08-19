# Coding Wave 1 集成评审

日期：2026-08-20  
状态：static review passed / executable verification pending

## 本轮范围

- `packages/policy`：Consent、D4、敏感度和行动风险策略；
- `packages/application`：外貌分析 command/query 与最小闭环用例；
- `packages/storage_api`、`model_gateway_api`、`sync_api`：平台无关 ports；
- `adapters/in_memory`：用于测试和 UI spike 的原子内存 EventStore。

## 已确认

- 上述 Dart 代码无 Flutter、SQLite、HTTP 或供应商 SDK 依赖；
- D4 在处理与持久化入口均失败关闭；
- Consent 按 revision、主体、Actor、purpose、resource、action、敏感度、有效期和状态完整校验；
- MVP 中 R3 即使已经用户确认也只能形成草案，不能执行外部动作；
- 外貌用例按“Policy → Model Gateway → Event batch”执行，拒绝或空分析不会写入；
- 内存 EventStore 实现正式 storage port，批量失败不会部分提交；
- event ID 重复幂等，expected revision 冲突使用稳定 reason；
- 共新增 17 个 Dart 测试案例：Policy 5、Application 4、In-memory 8。

## 主审修正

初稿曾允许 R3 在用户确认后执行，这与 M1 `CT-304` 和 MVP 边界冲突。现已修正为始终 `draftOnly`；请求执行时返回 `R3_MVP_EXECUTION_FORBIDDEN`。

## 尚未通过

- 当前环境不存在 Dart/Flutter SDK，因此 `dart format`、`dart analyze`、`dart test` 未运行；
- application 的 `AppearancePolicyPort` 尚未连接到真实 `packages/policy` adapter；
- 尚未执行固定 JSON fixtures 的自动 runner；
- 未实现 SQLite/SQLCipher、Android Keystore、Flutter UI 或 Redmi 真机验证。

## 下一波门禁

1. 在具备 Dart SDK 的环境运行全部 package tests 并修复编译问题；
2. 建立 Policy → Application adapter，禁止 fake policy 进入非测试 composition root；
3. 实现 JSON fixture runner，先覆盖 CT-001、002、101、105、301、303、304、501；
4. 再建立 Flutter Android shell 和 in-memory vertical slice。
