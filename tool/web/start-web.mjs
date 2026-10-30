import { spawn, spawnSync } from 'node:child_process';
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const appRoot = join(repoRoot, 'apps/personal_os_app');
const gatewayRoot = join(repoRoot, 'services/agent_gateway');
const webRoot = join(appRoot, 'build/web');
const font = join(appRoot, 'web/fonts/NotoSansSC.ttf');
const fontBlob = '5371a543be5fc670c7cdee9760c03554ee3e9b8e';

function run(executable, args, cwd) {
  const result = spawnSync(executable, args, { cwd, stdio: 'inherit' });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}

async function main() {
  let hasPinnedFont = false;
  try {
    const bytes = await readFile(font);
    const blob = createHash('sha1').update(`blob ${bytes.length}\0`).update(bytes).digest('hex');
    hasPinnedFont = blob === fontBlob;
  } catch { /* Fetch the pinned font below. */ }
  if (!hasPinnedFont) {
    const python = process.env.PERSONAL_OS_PYTHON || (process.platform === 'win32' ? 'python' : 'python3');
    run(python, [join(repoRoot, 'tool/prepare_local_web_font.py')], repoRoot);
  }

  const flutter = process.env.PERSONAL_OS_FLUTTER_BIN || 'flutter';
  run(flutter, [
    'build', 'web', '--release', '--base-href', '/',
    '--target', 'lib/main_web_agent.dart',
  ], appRoot);

  const server = spawn(process.execPath, ['server.mjs'], {
    cwd: gatewayRoot,
    stdio: 'inherit',
    env: {
      ...process.env,
      PERSONAL_OS_WEB_ROOT: process.env.PERSONAL_OS_WEB_ROOT || webRoot,
      PERSONAL_OS_OPEN_BROWSER: process.env.PERSONAL_OS_OPEN_BROWSER || '1',
    },
  });
  const stopServer = signal => {
    if (server.exitCode === null && !server.killed) server.kill(signal);
  };
  process.once('SIGINT', () => stopServer('SIGINT'));
  process.once('SIGTERM', () => stopServer('SIGTERM'));
  server.once('error', error => {
    console.error(`Unable to start the Personal OS Web gateway: ${error.message}`);
    process.exitCode = 1;
  });
  server.once('exit', (code, signal) => {
    process.exitCode = signal ? 1 : (code ?? 1);
  });
}

main().catch(error => {
  console.error(`Unable to prepare the Personal OS Web app: ${error.message}`);
  process.exitCode = 1;
});
