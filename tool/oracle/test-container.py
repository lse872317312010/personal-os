#!/usr/bin/env python3
"""Test real Docker deployment/recovery with disposable synthetic data and no AI requests."""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tarfile
import tempfile
import time
import urllib.error
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('prepare', Path(__file__).with_name('prepare-experiment.py'))
prepare = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(prepare)
ORIGIN = 'http://127.0.0.1:8787'


class ContainerTest:
    def __init__(self, directory: Path, expected_arch: str):
        self.directory = directory
        self.context = directory / 'context'
        self.expected_arch = expected_arch
        suffix = uuid.uuid4().hex[:12]
        self.project = 'pos-container-test-' + suffix
        self.recovery = self.project + '-recovery'
        self.steps = []

    def run(self, args, *, project=None, expected=0, timeout=120, stream=False):
        env = dict(os.environ, COMPOSE_PROJECT_NAME=project or self.project)
        result = subprocess.run(args, cwd=self.context, env=env, text=True, capture_output=not stream, timeout=timeout)
        if result.returncode != expected:
            raise RuntimeError(f'Command {args[0]} failed with exit {result.returncode}; expected {expected}')
        return result.stdout or ''

    def compose(self, *args, project=None, **kwargs):
        return self.run(['docker', 'compose', *args], project=project, **kwargs)

    def execute(self, *args, project=None, **kwargs):
        return self.compose('exec', '-T', 'gateway', *args, project=project, **kwargs)

    def inspect(self, project=None):
        container = self.compose('ps', '-a', '-q', 'gateway', project=project).strip()
        if not container:
            raise RuntimeError('Gateway container is missing')
        return json.loads(self.run(['docker', 'inspect', container]))[0]

    def passed(self, name):
        self.steps.append(name)
        print('PASS: ' + name, flush=True)

    def request(self, path, data=None, csrf=None):
        headers = {'X-Personal-OS': '1'}
        if data is not None:
            headers.update({'Content-Type': 'application/json', 'X-Personal-OS-CSRF': csrf or ''})
        request = urllib.request.Request(ORIGIN + path, headers=headers, data=None if data is None else json.dumps(data).encode())
        with urllib.request.urlopen(request, timeout=5) as response:
            return json.load(response)

    def ready(self, project=None):
        for _ in range(60):
            state = self.inspect(project)['State']
            if state.get('Health', {}).get('Status') == 'healthy':
                assert self.request('/api/health') == {'ok': True}
                return
            time.sleep(1)
        raise RuntimeError('Gateway did not become healthy')

    def prepare_context(self):
        self.context.mkdir()
        (self.context / 'gateway').mkdir()
        for name in prepare.RUNTIME:
            shutil.copyfile(ROOT / 'services/agent_gateway' / name, self.context / 'gateway' / name)
        for name in prepare.DEPLOYMENT:
            shutil.copyfile(ROOT / 'tool/oracle' / name, self.context / name)
        # Fixture bytes only: this tests packaging paths and container runtime,
        # not Flutter rendering, the CI Web artifact or a real personal profile.
        for name in prepare.REQUIRED_WEB:
            path = self.context / 'web' / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('container-test-fixture:' + name)

    def test(self):
        # Refuse to disturb any existing gateway, even on a developer machine.
        with socket.socket() as probe:
            probe.bind(('127.0.0.1', 8787))
        self.prepare_context()
        try:
            self.compose('config', '--quiet')
            self.compose('build', 'gateway', timeout=600, stream=True)
            self.compose('up', '-d', '--wait', '--wait-timeout', '90', timeout=120)
            self.ready()
            self.passed('image build and unauthenticated healthy startup')

            info = self.inspect()
            assert info['Config']['User'] == 'node'
            host = info['HostConfig']
            assert host['ReadonlyRootfs'] is True and host['NetworkMode'] == 'host'
            assert 'ALL' in host['CapDrop']
            assert any(value.startswith('no-new-privileges') for value in host['SecurityOpt'])
            assert 'noexec' in host['Tmpfs']['/tmp'] and 'nosuid' in host['Tmpfs']['/tmp']
            assert not host.get('PortBindings')
            arch = self.execute('node', '-p', 'process.arch').strip()
            assert arch == self.expected_arch, f'Expected {self.expected_arch}, got {arch}'
            assert self.execute('codex', '--version').strip() == 'codex-cli 0.162.1'
            help_text = self.execute('codex', 'exec', '--help')
            for option in ['--json', '--ephemeral', '--ignore-user-config', '--ignore-rules', '--output-schema']:
                assert option in help_text, option
            features = self.execute('codex', 'features', 'list')
            for name in ['shell_tool', 'unified_exec', 'code_mode_host', 'apps', 'plugins', 'hooks', 'multi_agent', 'browser_use', 'computer_use', 'view_image', 'skill_search', 'workspace_dependencies', 'daemon_auto_start']:
                assert any(line.split() and line.split()[0] == name for line in features.splitlines()), name
            self.passed('native architecture, pinned CLI and command compatibility')

            self.execute('node', '-e', "const fs=require('node:fs');for(const p of ['/var/lib/personal-os','/home/node/.codex'])if((fs.statSync(p).mode&511)!==448)process.exit(1);try{fs.writeFileSync('/opt/personal-os/readonly-probe','x');process.exit(1)}catch(e){if(!['EROFS','EACCES'].includes(e.code))process.exit(1)}fs.writeFileSync('/tmp/writable-probe','fixture');fs.unlinkSync('/tmp/writable-probe')")
            status = self.request('/api/agent/status')
            assert status['provider'] == 'codex-cli' and status['connected'] is False
            report = json.loads(self.execute('node', 'diagnostics.mjs', expected=2))
            assert [item['check'] for item in report['checks'] if not item['ok']] == ['chatgpt_login']
            assert report['inference_tested'] is False
            report = json.loads(self.execute('node', 'acceptance.mjs', expected=2))
            assert report['inference_attempted'] is False and report['code'] == 'not_requested'
            self.passed('read-only runtime, private writable volumes and no inference by default')

            event = {'event_id': 'container-test-synthetic-event', 'sensitivity': 'd1', 'goal': 'Synthetic recovery fixture only'}
            self.request('/api/history', {'revision': 0, 'events': [event]}, status['csrf'])
            assert self.request('/api/history') == {'revision': 1, 'events': [event]}
            self.execute('node', '-e', "const fs=require('node:fs');if(fs.readFileSync('/var/lib/personal-os/history.private','utf8').includes('Synthetic recovery fixture'))process.exit(1);fs.writeFileSync('/home/node/.codex/backup-fixture.txt','synthetic-auth-volume-fixture',{mode:384})")
            self.compose('kill', '--signal', 'SIGKILL', 'gateway')
            self.compose('up', '-d', '--wait', '--wait-timeout', '90')
            self.ready()
            assert self.request('/api/history') == {'revision': 1, 'events': [event]}
            self.passed('encrypted history survives abrupt stop and PID reuse')

            archive = self.directory / 'synthetic-private-backup.tar.gz'
            self.run(['bash', 'backup-data.sh', str(archive)])
            self.ready()
            assert archive.stat().st_mode & 0o777 == 0o600
            with tarfile.open(archive) as bundle:
                names = set(bundle.getnames())
                assert 'history/history.private' in names
                assert 'history/installation-key.private' in names
                assert 'codex-auth/backup-fixture.txt' in names
                assert 'history/runtime.lock' not in names
            self.passed('real stopped-write backup captures both volumes and resumes service')

            self.compose('stop', 'gateway')
            # A second project guarantees empty, separately named volumes.
            self.compose('build', 'gateway', project=self.recovery, timeout=600)
            self.run(['bash', 'restore-data.sh', str(archive)], project=self.recovery)
            assert self.inspect(self.recovery)['State']['Running'] is False
            self.compose('up', '-d', '--wait', '--wait-timeout', '90', project=self.recovery)
            self.ready(self.recovery)
            assert self.request('/api/history') == {'revision': 1, 'events': [event]}
            assert self.execute('cat', '/home/node/.codex/backup-fixture.txt', project=self.recovery).strip() == 'synthetic-auth-volume-fixture'
            self.passed('real restore decrypts history and restores the independent auth volume')

            before = self.inspect(self.recovery)['Id']
            self.run(['bash', 'restore-data.sh', str(archive)], project=self.recovery, expected=1)
            assert self.inspect(self.recovery)['Id'] == before
            assert self.inspect(self.recovery)['State']['Running'] is True
            self.compose('stop', 'gateway', project=self.recovery)
            self.run(['bash', 'restore-data.sh', str(archive)], project=self.recovery, expected=1)
            self.compose('up', '-d', '--wait', '--wait-timeout', '90', project=self.recovery)
            assert self.request('/api/history') == {'revision': 1, 'events': [event]}
            self.passed('restore refuses a running service and nonempty destination without data loss')
            print(json.dumps({'container_checks': len(self.steps), 'architecture': arch, 'real_inference_tested': False, 'oci_tested': False}), flush=True)
        finally:
            # These projects and volumes contain only this run's fixtures.
            # Never run down -v against the user's deployment project.
            for project in [self.recovery, self.project]:
                try:
                    self.compose('down', '--volumes', '--remove-orphans', project=project)
                except (RuntimeError, subprocess.SubprocessError):
                    print('Fixture cleanup failed for ' + project, flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run-docker-tests', action='store_true')
    parser.add_argument('--expected-arch', choices=['arm64', 'x64'], required=True)
    args = parser.parse_args()
    if not args.run_docker_tests:
        parser.error('Explicit --run-docker-tests required; creates disposable fixture containers')
    with tempfile.TemporaryDirectory(prefix='personal-os-container-') as temporary:
        ContainerTest(Path(temporary), args.expected_arch).test()


if __name__ == '__main__':
    main()
