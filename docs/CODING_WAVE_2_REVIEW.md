# Coding Wave 2 集成评审

日期：2026-08-20  
状态：CI ready / run result pending

## 本轮交付

- `adapters/policy_application`：Application 到 Policy Core 的真实失败关闭适配器；
- `test_contract/runner_dart`：S1–S4 JSON fixture 的 Dart runner 与稳定机器输出；
- 根级 Dart 检查脚本与 GitHub Actions 工作流。

## 安全与接口结论

- 外貌分析固定使用 `appearance_review / portrait / derive / D3`；调用方不能以降低 sensitivity 扩权；
- 必须恰好提供一个固定到 revision 的 ConsentRef；缺失、过期、撤销、不匹配或 repository 异常均拒绝；
- runner 对未实现领域语义返回 `unsupported`，不得伪装成 pass；
- runner 不输出事件 payload，避免测试报告泄露 D2/D3；
- D4 在进入内存存储前由 Policy gate 拒绝；
- CI 覆盖 `packages/**`、`adapters/**` 和 `test_contract/runner_dart`。

## 新增测试

- Policy/Application adapter：7 个；
- Contract runner：6 个；
- 连同 Wave 1 的 17 个，目前源码中共 30 个 Dart test cases。

## 本地主审证据

- `git diff --check` 通过；
- `bash -n tool/check_dart_core.sh` 通过；
- 平台无关目录未发现 Flutter import/dependency；
- CI 工作流采用只读权限、固定 Dart 3.3.4、15 分钟超时和并发取消。

## 尚未完成

- GitHub Actions 首次运行结果；
- 对 runner 的全部 S1–S4 输出建立批准基线；
- 当前 reducer 尚未实现 Source、Observation、Baseline、Opportunity、Recommendation、Outcome、Deletion、Conflict 等投影，因此对应检查应保持 `unsupported`；
- Flutter Android shell 与 Redmi 真机尚未开始可执行验证。
