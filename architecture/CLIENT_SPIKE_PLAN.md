# Android Agent Gateway Spike计划 v0.3

状态：replaces the former Android/Windows client spike

旧版跨平台Flutter spike已经失去MVP优先级。当前只验证Android权威Vault与外部Agent连接。

## 目的

证明一个真实Agent能够在不嵌入Android App的情况下，通过稳定接口完成：

读取个人资产与Goal → 维护资产 → 创建Strategy与Plan → 读取执行结果 → 创建Review与Strategy新版本。

## 必测平台

- Redmi Turbo / Android；
- 一个可连接MCP的Codex CLI或其他Harness；
- 第二个不同Agent用于兼容性验证。

Windows客户端不是必测平台。

## Spike A：Bundle往返

1. Android创建Goal和资产；
2. 导出Context Bundle；
3. Agent生成Proposal Bundle；
4. Android校验并导入；
5. 用户接受Strategy和Plan；
6. 验证引用、Schema和错误处理。

Bundle先行可以在网络MCP尚未实现时验证领域协议。

## Spike B：实时MCP

1. 解锁Android Vault；
2. 用户启动临时MCP Session；
3. Agent发现Resources和Tools；
4. Agent读取目标上下文；
5. 只读Session写入被拒绝；
6. 读写Session创建资产修订、Strategy和Plan；
7. App锁定后Session失效；
8. 日志不包含D4、路径和原始异常。

## Spike C：两轮闭环

1. 执行Strategy v1；
2. App保存Execution、Outcome和Feedback；
3. Agent创建Review；
4. Agent创建Strategy v2；
5. UI展示差异与证据；
6. 第二Agent继续同一历史。

## 指标

- Context与Proposal Schema兼容率；
- MCP调用成功率和稳定错误；
- Android Session启动/关闭延迟；
- 写入事务原子性；
- 冷启动和杀进程恢复；
- 常用执行反馈操作负担；
- 更换Agent后的兼容性；
- 数据导出和重建一致性。

## 退出条件

- Bundle与实时MCP至少一种完成真实往返；
- Codex或一种Agent完成完整读写；
- 第二Agent无需修改核心Schema即可继续；
- Redmi完成两轮Strategy闭环；
- exact commit、设备和Harness版本有可复现记录。
