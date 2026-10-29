import { access, statfs } from 'node:fs/promises';
import { constants } from 'node:fs';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { cliEnvironment } from './codex-cli.mjs';

const exec = promisify(execFile);
async function checkStorage(profile) {
  await access(profile, constants.W_OK);
  const disk = await statfs(profile);
  return Number(disk.bavail) * Number(disk.bsize) >= 512 * 1024 * 1024;
}
async function checkCli() {
  const { stdout } = await exec(process.env.PERSONAL_OS_CODEX_BIN || 'codex', ['--version'], { env: cliEnvironment(), timeout: 3000, maxBuffer: 1024 });
  return stdout.trim() === 'codex-cli 0.162.1';
}

// Read-only probes only. Never request inference, history or logs. Allowlist
// two public status fields; discard accounts, CSRF and all raw exceptions.
export async function deploymentDiagnostics({ origin = 'http://127.0.0.1:8787', profile = process.env.PERSONAL_OS_PROFILE || '/var/lib/personal-os', fetcher = fetch, storage = checkStorage, cli = checkCli } = {}) {
  const checks = [];
  async function check(name, action, passed, failed) {
    let ok = false;
    try { ok = (await action()) === true; } catch { /* raw errors may contain credentials */ }
    checks.push({ check: name, ok, message: ok ? passed : failed });
  }
  const get = path => fetcher(origin + path, { headers: { 'X-Personal-OS': '1' }, redirect: 'error', signal: AbortSignal.timeout(12_000) });
  await check('gateway', async () => {
    const response = await get('/api/health'); return response.ok && (await response.json()).ok === true;
  }, '网关正常', '网关未就绪：检查容器状态和 8787 端口');
  for (const path of ['/', '/flutter_bootstrap.js', '/main.dart.js', '/fonts/NotoSansSC.ttf']) {
    await check(path === '/' ? 'web' : path.split('/').pop(), async () => {
      const response = await fetcher(origin + path, { method: 'HEAD', redirect: 'error', signal: AbortSignal.timeout(3000) });
      await response.body?.cancel(); return response.ok;
    }, '网页文件可访问', '网页文件缺失：重新核对部署包');
  }
  await check('storage', () => storage(profile), '资料卷可写，剩余空间至少 512 MiB', '资料卷不可写或剩余空间不足 512 MiB');
  await check('cli', cli, 'CLI 版本与部署包一致', 'CLI 不可运行或版本不符：重新构建镜像');
  await check('chatgpt_login', async () => {
    const response = await get('/api/agent/status');
    if (!response.ok) return false;
    const status = await response.json();
    return status.provider === 'codex-cli' && status.connected === true;
  }, 'Codex 的 ChatGPT 登录已就绪', '选择 Codex 连接并检查设备码登录；此项不验证额度和推理权限');
  return { diagnostic_version: 'personal-os.deployment-check.v1', ready: checks.every(c => c.ok), inference_tested: false, checks };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const report = await deploymentDiagnostics();
  console.log(JSON.stringify(report, null, 2));
  process.exitCode = report.ready ? 0 : 2;
}
