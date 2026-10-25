#!/usr/bin/env bash
# Server-side controls for the private Oracle deployment, not a desktop package.
set -Eeuo pipefail
directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
usage() {
  cat <<'TEXT'
Usage: bash personal-os.sh <command>
  start    校验部署包、构建并等待网关健康；不调用 AI
  status   检查部署与 ChatGPT 登录；不调用 AI，未就绪返回 2
  login    在交互式 SSH 终端完成 ChatGPT 设备码登录
  test-ai  调用一次固定测试内容，会使用订阅额度
  stop     停止网关，保留个人资料和登录卷
TEXT
}
command=${1:-help}
[[ $# -le 1 ]] || { usage >&2; exit 2; }
case "$command" in
  help|--help|-h) usage; exit 0 ;;
  start|status|login|test-ai|stop) ;;
  *) usage >&2; exit 2 ;;
esac
if [[ "$command" == login && ( ! -t 0 || ! -t 1 ) ]]; then
  echo '登录需要交互式 SSH 终端；请直接在终端运行 bash personal-os.sh login。' >&2
  exit 2
fi
cd -- "$directory"
[[ -f compose.yaml ]] || { echo '缺少 compose.yaml，请使用完整部署包。' >&2; exit 2; }
if [[ "$command" == start ]]; then
  [[ -f SHA256SUMS ]] || { echo '缺少 SHA256SUMS，请重新解压完整部署包。' >&2; exit 2; }
  sha256sum --check --quiet SHA256SUMS || { echo '部署包校验失败，未启动服务。' >&2; exit 2; }
fi
docker_cmd=(docker)
if ! docker info >/dev/null 2>&1; then
  sudo -n docker info >/dev/null 2>&1 || { echo 'Docker 未运行或没有权限；先安装 Docker，或在有权限的终端运行。' >&2; exit 2; }
  docker_cmd=(sudo -n docker)
fi
# Pin the compose file and working directory even when launched elsewhere or
# when COMPOSE_FILE is set in the caller's shell. Preserve COMPOSE_PROJECT_NAME
# for separately named deployments and isolated container tests.
compose=("${docker_cmd[@]}" compose --project-directory "$directory" -f "$directory/compose.yaml")
case "$command" in
  start)
    "${compose[@]}" config --quiet
    "${compose[@]}" up --build -d --force-recreate --wait --wait-timeout 90
    echo '网关已健康启动；接着运行 login、status，再按需运行 test-ai。网页仍需 SSH 隧道。'
    ;;
  status) "${compose[@]}" exec -T gateway node diagnostics.mjs ;;
  login) "${compose[@]}" exec gateway codex login --device-auth ;;
  test-ai) "${compose[@]}" exec -T gateway node acceptance.mjs --run-inference ;;
  stop) "${compose[@]}" stop gateway ;;
esac
