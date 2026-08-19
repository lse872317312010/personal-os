# M2 逻辑包与依赖边界 v0.1

状态：accepted at architecture level

```text
apps/personal_os_app
packages/domain
packages/events
packages/policy
packages/application
packages/storage_api
packages/sync_api
packages/model_gateway_api
adapters/sqlite_vault
adapters/blob_vault
adapters/platform_security
adapters/sync_relay
adapters/model_local
adapters/model_cloud
```

## 职责

| 包 | 职责 | 禁止事项 |
|---|---|---|
| `domain` | 实体、值对象、状态 | UI、数据库、网络依赖 |
| `events` | M1 事件信封、事件类型、reducer | 平台插件依赖 |
| `policy` | D0–D4、R0–R4、Consent 与授权判定 | 绕过失败关闭规则 |
| `application` | commands、queries、用例编排、事务边界 | 直接调用 Flutter widget |
| `*_api` | 存储、同步、模型能力 ports | 绑定具体供应商 |
| `adapters/*` | SQLite/SQLCipher、Blob、Keystore、Relay、模型实现 | 反向定义业务语义 |
| `personal_os_app` | Flutter 路由、页面、状态呈现、平台组合根 | 直接改写事件或投影 |

依赖方向始终指向内层：`app/adapters → APIs/application → events/policy/domain`。平台适配器可以替换，M1 事件和规则不能因此变化。

## v1 核心接口

- `CommandBus.execute(command, actorContext)`
- `QueryService.read(view, authorizationContext)`
- `EventStore.append(expectedVersion, events)`
- `ProjectionStore.apply(events)`
- `BlobStore.put/read/delete(blobRef)`
- `KeyProvider.wrap/unwrap/rotate(keyRef)`
- `SyncPort.push/pull(cursor, envelopes)`
- `ModelGateway.analyze(request, consentContext)`

具体 Dart 签名在 Flutter 工具链就绪后由首个 vertical slice 固化；在此之前不假装已有可编译实现。
