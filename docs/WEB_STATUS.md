# Personal OS：Web 阶段记录

更新日期：2026-10-08（Asia/Shanghai）。

## 当前阶段

**本机 Web 自动 Agent 闭环原型已通过本地 fixture 验证，真实账号和真实使用验收待完成。**

Personal OS 负责结构化个人资料和连续行动历史，用户选择的 GPT 或其他
Agent 提供计划与复盘。当前主线只做 Web。Windows/Linux 启动包维护、Android
真机和多设备同步后排。

应用依赖本机 Node 网关保存加密历史与凭据。公开 GitHub Pages 仍是下载入口，
无法独立运行当前的 AI 闭环。

## 已实现的流程

连接 AI → 保存目标与资料 → 自动生成计划 → 用户确认 → 用户执行并明确反馈
→ 自动复盘 → 用户接受复盘 → 自动生成下一轮计划。

- 支持 ChatGPT 授权、Responses、OpenAI 兼容 Chat Completions 和 HTTP Agent。
- 切换 Agent 保留资料与历史，后续请求继续携带已有证据。
- 行动卡在首屏；已连接后的连接管理、补充资料和行动历史按需展开。
- 目标、成功标准、当前情况、执行限制统一编辑，刷新后恢复。
- 编辑追加版本事件；清空可选现状/约束会归档，旧固定版本证据仍可读取。
- 已保存目标、反馈或已接受复盘可在重新连接/刷新后继续待完成的 AI 请求。
- 多行动计划在保存执行或反馈后，会从执行记录恢复对应行动，刷新后继续显示该步。
- 仅有执行记录时可补交结果；原文按中性评价保存，写入失败保留输入，AI 失败后重试复盘不重复记结果。
- 计划和复盘仍等待用户确认；仅接受计划不会记为已执行。

## 本轮改动整理

| 部分 | 内容 | 主要位置 |
| --- | --- | --- |
| 结构化资料 | 四字段编辑、修订/归档、旧约束目标归属校验、上下文传递 | `packages/application`、`packages/events`、`packages/agent_protocol` |
| Web 交互 | 四字段恢复与展示，当前目标/现状去重，资料和历史分开查看 | `apps/personal_os_app` |
| 行动恢复 | 多行动计划恢复已记录的行动，覆盖完成/跳过及待补结果状态 | `strategy_session_read_model.dart`、`strategy_cold_start_restore_test.dart` |
| 补交结果 | 不推断效果评价，保存期间锁定提交，失败重试与刷新不重复记结果 | `automatic_agent_controller.dart`、`automatic_agent_loop_test.dart` |
| Web 启动 | 单条命令准备字体、构建 Web、直接启动网关 | `tool/web/start-web.mjs`、`services/agent_gateway/package.json` |
| 编译浏览器验证 | 手机/桌面闭环、刷新恢复、已连接时管理控件默认折叠 | `services/agent_gateway/test/built-web-smoke.mjs` |
| 文档与协议 | 更新事件规范、启动说明和本阶段验证边界 | `specs`、`docs`、`README.md`、`CHANGELOG.md` |

