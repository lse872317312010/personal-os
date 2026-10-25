# Oracle Always Free：开通服务器与启动 Personal OS

更新：2026-10-25（Asia/Shanghai）；免费资源规格沿用 2026-10-13 核对的方案，创建前以账号控制台的免费标签和剩余配额为准。

## 这套方案的范围

一台免费 Ubuntu Arm VM 承载 Personal OS Web 与 Node 网关，Windows 通过
SSH 隧道访问。使用已经编译的实验包，服务器无需 Flutter SDK，也无需在
宿主机安装 Node。暂不开放公网 Web API，不依赖 GitHub Pages。

更新包默认使用官方 Codex CLI 0.162.1。完成一次 ChatGPT 设备码登录后，
Web 网关通过 `codex exec` 自动提交上下文、接收计划/复盘/修订。使用订阅
额度，仍受账号实际权限和用量限制；不配置 API key、不自动转到付费 API。

网关 32 项、打包器 7 项及归档安全 5 项测试已通过 CI。原生 Arm64 Docker
已完成镜像构建、CLI 兼容性、只读运行、私有卷、强制停止恢复及真实备份恢复
加上镜像升级与回滚，共 9 项检查，使用合成资料和测试网页文件，没有登录账号或发起 AI 推理。
[容器验收记录](https://github.com/lse872317312010/personal-os/actions/runs/40166775128)。
部署包的 Web 产物来源也已核对。尚未在 OCI 实例执行，下列是待上机完成的流程。

本版网页已通过 153 项应用测试、44 项 Chrome 测试及手机/桌面编译页面验收。
选择 Codex 连接后，未登录会显示下述服务器登录命令；连接表单不再要求 API
地址或密钥。额度耗尽会保留计划和反馈，待额度恢复后再由你重试。
若模型列表为空，页面会撤下旧连接和模型，提示检查登录与模型配置；修复后
刷新连接即可恢复，单独刷新不会发起测试 AI 调用。
请求或 AI 响应测试中授权失效时，会显示登录指引并停止继续请求。重新登录后
刷新连接不会重复已经失败的自动复盘；确认恢复后再点击重试，已保存反馈不重写。

## 1. 注册或登录 Oracle Cloud

从 [Oracle Free Tier](https://www.oracle.com/cloud/free/) 进入注册，已有账号
则登录 [Oracle 控制台](https://cloud.oracle.com/)。手机号、邮箱、付款验证
和服务条款由账号持有人在 Oracle 页面完成，不把密码、验证码或卡号发到聊天。

注册时选择自己实际可用的 home region；本方案的免费实例和磁盘都放在该区。
不选择 Upgrade / Pay As You Go。不把限时 $300 Free Trial 额度当作 Always Free。

## 2. 创建免费 Ubuntu 实例

在 Compute → Instances 中选择创建实例（Create instance）。

| 设置 | 选择 |
| --- | --- |
| Name | `personal-os-lab` |
| Region | 当前账号 home region |
| Image | 官方、Always Free Eligible 的 Ubuntu 24.04 LTS Arm64；若没有，可选 Ubuntu 22.04 LTS Arm64 |
| Shape | `VM.Standard.A1.Flex` |
| OCPU | `1` |
| Memory | `6 GB` |
| Boot volume | `50 GB`，保留默认免费适用性能，不加其他块盘 |
| Network | 有 Internet Gateway 和默认互联网路由的 VCN、公有子网 |
| Public IPv4 | 分配公网 IPv4，用于 SSH |
| SSH key | 上传自己的公钥，或让 OCI 生成一对密钥并立即下载保存私钥 |

不要选择 Oracle Linux 镜像：本包的安装脚本使用 Ubuntu apt。不选择付费
Marketplace 镜像、额外数据库、负载均衡器或额外磁盘。

创建前核对 Shape/镜像免费标签与账号剩余配额。当前 A1 免费资源按账号合计
为每月 1,500 OCPU 小时、9,000 GB 内存小时（约持续运行 2 OCPU / 12GB），
启动盘与其他块盘共享 200GB 配额。已有资源占用也要计入。
保存后等实例变成 Running，记下公网 IPv4 和账号 home region。

若出现 `Out of host capacity`：在同一 home region 有其他 AD 时可以改选；
否则稍后再试，不升级付费，也不换成付费 Shape。

## 3. 配置 SSH 入站

在实例关联的子网 Security List / NSG 中，核对所有允许 SSH 的规则：

| 项目 | 值 |
| --- | --- |
| 来源 | 你的当前公网 IPv4 加 `/32` |
| 协议 | TCP |
| 目标端口 | `22` |

将默认 `0.0.0.0/0` 的 SSH 宽规则收紧到自己的 IP；仅添加一条窄规则不能
抵消另一条宽规则。换网络或公网 IP 后，要更新来源规则。
保留必要的出站规则，便于 apt、Docker 映像下载和后续 AI 服务访问。
本阶段不开放 `8787`、`80`、`443` 的公网入站。

## 4. 在 Windows 准备文件并连接

下载 `personal-os-oracle-experiment-20261013.tar.gz` 到 Downloads。
把 OCI 私钥存为 `.ssh\personal-os-oracle.key`。私钥仅供你自己使用；如果
OpenSSH 提示权限太宽，在文件属性 → 安全 → 高级中关闭继承，只保留自己
账户的访问权限。Oracle Linux 默认用户名是 `opc`，本方案 Ubuntu 用户名
是 `ubuntu`。

在 **Windows PowerShell** 定义以下变量（IP 要换成实例真实公网 IPv4）：

```powershell
$ServerIp = "替换为OCI公网IPv4"
$SshKey = "$env:USERPROFILE\.ssh\personal-os-oracle.key"
$Bundle = "$env:USERPROFILE\Downloads\personal-os-oracle-experiment-20261013.tar.gz"

Test-Path $SshKey
Test-Path $Bundle
ssh -i $SshKey "ubuntu@$ServerIp"
```

两个文件检查都应返回 True。首次 SSH 连接时先核对主机指纹，再确认保存；
不要设置跳过主机密钥检查。登录成功后提示符应来自云端 Ubuntu。
如果系统没有 ssh/scp，启用 Windows OpenSSH 客户端或使用已有 WSL。

## 5. 上传并解压实验包

再打开一个 **本机 PowerShell**，重新定义上面的三个变量，执行：

```powershell
scp -i $SshKey $Bundle "ubuntu@${ServerIp}:~/"
```

回到 **云端 SSH 终端**：

```bash
mkdir -p ~/personal-os-lab
cd ~/personal-os-lab
tar -xzf ~/personal-os-oracle-experiment-20261013.tar.gz
cd personal-os-oracle-experiment
sha256sum -c SHA256SUMS
```

所有文件都应显示 OK。首次使用新的空目录；不要在已有个人数据目录覆盖解压。

## 6. 安装 Docker 并启动服务

继续在 **云端 SSH 终端**执行：

```bash
sudo bash install-docker-ubuntu.sh
bash personal-os.sh start
sudo docker compose ps
```

安装脚本仅使用 Docker 官方 apt 仓库，识别 Arm64/x86_64 Ubuntu LTS。
`start` 会检查部署包 SHA256SUMS、核对 Compose 配置并等待服务 healthy。
它从脚本所在目录运行固定 Compose 文件，自动使用当前 Docker 权限或非交互
sudo；不会登录账号、调用 AI 或删除资料卷。
如果已有可用 Docker/Compose 就退出；遇到不完整安装或冲突包会停止，
不会自动卸载现有容器软件。初次启动会拉取 `node:22-bookworm-slim` 并构建
网关映像，网络耗时取决于实例的实际连接。

正常情况下服务为 running，健康检查稍后变为 healthy。应用使用命名卷
`history` 持久保存加密历史与配置，容器重建保留该卷。

## 7. 在服务器验证

仍在 **云端 SSH 终端**：

```bash
curl --fail -H 'X-Personal-OS: 1' http://127.0.0.1:8787/api/agent/status
curl --fail -H 'X-Personal-OS: 1' http://127.0.0.1:8787/api/health
curl --fail -I http://127.0.0.1:8787/
sudo ss -lntp 'sport = :8787'
```

首次期望：状态 JSON 中 `provider` 为 `codex-cli`、`connected` 为 false；页面 HTTP 200；监听地址为
`127.0.0.1:8787`，不是公网地址。状态请求还会返回本次进程的 CSRF 值，
不需要把整段状态响应公开或发到聊天。
这些结果只证明服务启动，不证明真实 AI 已接通。

### 7.0 一条命令诊断部署

```bash
sudo docker compose exec -T gateway node diagnostics.mjs
```

输出逐项检查网关、网页入口/脚本/字体、资料卷可写和至少 512 MiB 剩余空间、
固定 CLI 版本及 ChatGPT 登录。全部通过时 `ready=true`、退出码 0；未通过
时退出码 2，并给出对应检查项。首次尚未登录时，只有登录项失败属于正常。
如果保留着旧连接选择，应先在应用里选 Codex，再重跑检查。

诊断不调用 AI、不读取历史内容，也不输出令牌、账号列表或原始日志。
`inference_tested` 始终为 false：诊断通过仍须完成 7.1 的真实 AI 测试。
Docker 的 healthy 仅检查 `/api/health`；没有登录也可以 healthy。

### 7.1 连接 ChatGPT 订阅

在同一云端部署目录执行：

```bash
bash personal-os.sh login
sudo docker compose exec gateway codex login status
```

在你自己的浏览器打开终端给出的官方登录地址，输入设备码，登录购买 Plus
的账号。可能需要先在 ChatGPT 安全设置启用设备码登录。不要把设备码、
密码、`auth.json` 或令牌发到聊天，也不要使用 `--with-api-key`。

期望 CLI 显示 `Logged in using ChatGPT`。再执行上一节的状态请求，确认
`connected=true`；登录凭据保存在独立 `codex-auth` 卷，容器重建后仍保留。
要退出这条连接，执行 `sudo docker compose exec gateway codex logout`。

若沿用此前旧包且已有启动配置，在应用中选择「Codex · ChatGPT 订阅」；
启动配置会为旧配置补上这条连接并保留原选择；新安装默认选择 Codex。
不需要输入 API 地址或密钥。

打开网页后先点「测试 AI 响应」，这会消耗少量订阅额度但不发送个人历史。
通过后再输入真实目标，让应用生成策略，记录执行结果并完成一次复盘。
只有这条真实链路通过，才算 Plus 调用和 Personal OS 闭环上机验收完成。

### 7.2 在终端单独验收一次模型调用

也可以在云端部署目录执行：

```bash
bash personal-os.sh test-ai
```

它通过现有 HTTP 网关读取当前连接与模型列表，再发送一次固定内容的
`/api/agent/check`；会消耗订阅额度。它不切换连接、不读取或写入个人历史、
不输出账号、令牌、CSRF 或模型原文，也不会在失败后自动重试或转用付费 API。
`test-ai` 是显式调用入口，会传入 `--run-inference`。直接运行容器内的
`node acceptance.mjs` 且不加此参数时只显示用法，不发请求，退出码 2。

成功结果为 `inference_passed=true`、`code=passed`、退出码 0。
`inference_attempted=true` 仅表示向网关发送了测试请求，不能单独证明模型完成回复。
失败退出码为 2，`code` 和中文消息指出当前阻塞：

| code | 处理 |
| --- | --- |
| `codex_connection_required` | 在应用选择 Codex 连接 |
| `codex_chatgpt_login_required` | 当前是 API key 登录，退出后用 ChatGPT 账号登录 |
| `sign_in_required` | 完成或重新执行设备码登录 |
| `codex_usage_limit_reached` | 检查 ChatGPT/Codex 用量，等待额度恢复 |
| `rate_limit_exceeded` | 稍后重试 |
| `connection_changed` | 连接配置已更新，刷新应用后重跑 |
| `connection_check_timeout` | 测试超时，不会自动再发一次 |
| `codex_cli_request_failed` | CLI 未返回可识别的错误类型；检查权限、网络和部署诊断 |

错误分类只识别已知失败标记，其他情况保留通用失败，不猜测真实原因。
测试成功仍保留 `strategy_loop_tested=false` 和 `history_tested=false`，
接着要在网页完成以下人工验收：

1. 输入一个低敏感的真实目标，生成策略，确认行动卡可见。
2. 按真实发生的情况记录执行结果，生成复盘，再生成修订策略。
3. 刷新网页，确认行动与已记录结果恢复；重启容器后再次检查。
4. 检查修订是否使用了你的反馈。没有执行过的行动不要标成已完成。

只有这四项实际完成，才在验收记录中写“个人策略闭环已通过”。

官方说明：[非交互调用](https://learn.chatgpt.com/docs/non-interactive-mode)、
[设备码登录](https://learn.chatgpt.com/docs/auth)。

## 8. 从 Windows 打开网页

在 **本机 PowerShell** 定义 `$ServerIp`、`$SshKey` 后运行：

```powershell
ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -L 127.0.0.1:8787:127.0.0.1:8787 -i $SshKey "ubuntu@$ServerIp"
```

窗口停在这里没有文字输出是正常的；保持窗口打开。浏览器访问：

```text
http://127.0.0.1:8787
```

虽然地址是本机，页面与网关实际运行在 Oracle VM，通过 SSH 隧道转发。
这个隧道窗口只负责连接，不是在运行旧 Windows 启动包。
如果本机 8787 已占用，先关闭原本机网关；当前 Host 校验要求隧道两端
使用相同的 8787，不能只改前端端口。

## 9. 日常启动、停止与检查

以下都在 **云端部署目录**执行：

| 操作 | 命令 |
| --- | --- |
| 再次启动 | `sudo docker compose up -d` |
| 校验包、构建并重建容器，等待健康启动 | `bash personal-os.sh start` |
| 查看状态 | `sudo docker compose ps` |
| 无 AI 额度消耗的部署诊断 | `bash personal-os.sh status` |
| ChatGPT 设备码登录，需要交互式 SSH 终端 | `bash personal-os.sh login` |
| 调用一次固定内容验收，会消耗订阅额度 | `bash personal-os.sh test-ai` |
| 查看最近日志 | `sudo docker compose logs --tail=80 gateway` |
| 重启网关 | `sudo docker compose restart gateway` |
| 停止网关，保留资料与登录卷 | `bash personal-os.sh stop` |
| 停止并移除容器、保留历史卷 | `sudo docker compose down` |

`start` 每次都会重建网关容器以应用新镜像，服务会短暂中断；两个命名资料卷保留。
仅需日常启动已有容器时，使用表中的 `sudo docker compose up -d`。

Docker 与容器重启策略已启用，正常 VM 重启后服务会重新运行；本机 SSH
隧道仍需重新打开。不执行 `docker compose down -v`，它会删除历史卷。

要停止整个 VM，在 OCI 实例页使用 Stop；以后用 Start 恢复。恢复后重新核对
公网 IP、Security List 来源和 SSH 隧道，不假定所有停止/启动方式都保留地址。
只停止实例不等于释放所有资源和配额。

### 9.1 备份到自己的电脑

Always Free 闲置实例可能被回收。在云端部署目录以 SSH 用户执行（不在
`bash` 前加 sudo，脚本会按需调用 sudo Docker）：

```bash
bash backup-data.sh "$PWD/../personal-os-private-backup-20261013.tar.gz"
```

脚本临时停止网关、备份 `history` 和 `codex-auth` 卷，然后恢复之前的运行
状态。排除失效的 `runtime.lock` 和 CLI 可重新生成的 `codex-auth/tmp` 临时
目录；账号凭据仍保留。发布备份前使用随包的 `validate-backup.py` 检查格式，
其他链接或不安全条目会失败并清理临时归档。目标必须是新文件，不覆盖已有备份。
备份含 installation key
和登录凭据，权限为 600，不要公开上传。备份前结束登录操作。

在 Windows PowerShell 下载（调整服务器目录）：

```powershell
scp -i $SshKey "ubuntu@${ServerIp}:~/personal-os-lab/personal-os-private-backup-20261013.tar.gz" "$env:USERPROFILE\Downloads\"
```

仅备份 `history.private` 无法恢复加密记录。云端备份副本不能替代电脑副本。

### 9.2 在新实例恢复

上传部署包和私有备份、安装 Docker 后，在部署目录执行：

```bash
sudo docker compose build
bash restore-data.sh "$HOME/personal-os-private-backup-20261013.tar.gz"
sudo docker compose up -d
```

恢复脚本只接受普通文件/目录，拒绝路径越界和链接；只恢复到未运行容器
的两个空卷。运行中容器会直接拒绝，未经停止不会重建它。检测到已有数据
会停止，不自动删除或覆盖；解压、权限设置失败会返回错误，不报告成功。
失败时目标卷可能已含部分文件，不要启动应用或反复恢复覆盖，先保留原始
备份并确认失败原因，再选择全新空卷重试。恢复后核对历史、
CLI 登录和网页；若登录过期，重新设备码登录。合成数据已在真实 Arm64 Docker
完成备份恢复；账号会话能否继续使用仍需在你的实例上验证。

### 9.3 更新版本与回滚

在旧部署目录操作，先结束登录、AI 请求和网页编辑；更新期间暂停使用网页。
先保存新文件名的私有备份，并保留旧版本完整部署包。不要直接把新包覆盖解压
到旧目录，否则可能混入已被新版本移除的文件。

```bash
bash backup-data.sh "$PWD/../personal-os-before-upgrade-$(date -u +%Y%m%dT%H%M%SZ).tar.gz"
old_container=$(sudo docker compose ps -q gateway)
test -n "$old_container"
old_image=$(sudo docker inspect --format '{{.Image}}' "$old_container")
rollback_image="personal-os-rollback:$(date -u +%Y%m%dT%H%M%SZ)"
sudo docker image tag "$old_image" "$rollback_image"
printf 'services:\n  gateway:\n    image: %s\n' "$rollback_image" > ../personal-os-rollback.yaml
```

把新包解压到旧部署目录同级的另一个空目录后，进入新部署目录运行 `bash personal-os.sh start`。
保持 Compose 的项目名为 `personal-os-oracle-experiment`；如果旧部署使用了
`COMPOSE_PROJECT_NAME`，新目录也必须使用相同的值，才能连接原来的两个卷。
不要删除卷、清理旧镜像或执行 `down -v`。

启动后运行 `bash personal-os.sh status`，刷新网页核对历史与当前行动。登录
已过期时重新运行 `login`；`test-ai` 仍须显式执行，升级不会自动调用 AI。

如果新版本启动或页面检查失败，进入保留的旧部署目录，使用刚保存的镜像回滚：

```bash
sudo docker compose -f compose.yaml -f ../personal-os-rollback.yaml up -d --no-build --force-recreate --wait --wait-timeout 90
bash personal-os.sh status
```

回滚使用已保留的旧镜像并继续挂载原卷；不会重新构建镜像或自动恢复备份。
旧目录、回滚配置和原项目名必须保持对应。此流程适用于数据格式兼容的更新；
若未来版本引入不兼容的数据迁移，须按该版本的迁移方案操作，不能假定旧镜像
可以读取新数据。需要恢复升级前快照时，应按 9.2 使用全新空卷，保留现有卷。

## 常见阻塞

| 现象 | 优先检查 |
| --- | --- |
| OCI 无 A1 容量 | 当前 home region、AD 和实际错误；不改成付费规格 |
| SSH 超时 | 实例 Running、公网 IPv4、公有子网、互联网路由、自己的 IP/32 入站 |
| Permission denied (publickey) | Ubuntu 用户名 `ubuntu`、私钥与实例公钥匹配、私钥访问权限 |
| 安装脚本提示不是 Ubuntu | 创建了 Oracle Linux；按本方案重新选择 Ubuntu，或另用该发行版安装流程 |
| Docker 拉取失败 | 实例出站、DNS、软件仓库和 Docker Hub 的实际连通性 |
| 8787 已被占用 | 云端是否已有网关或其他进程，本机是否已有本地服务 |
| 页面打不开 | 云端页面 HTTP 200、隧道窗口仍在、本机访问地址确为 `127.0.0.1:8787` |
| connected=false | 检查 `codex login status`；首次未登录或凭据失效 |
| healthy 但不能生成策略 | healthy 只代表网关存活；运行部署诊断后再测试 AI 响应 |
| codex_chatgpt_login_required | CLI 使用了 API key；退出后改为 ChatGPT 设备码登录 |
| codex_cli_request_failed | CLI 调用失败；核对账号额度、云端出站与模型权限；不会转付费 API |

## 官方依据

- [Always Free 配额](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm)
- [Oracle Linux 实例开通与 SSH 教程（本方案将镜像改为 Ubuntu）](https://docs.oracle.com/en-us/iaas/Content/Compute/tutorials/first-linux-instance/overview.htm)
- [Docker Ubuntu 安装方法](https://docs.docker.com/engine/install/ubuntu/)
- [Oracle 免费账号 FAQ](https://www.oracle.com/cloud/free/faq/)
