# 客户端与核心运行时评分表 v0.1

状态：Flutter selected by product constraint；empirical gates pending

每项 0–5 分。Safety Gate 任一失败则淘汰，不计算总分。

## Safety Gates

| Gate | Flutter + Dart | Tauri |
|---|---:|---:|
| D4 不进入持久层/日志 | pending | deferred |
| D3 Vault 可使用 OS-backed key 保护 | pending | deferred |
| Consent revoke 可阻断新处理 | pending | deferred |
| L2 删除后 Snapshot/临时文件无原内容 | pending | deferred |
| M1 核心契约测试 ≥ 必测集合 | pending | deferred |

## 加权评分

| 维度 | 权重 | Flutter + Dart | Tauri |
|---|---:|---:|---:|
| 移动端体验与系统能力 | 20 | pending | deferred |
| Windows 体验与集成 | 12 | pending | deferred |
| 本地数据库/加密成熟度 | 15 | pending | deferred |
| 后台同步与生命周期 | 10 | pending | deferred |
| M1 核心复用与类型安全 | 12 | pending | deferred |
| 测试、调试与可观测性 | 10 | pending | deferred |
| 开发速度与单人维护成本 | 12 | pending | deferred |
| 包体、启动与资源占用 | 5 | pending | deferred |
| 供应商/生态退出能力 | 4 | pending | deferred |

## 决策规则

- Android 是 Primary Vault，移动体验不得低于 3/5；
- Windows 若是 Primary Vault，Windows 集成不得低于 3/5；
- Flutter + Rust core 只在相对纯 Dart core 的收益覆盖 FFI 复杂度时采用；
- Tauri 的 Rust 优势不能抵消移动后台、WebView 权限或插件缺口；
- 分数差小于 8% 时，选择维护面更小、MVP 更快的方案；
- 分数和测量结果进入 ADR，保留复现命令与版本。

当前选择来自已确认的产品约束，不是尚未执行的性能评分。表中的 `pending` 不得擅自填分；`deferred` 表示 Tauri 只有触发条件成立时才进入实测。
