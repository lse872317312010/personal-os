import { mkdir, readFile, writeFile, rename, chmod } from 'node:fs/promises';
import { join } from 'node:path';
import { randomUUID, randomBytes, createCipheriv, createDecipheriv } from 'node:crypto';
import { spawn } from 'node:child_process';

// Windows credentials and personal history are protected with current-user
// DPAPI. Unix encrypts records with AES-256-GCM and keeps its installation key
// in an owner-only file; it does not claim hardware/OS-keystore protection.
function dpapi(value, decrypt) {
  const script = `Add-Type -AssemblyName System.Security; [Console]::InputEncoding=New-Object Text.UTF8Encoding($false); [Console]::OutputEncoding=New-Object Text.UTF8Encoding($false); $v=[Console]::In.ReadToEnd(); $b=${decrypt ? '[Convert]::FromBase64String($v)' : '[Text.Encoding]::UTF8.GetBytes($v)'}; $r=[Security.Cryptography.ProtectedData]::${decrypt ? 'Unprotect' : 'Protect'}($b,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser); [Console]::Out.Write(${decrypt ? '[Text.Encoding]::UTF8.GetString($r)' : '[Convert]::ToBase64String($r)'});`;
  return new Promise((resolve, reject) => {
    const child = spawn('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', script], { windowsHide: true, stdio: ['pipe', 'pipe', 'ignore'] });
    let result = '';
    child.stdout.on('data', chunk => { result += chunk; });
    child.on('error', () => reject(new Error('protected_storage_unavailable')));
    child.on('exit', code => code === 0 ? resolve(result) : reject(new Error('protected_storage_unavailable')));
    child.stdin.end(value);
  });
}

export class ProtectedStore {
  constructor(directory) { this.directory = directory; }
  async key() {
    if (!this.keyPromise) this.keyPromise = (async () => {
      await mkdir(this.directory, { recursive: true, mode: 0o700 });
      await chmod(this.directory, 0o700);
      const path = join(this.directory, 'installation-key.private');
      try { await writeFile(path, randomBytes(32), { mode: 0o600, flag: 'wx' }); }
      catch (error) { if (error.code !== 'EEXIST') throw error; }
      const value = await readFile(path);
      if (value.length !== 32) throw new Error('protected_storage_unavailable');
      await chmod(path, 0o600);
      return value;
    })();
    return this.keyPromise;
  }
  async read(name, fallback = null) {
    try {
      let data = await readFile(join(this.directory, `${name}.private`), 'utf8');
      if (process.platform === 'win32') data = await dpapi(data, true);
      else {
        const envelope = JSON.parse(data);
        if (envelope.version !== 1) throw new Error('protected_storage_unavailable');
        const decipher = createDecipheriv('aes-256-gcm', await this.key(), Buffer.from(envelope.iv, 'base64'));
        decipher.setAAD(Buffer.from(name));
        decipher.setAuthTag(Buffer.from(envelope.tag, 'base64'));
        data = Buffer.concat([decipher.update(Buffer.from(envelope.ciphertext, 'base64')), decipher.final()]).toString('utf8');
      }
      return JSON.parse(data);
    } catch (error) {
      if (error.code === 'ENOENT') return fallback;
      throw new Error('protected_storage_unavailable');
    }
  }
  async write(name, value) {
    await mkdir(this.directory, { recursive: true, mode: 0o700 });
    let data = JSON.stringify(value);
    if (process.platform === 'win32') data = await dpapi(data, false);
    else {
      const iv = randomBytes(12), cipher = createCipheriv('aes-256-gcm', await this.key(), iv);
      cipher.setAAD(Buffer.from(name));
      const ciphertext = Buffer.concat([cipher.update(data, 'utf8'), cipher.final()]);
      data = JSON.stringify({ version: 1, iv: iv.toString('base64'), tag: cipher.getAuthTag().toString('base64'), ciphertext: ciphertext.toString('base64') });
    }
    const target = join(this.directory, `${name}.private`);
    const temporary = `${target}.${randomUUID()}.tmp`;
    await writeFile(temporary, data, { mode: 0o600, flag: 'wx' });
    await rename(temporary, target);
    if (process.platform !== 'win32') await chmod(target, 0o600);
  }
}
