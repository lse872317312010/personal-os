# Coding Wave 3 集成评审

日期：2026-08-20  
状态：local static review passed / remote sync and executable CI pending

## 本轮交付

- 扩展 Event reducer，覆盖 S1–S4 中声明的 46 种事件类型；
- 补齐删除 barrier、安全 Tombstone 和显式 Conflict 生命周期；
- Android-first Flutter shell：Vault gate、Capture、Claim、Plan、Task、Review；
- 真实 Policy adapter 进入 Flutter demo composition，删除本地假授权；
- 精确 revision 的 in-memory Consent repository；
- 平台无关 `security_api`：VaultSession、UnlockGrant、KeyProvider 与设备撤销；
- Flutter Android CI 与隔离的临时 host bootstrap。

## 主审修正

### 禁止 UI 同意替代真实授权

Flutter 初稿的本地 policy 只检查 ConsentRef 形状，可能让 UI 开关被误认为真实授权。现已删除该实现：

- UI 开关仅用于交互前置提示；
- Application 仍调用 `AppearancePolicyAdapter`；
- Adapter 从 `InMemoryConsentRevisionRepository` 精确读取 revision；
- Grant 缺失时，即使 UI 已同意，Model Gateway 调用次数仍为零。

### CI 不覆盖源码生成 Host

仓库当前只有最小 Android host，不能直接构建 APK。CI 会在隔离临时副本执行 `flutter create` 补全 host，只复制最终 debug APK，不覆盖 `lib/`、`test/` 或仓库内 Android 文件。

## 当前测试资产

- Wave 1：17 个 Dart tests；
- Wave 2：13 个 adapter/runner tests；
- Event reducer 扩展：6 个；
- In-memory Consent repository：6 个；
- Security API：4 个；
- Flutter shell：controller/widget tests，并新增真实 policy 缺失授权拒绝场景。

具体数量以 CI 实际发现为准；静态计数不能替代测试运行。

## 仍未完成

- GitHub 写入因当前连接额度限制暂时阻塞，Wave 2/3 尚未同步远端；
- Dart Core CI 和 Flutter Android CI 尚无首次运行结果；
- SQLite/SQLCipher、Android Keystore 与加密 Blob 尚未实现；
- demo Consent 与 Model Gateway 不能用于 dogfood build；
- Redmi Turbo 安装、锁屏、杀进程、省电和权限拒绝测试未执行。