当前分支为 `codex/web-only-validation-20261008`，整理时基线 HEAD 为 `57ae89b`。
远端已有 [PR #131](https://github.com/lse872317312010/personal-os/pull/131)，
分支为 `feature/structured-web-profile-20261008`。其 `f340bc9` 的资料编辑
版本已通过核心、契约和 Web CI。本轮接续整理源码启动、行动恢复、补交结果与
验证范围；本地与远端提交历史不同，候选版本须以文件树和实际 CI head 核对。
旧 PR 检查不能证明新增修复；本轮结论以以下候选代码的具体执行结果为准，
不代表合并或公开发布已完成。

2026-10-08 15:50（Asia/Shanghai）更新：本地候选代码提交 `16ffe5a`、远端
候选代码提交 `19cacae` 具有相同文件树
`a02653aa252a5cc70505c47ae08518d918d74a70`。该远端提交的核心、契约和 Web
CI 已通过，新增恢复用例也已在 Chrome 完成。本次结果记录只修改文档，
不改变上述候选代码；PR 仍未合并，公开下载页面未由此次 PR 更新。

## 已完成的本地验证

以下来自同一项目分支的分阶段执行结果。Flutter 使用 3.47.0，编译/浏览器
验证在隔离副本完成，构建产物未复制进源码工作树。

| 检查 | 结果 | 范围 |
| --- | --- | --- |
| Dart 格式检查 | 此前 34 个检查路径；行动恢复 4 个文件、最新补交结果 2 个文件已检查 | 工作流对应 Dart 文件 |
| Flutter analyze | No issues found | 应用及解析到的依赖 |
| 共享 Dart 核心全量 | 本轮本地及 `19cacae` CI 均为 23 个测试套件、373 项通过 | 本地使用 Flutter SDK 所带 Dart 和缓存依赖；远端 Dart 3.3.4 的格式、分析、测试和契约检查也已通过 |
| 仓库契约检查 | 本轮通过 | `bash tool/check_contracts.sh`；其中设备示例是 synthetic 数据，不是新真机证据 |
| Application 目标/资料测试 | 14 项通过 | 归属、版本、修订与归档 |
| Agent context 测试 | 6 项通过 | 活跃上下文与固定版本历史 |
| Flutter 应用全量测试 | 146 项通过 | Widget/控制器等本地套件，包含多行动恢复及新增补交结果/并发提交用例 |
| Session 读模型测试 | 3 项通过 | 从执行记录恢复行动 ID |
| Chrome Web 测试 | `19cacae` CI 37 项通过 | 自动闭环、行动优先、冷启动、多行动恢复及补交结果/并发提交 |
| Agent Gateway 测试 | 本轮 13 项通过 | 本地 HTTP、OAuth 替身、连接切换、加密存储等 |
| Web release 构建 | 最新行动恢复、补交结果修复后成功 | `lib/main_web_agent.dart` |
| 编译页面冒烟 | `19cacae` CI 手机 390×844、桌面 1440×900 均通过 | 最新候选的连接表单、本机网关、fixture Agent、反馈、失败后刷新恢复及连接管理默认折叠 |
| 单命令源码启动 | 此前构建、网关启动、页面与 bootstrap HTTP 200 | 测试时设 `PERSONAL_OS_OPEN_BROWSER=0`；未验证系统浏览器自动打开 |
| 差异与脚本检查 | 通过 | `git diff --check`、Node 语法与 package JSON |

最新多行动恢复用例已在本地 Flutter Widget 测试通过，覆盖完成、跳过和仅有执行
记录三种状态。补交结果测试验证中性评价、保存失败保留输入、模型失败后刷新
接续复盘及并发提交不重复写入。尝试在 Chrome 执行时，浏览器创建本地 socket 返回
`Operation not permitted`，本地启动失败；随后 `19cacae` 的远端 Chrome
套件已执行新用例并通过，不再把本地启动限制作为该候选的浏览器验收缺口。

本轮 CI 已加入 `tool/web/**` 的变更触发、启动脚本语法检查、Session 读模型
测试的格式检查和 `strategy_cold_start_restore_test.dart` 的 Chrome 执行。
上述范围已在本轮远端执行成功。

[Web CI #194](https://github.com/lse872317312010/personal-os/actions/runs/37745226802)
保留 `personal-os-agent-startup` 截图及 `personal-os-agent-web` 编译产物，
artifact 元数据均对应 `19cacae`。CI 已生成并上传截图，本会话下载返回
HTTP 403，未追加人工图片检查；截图上传与视觉复核分别记录。

浏览器冒烟确认中文字体与渲染器从应用自身加载，启动无外部资源请求。
Web 构建有 Cupertino 图标字体提示；应用源码未发现 `CupertinoIcons` 引用，
构建和上述浏览器流程成功。

这些验证使用明确的模型替身，没有进行真实 GPT 授权或推理。测试完成/跳过
记录属于 fixture 数据，不是用户的真实行动或效果证据。

## 下一阶段顺序

| 优先级 | 工作 | 完成判据 |
| --- | --- | --- |
| 已完成 / W0 | 固定可复现候选版本 | `19cacae` 的核心、契约、Web CI 和编译页面验证通过，截图与构建产物对应该提交 |
| P0 / W1 | 真实账号接入 | 在应用中完成实际可用账号授权或所选服务配置，选定模型，收到真实且通过协议校验的计划 |
| P0 / W2 | 同一目标两轮真实使用 | 计划 v1 → 用户明确行动反馈 → 复盘 → 计划 v2；v2 引用已有证据，刷新和网关重启保留历史，无重复事实 |
| P1 / W3 | 变化展示与真实跨 Agent 接续 | 页面清楚展示这轮改变与反馈依据；更换第二种实际服务后沿同一目标和历史完成后续请求 |
| 试用前 / W4 | Web 历史备份与恢复 | 用户可从 Web 导出/恢复历史，空白环境恢复一致，异常输入不破坏旧数据；不借用 Android 验证结论 |
| 后排 | 桌面包、Android 真机、同步 | 按用户后续安排恢复 |

完整工作范围和退出条件见 [当前路线图](ROADMAP.md)。W0 的候选代码、CI、
截图与产物对应关系已完成，下一步进入 W1 真实 Agent 接入验收。
真实账号等待期间可推进变化展示；真实接入
后按实际阻塞修复交互，不以增加模拟用例代替产品验收。

真实 GPT 首次授权需要用户完成账号登录/授权。两轮真实使用还需要用户实际
执行或明确选择跳过，并反馈结果；fixture 通过不能代替这些步骤。
两轮功能验收也不等同于 2–6 周实际效果验证或 `DOGFOOD_READY`。

## 当前启动入口

依赖：Node.js 22+、Flutter SDK；首次准备字体还需 Python 3 和网络。

在仓库根目录运行：

```sh
npm --prefix services/agent_gateway run web
```

默认地址为 `http://127.0.0.1:8787`。可用 `PERSONAL_OS_PORT` 修改端口，
用 `PERSONAL_OS_OPEN_BROWSER=0` 关闭自动打开浏览器。

接入、数据边界与错误恢复详见 [automatic-agent.md](automatic-agent.md)。
