import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';

const messages = {
  not_requested: '未调用 AI；加 --run-inference 执行一次固定内容测试，会使用订阅额度',
  gateway_unavailable: '网关不可访问：先运行部署诊断',
  codex_connection_required: '请在应用中选择 Codex · ChatGPT 订阅连接',
  sign_in_required: 'ChatGPT 登录未就绪或已失效：重新执行设备码登录',
  codex_chatgpt_login_required: '当前是 API key 登录：退出后改用 ChatGPT 账号登录',
  codex_cli_not_installed: '未找到 CLI：重新构建网关镜像',
  codex_cli_unavailable: 'CLI 无法运行：检查容器并重跑部署诊断',
  codex_usage_limit_reached: 'ChatGPT/Codex 使用额度已达上限；等待恢复或检查账号用量',
  rate_limit_exceeded: '请求过于频繁：稍后重试',
  connection_changed: '连接配置已经改变：刷新应用后重新验收',
  agent_busy: '网关正在执行其他任务：完成后重新验收',
  model_not_available: '当前连接没有可用模型',
  invalid_model_catalog: '模型列表格式错误',
  invalid_provider_response: '模型响应格式错误',
  provider_response_interrupted: '模型响应未完整结束',
  codex_cli_tools_not_allowed: '模型尝试使用未授权工具，响应已拒绝',
  connection_check_timeout: '模型测试超时：本次不会自动重试',
  codex_cli_timeout: 'CLI 调用超时：本次不会自动重试',
  codex_cli_request_failed: 'CLI 请求失败；部署和登录成功仍不保证推理权限',
  invalid_csrf: '网关进程已改变：重新运行验收',
  provider_request_failed: '模型请求失败，未输出原始日志；检查账号权限和网络',
  passed: 'ChatGPT 账号下的模型已完成一次真实响应；尚未验收个人策略和历史恢复',
};

// This probe only uses the gateway's fixed /check request. No history access,
// account switching, credentials, model text, prompts, or raw errors in output.
// Fetch is injectable for tests; origin must stay loopback for real execution.
export async function inferenceAcceptance({ runInference = false, origin = 'http://127.0.0.1:8787', fetcher = fetch } = {}) {
  const report = { acceptance_version: 'personal-os.inference-check.v1', inference_requested: runInference === true, inference_attempted: false, inference_passed: false, strategy_loop_tested: false, history_tested: false };
  const finish = code => ({ ...report, code, message: messages[code] || messages.provider_request_failed });
  if (runInference !== true) return finish('not_requested');
  try {
    const url = new URL(origin);
    if (url.protocol !== 'http:' || url.hostname !== '127.0.0.1' || url.username || url.password || url.pathname !== '/' || url.search || url.hash) return finish('gateway_unavailable');
  } catch { return finish('gateway_unavailable'); }
  const headers = { 'X-Personal-OS': '1' };
  let phase = 'status';
  try {
    const statusResponse = await fetcher(`${origin}/api/agent/status`, { headers, redirect: 'error', signal: AbortSignal.timeout(12_000) });
    if (!statusResponse.ok) return finish('gateway_unavailable');
    const status = await statusResponse.json();
    if (status.provider !== 'codex-cli') return finish('codex_connection_required');
    if (status.connected !== true) return finish(Object.hasOwn(messages, status.error) && status.error !== 'passed' ? status.error : 'sign_in_required');
    if (typeof status.csrf !== 'string' || !status.csrf || typeof status.connection_id !== 'string' || !status.connection_id || typeof status.connection_revision !== 'string' || !status.connection_revision) return finish('invalid_provider_response');
    phase = 'models';
    const query = new URLSearchParams({ connection_id: status.connection_id, connection_revision: status.connection_revision });
    const modelsResponse = await fetcher(`${origin}/api/agent/models?${query}`, { headers, redirect: 'error', signal: AbortSignal.timeout(12_000) });
    if (!modelsResponse.ok) {
      const body = await modelsResponse.json();
      return finish(body.error === 'connection_changed' ? 'connection_changed' : 'model_not_available');
    }
    const { models } = await modelsResponse.json();
    if (!Array.isArray(models)) return finish('invalid_model_catalog');
    if (models.length !== 1 || typeof models[0]?.id !== 'string' || !models[0].id) return finish('model_not_available');
    phase = 'inference';
    report.inference_attempted = true;
    const response = await fetcher(`${origin}/api/agent/check`, {
      method: 'POST', redirect: 'error', signal: AbortSignal.timeout(35_000),
      headers: { ...headers, 'Content-Type': 'application/json', 'X-Personal-OS-CSRF': status.csrf },
      body: JSON.stringify({ model: models[0].id, connection_id: status.connection_id, connection_revision: status.connection_revision }),
    });
    const body = await response.json();
    if (!response.ok) return finish(Object.hasOwn(messages, body.error) && !['passed', 'not_requested'].includes(body.error) ? body.error : 'provider_request_failed');
    if (body.ok !== true || body.provider !== 'codex-cli' || body.model !== models[0].id) return finish('invalid_provider_response');
    report.inference_passed = true;
    return finish('passed');
  } catch (error) {
    return finish(phase === 'inference' ? ['AbortError', 'TimeoutError'].includes(error?.name) ? 'connection_check_timeout' : 'provider_request_failed' : 'gateway_unavailable');
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  if (args.length > 1 || (args.length === 1 && args[0] !== '--run-inference')) {
    console.error('Usage: node acceptance.mjs [--run-inference]');
    process.exitCode = 2;
  } else {
    const report = await inferenceAcceptance({ runInference: args[0] === '--run-inference' });
    console.log(JSON.stringify(report, null, 2));
    process.exitCode = report.inference_passed ? 0 : 2;
  }
}
