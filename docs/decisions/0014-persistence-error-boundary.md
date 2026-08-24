# 0014 — 持久化错误边界

日期：2026-08-24  
状态：proposed

## 背景

持久化实现会产生平台、数据库和密钥管理器特有的异常。如果 Application
直接识别这些异常，Port 将反向依赖 Adapter，且路径、SQL、subject ID、
密钥信息或 stack trace 可能进入 UI、日志和 evidence。

## 决定

`packages/storage_api` 只定义 adapter-neutral 的：

- `PersistenceErrorCode`：稳定 wire value；
- `PersistenceException`：仅持有 code；
- 由 code 决定的固定 `safeMessage`；
- 仅包含 `code` 与 `safe_message` 的 evidence 投影。

Port 层不得 import adapter exception。每个 Adapter 必须在自己的出口捕获
内部异常，并用结构化条件映射为 `PersistenceException`。禁止解析任意
exception message 的正则来判断语义。

固定安全文案不能由调用方覆盖，不能透传 `Exception.toString()`。内部
cause 只能停留在受控本地调试通道，不得进入 UI、普通日志、Relay 或 evidence。

Python 工具可以验证 canonical code 清单，但不能复制一套影子异常类并声称
代表真实 Dart 行为。真实 Adapter 必须通过 Dart 合同测试。

## 映射责任

- EventStore Adapter：识别 duplicate/conflict、D4、revision 和事务失败；
- BlobStore Adapter：识别 D4、partial-write、not-found 和 provider failure；
- Vault/Key Adapter：识别 locked、unlock、rekey、revoked 和 key lifecycle；
- 未识别内部错误统一映射为 `internalAdapterFailure`。

映射实现位于对应 Adapter 包，storage/security API 不得引用实现包。

## 验证

1. 17 个 wire value 唯一且以 `persistence.` 开头；
2. evidence 只有 `code` 和 `safe_message`；
3. 每个真实 Adapter 有 Dart 参数化映射测试；
4. 未识别异常不会输出原 message；
5. CI 边界检查证明 `packages/*` 不 import persistence Adapter。

## 当前限制

本 ADR 先建立稳定错误形状。现有 EventStore、BlobStore 和 VaultDriver 的
所有旧异常尚未一次性迁移完成；在每个调用链迁移并通过合同测试前，不得声称
错误归一已经完整落地。
