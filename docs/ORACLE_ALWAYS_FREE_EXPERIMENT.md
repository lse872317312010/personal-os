# Oracle Always Free：Personal OS 私有部署实验

更新：2026-10-22（Asia/Shanghai）；免费资源规格沿用 2026-10-13 核对的方案，创建前以账号控制台的免费标签和剩余配额为准。

## 实际状态

网页已补齐 Codex 账号模式：连接表单不要求 API 地址或密钥，切换服务类型时
不会把旧密钥带入账号模式；未登录时显示服务器登录指引，额度耗尽时保留目标、
计划与反馈，并避免生命周期重连自动重复请求。
初次状态正常但模型列表为空时，也会清除旧模型和就绪状态，并提示检查登录
与模型配置，防止页面显示已连接却无法继续。刷新连接本身不调用 AI。
请求或连接测试返回授权失效时，也会清除连接与模型就绪状态。重新登录不重置
同一复盘的自动尝试记录；已保存反馈保持原样，显式重试后才再次请求。
Web 候选 `84dbc19ab105cd837e7406c8c380a918b9dd1a32` 已通过
[Web CI #201](https://github.com/lse872317312010/personal-os/actions/runs/39797256169)：
153 项应用测试、44 项 Chrome 测试、32 项网关测试、手机/桌面编译页面闭环。
核心 Dart 和仓库契约 CI 同时通过。测试使用替身 Agent，未请求真实模型。

本轮新增独立调用验收 `node acceptance.mjs --run-inference`，通过现有网关
发送一次固定测试内容。只有完成有效模型响应才报告 `inference_passed=true`；
登录、额度上限、临时限速、超时和格式错误分别给出固定错误码，不输出原始
日志或凭据，不读写个人历史，也不自动重试或切换付费 API。
32 项网关测试、7 项打包器测试、5 项归档安全测试已通过 CI，包含真实 HTTP
和替身 CLI 子进程。原生 Arm64 Docker 的 7 项检查也已通过：构建固定 CLI
镜像、未登录健康启动、命令兼容性、只读运行与私有卷、强制停止后的历史恢复、
真实备份与全新卷恢复，以及运行中/非空卷拒绝恢复。
验收源码 `84dbc19ab105cd837e7406c8c380a918b9dd1a32`，
[CI 运行记录](https://github.com/lse872317312010/personal-os/actions/runs/39797256850)。
容器使用合成历史、登录卷标记和测试网页文件，没有登录真实账号或请求 AI，
不能据此声称真实 ChatGPT 推理或 OCI 部署已经通过。
没有获得实例 IP 和 SSH 访问，真实部署、账号登录与两轮策略验收仍待上机完成。

2026-10-13 浏览器打开 `https://cloud.oracle.com/` 返回 “Site Unavailable / Unable to
access this site”，刷新一次仍相同。没有进入登录、选择租户或创建云资源。
没有升级付费账号，也没有发生真实 AI 推理。

部署包现使用 Web CI #201 的完整编译产物，并校验固定 SHA-256；不混用旧网页。
`node diagnostics.mjs` 不请求推理、不读取历史；Docker 健康检查只查询存活接口。
真实容器测试发现旧备份会包含 CLI 在 `codex-auth/tmp/arg0` 生成的符号链接，
恢复时因此被安全校验拒绝。新版排除这个临时目录，并在发布备份前使用与恢复
相同的 `validate-backup.py` 校验。其他位置出现链接或不安全条目仍会失败，
不放宽恢复规则。已有旧包应更新部署脚本后重新备份，保留原始归档。

Web 输入固定为已通过核心、应用、Chrome 和编译页面 CI 的候选代码
`84dbc19`，以及 Web CI #201 的
`personal-os-agent-web` 编译产物；不混入工作树中的其他未提交修改。
网关来自清单中单独固定的提交，包含 Codex CLI 适配；其测试不能证明真实
Plus 推理已经接通。默认选择 `codex-cli`，要求 ChatGPT 登录，不自动配置
付费 API。镜像安装官方 CLI，登录态由独立命名卷保留。

## 免费实例规格

在账号 home region 中选 `VM.Standard.A1.Flex`、Always Free Eligible 的
Ubuntu 镜像；初次实验建议 **1 OCPU、6GB 内存、50GB 启动盘**。

当前官方 A1 总免费配额是每月 1,500 OCPU 小时与 9,000 GB 内存小时，
相当于持续运行的 2 OCPU / 12GB；启动盘和其他块存储共享 200GB 免费配额。
先核对账号已有实例与磁盘的合计，不能把每个实例都当成独立免费额度。
不使用试用金创建付费规格，不开付费数据库、负载均衡器或额外磁盘。
若 home region 无容量，记录实际错误；不升级付费或不断循环抢占。
闲置实例可能被回收，需另行备份用户数据。

来源：[Oracle Always Free 资源](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm)。

## 网络边界

服务器只开放 SSH，来源限制为操作者的公网 IP `/32`。
Node 网关保持监听 `127.0.0.1:8787`；**不开放 OCI 的 8787 入站规则**。
通过 SSH 隧道将服务器页面转到操作者电脑的相同地址。
这不是多用户公网部署，也不是 GitHub Pages 直连云端 API。

容器使用 Linux host 网络，以保留原网关的 loopback 绑定；它不会把网关
改为监听 `0.0.0.0`。此配置用于 OCI Linux VM，不作为 Windows/Linux 桌面包维护。

## 准备部署目录

若已经下载完整实验包，解压后直接跳到“云实例上运行”，无需此准备步骤。

在源码仓库内，将 Web CI #201 对应的 `personal-os-agent-web` ZIP 传给：
检出包含 Oracle 部署脚本的源码版本，例如 PR #133 的分支。脚本核对固定的
Web 归档哈希，并只从指定的 Git 提交读取网关、部署文件与文档的允许清单。

```sh
gateway_commit=$(git rev-parse HEAD)
python3 tool/oracle/prepare-experiment.py personal-os-agent-web-84dbc19.zip personal-os-oracle-experiment --gateway-source "$gateway_commit"
```

`--gateway-source` 必须是包含 CLI 和部署脚本的完整 40 位提交 SHA；运行时、
镜像配置和文档均从该提交读取。旧部署包包含更新前的网页，本版本不接受
`--base-bundle` 复用旧网页，避免把旧字节标记为新候选。未提交改动不会进入包。

产物校验值应为：

```text
8c9077d43c0ac0469e59e8e935742468b82cde46c49984a807e3a5ea288ea378
```

脚本拒绝错误哈希、缺失编译入口、不安全压缩包条目和已存在的输出目录。
目录只包含指定源码版本的网关、已编译 Web、部署配置和校验清单，
不包含账号凭据、SSH 私钥或个人历史。云实例无需安装 Flutter SDK。

## 云实例上运行

部署包包含统一入口 `personal-os.sh`：`start` 校验并启动、`status` 只做诊断、
`login` 设备码登录、`test-ai` 显式调用一次固定测试内容、`stop` 停止并保留卷。
具体命令见 `START_HERE.md`。首次安装 Docker 后无需逐条拼接 Compose 命令。

1. 安装官方 [Docker Engine](https://docs.docker.com/engine/install/ubuntu/)
   及 Compose 插件，然后把部署目录传到自己的实例。
2. 在部署目录核对文件并启动：

```sh
sha256sum -c SHA256SUMS
sudo docker compose up --build -d
sudo docker compose ps
curl --fail -H 'X-Personal-OS: 1' http://127.0.0.1:8787/api/agent/status
```

首次状态应为未连接，不能把 HTTP 200 当作 AI 推理成功。
命名卷 `history` 保存加密配置与历史，容器重启保留；Unix 加密密钥也在
同一实例，不等同于硬件密钥库或云运营方无法访问的端到端加密。

3. 在操作者电脑执行（替换自己的实例 IP 和 SSH 私钥路径）：

```sh
ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:8787:127.0.0.1:8787 -i /path/to/oci-key ubuntu@INSTANCE_PUBLIC_IP
```

浏览器打开 `http://127.0.0.1:8787`。维持隧道期间才可访问。
若本机该端口已占用，先关闭原网关；不要任意更换前端端口后绕过 Host 校验。

## 验证与结束实验

- 核对实际 Shape、home region、账号剩余配额和镜像免费标签；
- 验证容器健康、页面/字体 HTTP 200、状态未连接、服务未监听公网接口；
- 设备码登录自己的 ChatGPT 账号，测试 AI 响应后完成一次计划/执行/复盘；
- 验证重启容器后测试历史可恢复，再把私有备份下载到自己的电脑；
- 记录实际映像 ID、实例 OCID、区域和错误，不记录令牌或用户上下文；
- `sudo docker compose down` 停止服务并保留历史卷；不要执行 `down -v`，
  除非用户明确要求删除该卷的数据；
- OCI 资源释放和删除启动盘需在确认没有需要保留的数据后单独执行。

目前没有完成 OCI 实例运行、Docker 映像构建或真实 Codex 登录验收。
