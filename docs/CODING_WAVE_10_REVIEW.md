# Coding Wave 10：可体验 MVP 收口

状态：代码与静态门禁完成；受控 Photo Picker→native blob→analysis wiring 已接入，等待 Flutter/Android 编译与 exact-commit 运行时证据，随后进入 Redmi Turbo 真机验证。

## 用户可见闭环

当前 Android MVP 提供一条明确的中文离线体验路径：

1. 进入本地 Vault 演示会话；
2. 合成 demo 不读取相册；secure Android path 可通过系统 Photo Picker 选择照片，但当前分析仍使用 synthetic model，不上传云端；
3. 明确授予本次 D3 外貌分析同意；
4. 生成并人工采用示例建议；
5. 选择一个两分钟行动计划；
6. 完成或跳过行动；
7. 创建复盘并标记有效或无效；
8. 在本地事件流中完成一次反馈闭环。

底部入口由六项压缩为首页、分析、行动、复盘四项。计划未确认时不能执行任务，任务未反馈时不能创建复盘，避免通过导航绕过领域流程。

## Android 包装

- 补齐 Gradle Kotlin DSL host、Flutter activity、日夜主题和 wrapper bootstrap；
- Debug APK 构建脚本同时执行 pub get、analyze、Flutter tests 与 build；
- Manifest 不申请网络、相机、麦克风、定位、联系人或共享存储权限；
- 禁止 Android backup 与明文流量；
- Release signing 未配置，仓库不保存签名密钥或密码；
- 提供 PowerShell 与 Bash 的 Redmi Turbo 安装/启动流程，不采集设备 ID、logcat、截图或手机文件。

## 验收门

`MVP_USABILITY_GATE.md` 将结论分为 STATIC、TEST、BUILD、DEVICE 与 DOGFOOD 五级。Synthetic evidence 永远不能通过 gate。当前 `evidence/mvp/status.json` 正确输出 `NOT_VERIFIED`；必须在同一候选 commit 上取得 Flutter tests、APK digest、Redmi 九场景与 2–6 周真实闭环证据，才能逐级升级。

## 已验证

- MVP acceptance Python tests：9/9 PASS；
- Android XML parse、零 permission scan、shell syntax：PASS；
- package dependency graph：PASS；
- `git diff --check`：PASS。

## 尚未验证

- 本执行环境没有 Flutter/Dart/ADB；
- Flutter analyze/widget tests 与 APK build 等待 GitHub Actions；
- Redmi Turbo 安装、冷启动、进程死亡、重启、权限拒绝与恢复演练尚未执行；
- Photo Picker、native blob sink 和 application wiring 已实现但未运行时验证；Camera 仍不可用；当前模型仍是 synthetic fixture，不代表真实照片分析。Android durable-vault、冷启动/重启、Redmi 和 production 行为仍未验证。
