# M1 敏感度继承 v0.1

状态：accepted

## 默认规则

派生对象的敏感度不得低于其必要输入中的最高等级：

`derived_sensitivity = max(input sensitivities, declared minimum for output type)`

只有经过明确、可测试的降敏转换，才能降低等级；“摘要”“embedding”“特征”或“匿名”字样本身不构成降敏。

## 字段级标签

对象级 sensitivity 是访问控制下限；字段可以更高，不能更低。任何序列化、日志、索引、Snapshot、缓存和导出都必须保留字段标签或提升整个容器等级。

## 典型继承

| 输入 | 派生物 | 默认等级 |
|---|---|---:|
| D3 原始人像 | 可识别缩略图、embedding、面部特征 | D3 |
| D3 健康/身体记录 | 个性化健康相关 Claim | D3 |
| D2 私密偏好 | 不含身份的任务排序 | D2 |
| 多条 D1 行为记录 | 可重识别长期模式 | 至少 D2 |
| 第三方关系记录 | 第三方画像或关系推断 | D3，且通常禁止长期化 |
| 任意 D4 | 任意派生物 | 禁止处理和持久化 |

## 聚合升级

多条低敏数据组合后可能揭示更敏感模式。投影必须允许 `sensitivity.escalated`，禁止因单条输入是 D1 就让长期画像保持 D1。

## 允许降敏的条件

- 输出无法合理重识别个人或恢复敏感输入；
- 移除不是简单隐藏，且攻击者不能通过可用上下文反推；
- 转换目的、方法、风险和测试被记录；
- D3 降到 D1/D0 需要用户授权和独立审查；
- 原始输入删除后，降敏输出仍重新评估。

## 传播事件

- `sensitivity.classified`
- `sensitivity.escalated`
- `sensitivity.declassification.requested`
- `sensitivity.declassification.approved|rejected`

降低等级不能由生成派生物的同一自动 Actor 自行批准。

