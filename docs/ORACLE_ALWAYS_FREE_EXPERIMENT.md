# Oracle Always Free：Personal OS 私有部署实验

更新：2026-10-22（Asia/Shanghai）；免费资源规格沿用 2026-10-13 核对的方案，创建前以账号控制台的免费标签和剩余配额为准。

## 实际状态

本轮新增独立调用验收 `node acceptance.mjs --run-inference`，通过现有网关
发送一次固定测试内容。只有完成有效模型响应才报告 `inference_passed=true`；
登录、额度上限、临时限速、超时和格式错误分别给出固定错误码，不输出原始
日志或凭据，不读写个人历史，也不自动重试或切换付费 API。
本轮 32 项网关测试、6 项打包器测试通过，包含真实 HTTP 和替身 CLI 子进程；
这些结果不能证明真实 ChatGPT 推理、Arm 容器或 OCI 部署已经通过。
没有获得实例 IP 和 SSH 访问，真实部署、账号登录与两轮策略验收仍待上机完成。

2026-10-13 浏览器打开 `https://cloud.oracle.com/` 返回 “Site Unavailable / Unable to
access this site”，刷新一次仍相同。没有进入登录、选择租户或创建云资源。
没有升级付费账号，也没有发生真实 AI 推理。

本地准备已完成：编译 ZIP 的 SHA-256 与 CI artifact 元数据一致；部署目录的
原始包文件通过清单校验；使用打包网关启动隔离测试服务，状态、页面、JavaScript
和中文字体均返回 HTTP 200；错误 ZIP 哈希会被拒绝且不产生输出目录。
更新网关 23 项测试通过，包含 CLI 完整输出、API-key 拒绝、取消、隔离目录
清理，以及真实 HTTP 接口的计划/复盘/修订和旧连接拒绝（使用替身 CLI）。
此前已安装并检查官方 CLI 0.162.1 的版本、exec 帮助和 features 开关。
前版部署目录的 48 项文件哈希已验证，33 个 Web 文件与此前包逐字节一致。
前版打包网关在隔离配置下调用官方 CLI 得到未登录状态；页面、脚本、字体均
返回 HTTP 200，写入的测试历史在网关重启后恢复。没有使用真实个人资料。
本轮 5 项备份脚本测试验证完整数据往返、私有权限、失败清理及原运行状态
恢复、不覆盖已有数据、运行中拒绝恢复、危险归档提前拒绝及解压失败不误报
成功；它们使用 Docker 命令替身和真实 shell/tar。
新增 `node diagnostics.mjs` 不请求推理、不读取历史，健康检查只查询存活接口。
Compose 的 YAML 与私有监听配置已检查，但当前环境
没有 Docker，未构建容器、未执行 Arm 机器或 OCI 运行验证。

Web 输入固定为已通过核心、应用、Chrome 和编译页面 CI 的候选代码
`19cacae`（同文件树本地提交 `16ffe5a`），以及 Web CI #194 的
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

在源码仓库内，将 Web CI #194 对应的 `personal-os-agent-web` ZIP 传给：
源码必须包含候选提交 `19cacae`（例如检出 PR #131 的分支）；在本次工作区
也可使用文件树完全相同的 `16ffe5a`。脚本会再次核对整个源码文件树。

```sh
gateway_commit=$(git rev-parse HEAD)
python3 tool/oracle/prepare-experiment.py personal-os-agent-web-19cacae.zip personal-os-oracle-experiment --gateway-source "$gateway_commit"
```

`--gateway-source` 必须是包含 CLI 和部署脚本的完整 40 位提交 SHA；运行时、
镜像配置和文档均从该提交读取。也可用 `--base-bundle` 复用先前的精确
v2/v3/v4 归档，脚本会校验固定归档哈希并只取 Web 文件。其他未提交改动不会进入包。

产物校验值应为：

```text
f0144a03c356998c8a2acde6cd84aa36393f0a3cebdc033ad0de4392e9d3c1bd
```

脚本拒绝错误哈希、缺失编译入口、不安全压缩包条目和已存在的输出目录。
目录只包含指定源码版本的网关、已编译 Web、部署配置和校验清单，
不包含账号凭据、SSH 私钥或个人历史。云实例无需安装 Flutter SDK。

## 云实例上运行

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
