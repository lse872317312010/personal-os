# 0003 — 本地权威的加密混合架构

- 状态：accepted at architecture-principle level
- 日期：2026-08-20
- 范围：M2+

## 决定

Personal OS 采用 local-authoritative encrypted hybrid：可信主设备保存完整 Vault 和当前投影；云端仅承担端到端加密的事件/Blob 中继、设备目录和同步协调。公司电脑等受限设备只作为最小采集端，不拥有完整 Vault。

## 理由

- 满足已确认的 local-first、隐私优先和原始敏感数据本地保留要求；
- 支持离线、跨设备缺口检测和历史补采；
- 避免云厂商成为长期记忆的明文权威和单点退出风险；
- 保留未来选择客户端、数据库、模型和中继供应商的空间。

## 不代表

本决定不锁定 Flutter、Tauri、Rust、Dart、SQLite/SQLCipher 具体封装、云厂商或模型供应商。这些仍需候选比较和 spike。

