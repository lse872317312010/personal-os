# M2 初版威胁模型

状态：draft

## 保护资产

- D2/D3 事件、投影、照片和长期记忆；
- Vault/Blob 密钥、设备身份和 Consent；
- 删除状态、审计历史和模型路由规则；
- 用户关系与第三方最小资料。

## 主要对手与故障

| 威胁 | 主要缓解 |
|---|---|
| 云端中继或供应商读取明文 | 客户端 E2EE；云端无业务解密密钥 |
| 公司电脑被管理、检查或丢失 | Restricted Collector；无完整 Vault；短期加密缓冲 |
| 手机/主设备丢失 | OS Keystore/Keychain、设备锁、远程设备撤销、密钥轮换 |
| 恶意/错误 Agent 越权 | 默认拒绝、Capability + Consent、R2+ 确认、Core 二次校验 |
| 调试日志/崩溃报告泄露 | 结构化 reason code；禁止 D2/D3 payload 和 D4 |
| 同步重放或伪造事件 | event_id 幂等、设备签名、sequence/cursor、完整性校验 |
| 恶意迟到事件改变历史 | 保留 recorded_at；重投影可审计；高影响变化需 Review |
| 删除后从快照/备份恢复 | deletion barrier、快照失效、备份删除传播和恢复后重放 tombstone |
| 密钥丢失导致永久不可恢复 | 用户控制的恢复材料/可信设备恢复方案在 M2 单独权衡 |
| OCR/采集触发平台封禁 | 不 Hook/破解；优先用户可见、非侵入式采集 |

## 需要 M2 继续决定

- 设备密钥层级、恢复与轮换协议；
- Relay 可见的最小元数据及流量分析风险；
- SQLCipher/Blob 临时文件和内存中的明文边界；
- 移动端后台同步与 Restricted Collector 的自动清理时间；
- 云模型供应商的数据保留和训练设置验证方式。

