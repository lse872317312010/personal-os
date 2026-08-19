# personal_os_domain

Personal OS 的纯 Dart 领域基础包。它只定义稳定身份、版本、引用、Actor、敏感度和核心状态，不依赖 Flutter、数据库、网络或平台插件。

当前实现覆盖 M1 最小公共语言：

- 逻辑对象 ID 与 revision 分离；
- 可固定到具体 revision 的对象引用；
- `D0`–`D4` 敏感度及最高等级继承辅助函数；
- Actor 审计身份，并强制非用户 Actor 声明 `onBehalfOf`；
- Claim、Goal、Plan、Task、Consent、Review 状态枚举。

领域实体的完整字段将在实际 vertical slice 中按用例逐步加入，避免在没有真实调用方时制造大而空的模型。本包尚未在 Dart 工具链中编译验证。

