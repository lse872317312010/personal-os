#!/usr/bin/env python3
"""Exercise deployment controls without Docker, credentials or inference."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import tarfile
import unittest


class ControlsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bundle = self.root / 'bundle with spaces'
        self.bundle.mkdir()
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.trace = self.root / 'calls.jsonl'
        self.script = self.bundle / 'personal-os.sh'
        shutil.copyfile(Path(__file__).with_name('personal-os.sh'), self.script)
        (self.bundle / 'compose.yaml').write_text('services: {}\n')
        self.manifest()
        docker = self.bin / 'docker'
        docker.write_text('#!/usr/bin/env python3\n' + '''import json,os,sys
with open(os.environ['TEST_DOCKER_TRACE'],'a') as f:f.write(json.dumps(sys.argv[1:])+'\\n')
if 'diagnostics.mjs' in sys.argv:sys.exit(2)
sys.exit(0)
''')
        docker.chmod(0o700)
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'], TEST_DOCKER_TRACE=str(self.trace), COMPOSE_FILE='/unrelated/compose.yaml')

    def manifest(self):
        (self.bundle / 'SHA256SUMS').write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n' for p in [self.script, self.bundle / 'compose.yaml']))

    def run_control(self, *args):
        return subprocess.run(['bash', str(self.script), *args], cwd=self.root, env=self.env, text=True, capture_output=True)

    def calls(self):
        return [json.loads(line) for line in self.trace.read_text().splitlines()] if self.trace.exists() else []

    def test_help_and_invalid_commands_never_contact_docker(self):
        self.assertEqual(self.run_control().returncode, 0)
        self.assertEqual(self.run_control('unknown').returncode, 2)
        self.assertEqual(self.run_control('stop', '--volumes').returncode, 2)
        self.assertEqual(self.calls(), [])

    def test_start_verifies_bytes_and_pins_compose_from_another_directory(self):
        self.assertEqual(self.run_control('start').returncode, 0)
        calls = self.calls()
        self.assertEqual(calls[0], ['info'])
        for call in calls[1:]:
            self.assertEqual(call[:5], ['compose', '--project-directory', str(self.bundle), '-f', str(self.bundle / 'compose.yaml')])
        self.assertEqual(calls[-1][5:], ['up', '--build', '-d', '--force-recreate', '--wait', '--wait-timeout', '90'])
        self.assertFalse(any('acceptance.mjs' in call or 'login' in call for call in calls))

    def test_corrupt_or_missing_manifest_stops_before_docker(self):
        (self.bundle / 'compose.yaml').write_text('changed')
        self.assertEqual(self.run_control('start').returncode, 2)
        self.assertEqual(self.calls(), [])
        (self.bundle / 'SHA256SUMS').unlink()
        self.assertEqual(self.run_control('start').returncode, 2)
        self.assertEqual(self.calls(), [])

    def test_status_preserves_not_ready_exit_code_and_never_infers(self):
        self.assertEqual(self.run_control('status').returncode, 2)
        self.assertEqual(self.calls()[-1][-5:], ['exec', '-T', 'gateway', 'node', 'diagnostics.mjs'])
        self.assertFalse(any('acceptance.mjs' in call for call in self.calls()))

    def test_only_explicit_test_ai_routes_to_one_inference(self):
        self.assertEqual(self.run_control('test-ai').returncode, 0)
        calls = self.calls()
        self.assertEqual(len(calls), 2)
        self.assertEqual(calls[-1][-6:], ['exec', '-T', 'gateway', 'node', 'acceptance.mjs', '--run-inference'])

    def test_stop_keeps_volumes_and_login_rejects_a_noninteractive_pipe(self):
        self.assertEqual(self.run_control('stop').returncode, 0)
        self.assertEqual(self.calls()[-1][-2:], ['stop', 'gateway'])
        before = self.calls()
        self.assertEqual(self.run_control('login').returncode, 2)
        self.assertEqual(self.calls(), before)

    def backup_scripts(self):
        for name in ['backup-data.sh', 'restore-data.sh', 'validate-backup.py']:
            shutil.copyfile(Path(__file__).with_name(name), self.bundle / name)
        archive = self.root / 'fixture.tar.gz'
        with tarfile.open(archive, 'w:gz') as bundle:
            for name in ['history', 'codex-auth']:
                info = tarfile.TarInfo(name)
                info.type = tarfile.DIRTYPE
                bundle.addfile(info)
        return archive

    def test_backup_restore_pin_their_deployment_before_container_lookup(self):
        archive = self.backup_scripts()
        for name, target, message in [
            ('backup-data.sh', self.root / 'new-backup.tar.gz', 'Create the gateway container first'),
            ('restore-data.sh', archive, 'Stop the gateway before restore'),
        ]:
            with self.subTest(script=name):
                self.trace.unlink(missing_ok=True)
                result = subprocess.run(['bash', str(self.bundle / name), str(target)], cwd=self.root, env=self.env, text=True, capture_output=True)
                # The Docker fixture has no real container. Verify safe routing
                # and refusal here; native CI covers successful data transfer.
                self.assertEqual(result.returncode, 1)
                self.assertIn(message, result.stderr)
                compose_calls = [call for call in self.calls() if call[0] == 'compose']
                self.assertTrue(compose_calls)
                for call in compose_calls:
                    self.assertEqual(call[:5], ['compose', '--project-directory', str(self.bundle), '-f', str(self.bundle / 'compose.yaml')])
                self.assertFalse(any(call[0] == 'run' for call in self.calls()))

    def test_backup_restore_missing_deployment_never_contact_docker(self):
        archive = self.backup_scripts()
        (self.bundle / 'compose.yaml').unlink()
        for name, target in [('backup-data.sh', self.root / 'new.tar.gz'), ('restore-data.sh', archive)]:
            result = subprocess.run(['bash', str(self.bundle / name), str(target)], cwd=self.root, env=self.env, text=True, capture_output=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn('Missing deployment compose.yaml', result.stderr)
        self.assertEqual(self.calls(), [])


if __name__ == '__main__':
    unittest.main()
