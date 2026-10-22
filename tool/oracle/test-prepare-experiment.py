#!/usr/bin/env python3
"""Exercise packaging with isolated Git commits and synthetic archives, no network."""
import hashlib
import importlib.util
import io
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import zipfile

SPEC = importlib.util.spec_from_file_location('prepare', Path(__file__).with_name('prepare-experiment.py'))
prepare = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(prepare)


class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.repo = self.root / 'repo'
        self.repo.mkdir()
        self.git('init', '-q')
        self.git('config', 'user.email', 'fixture@example.invalid')
        self.git('config', 'user.name', 'Fixture')
        paths = ([f'services/agent_gateway/{name}' for name in prepare.RUNTIME]
                 + [f'tool/oracle/{name}' for name in prepare.DEPLOYMENT]
                 + list(prepare.DOCS.values()))
        for path in paths:
            target = self.repo / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text('committed:' + path, encoding='utf-8')
        (self.repo / 'auth.json').write_text('must-never-package-credentials')
        self.git('add', '.')
        self.git('commit', '-qm', 'Fixture')
        self.commit = self.git('rev-parse', 'HEAD').strip()
        self.archive = self.root / 'web.zip'
        self.output = self.root / 'output'

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.repo), *args], stderr=subprocess.DEVNULL).decode()

    def zip(self, extra=None):
        with zipfile.ZipFile(self.archive, 'w') as bundle:
            for name in prepare.REQUIRED_WEB:
                bundle.writestr(name, 'web:' + name)
            if extra:
                bundle.writestr(*extra)
        return hashlib.sha256(self.archive.read_bytes()).hexdigest()

    def build(self, **kwargs):
        prepare.prepare(self.archive, self.output, self.commit, root=self.repo, **kwargs)

    def test_only_committed_allowlist_is_packaged_and_checksums_match(self):
        sha = self.zip()
        (self.repo / 'services/agent_gateway/server.mjs').write_text('dirty-private-change')
        with patch.object(prepare, 'WEB_SHA256', sha):
            self.build()
        self.assertEqual((self.output / 'gateway/server.mjs').read_text(), 'committed:services/agent_gateway/server.mjs')
        self.assertFalse((self.output / 'auth.json').exists())
        for line in (self.output / 'SHA256SUMS').read_text().splitlines():
            expected, name = line.split('  ', 1)
            self.assertEqual(prepare.digest(self.output / name), expected)
        self.assertFalse(list(self.root.glob('.personal-os-build-*')))

    def test_wrong_archive_hash_leaves_no_output(self):
        self.zip()
        with self.assertRaises(ValueError):
            self.build()
        self.assertFalse(self.output.exists())

    def test_zip_traversal_and_links_are_rejected(self):
        for extra in [('../outside', 'bad'), ('/absolute', 'bad')]:
            with patch.object(prepare, 'WEB_SHA256', self.zip(extra)):
                with self.assertRaises(ValueError):
                    self.build()
            self.assertFalse(self.output.exists())
        link = zipfile.ZipInfo('link')
        link.create_system = 3
        link.external_attr = 0o120777 << 16
        with patch.object(prepare, 'WEB_SHA256', self.zip((link, 'outside'))):
            with self.assertRaises(ValueError):
                self.build()
        self.assertFalse(self.output.exists())

    def test_existing_directory_and_symlink_are_never_overwritten(self):
        sha = self.zip()
        self.output.mkdir()
        marker = self.output / 'existing'
        marker.write_text('keep')
        with patch.object(prepare, 'WEB_SHA256', sha):
            with self.assertRaises(ValueError):
                self.build()
        self.assertEqual(marker.read_text(), 'keep')
        marker.unlink()
        self.output.rmdir()
        self.output.symlink_to(self.repo)
        with self.assertRaises(ValueError):
            self.build()
        self.assertTrue(self.output.is_symlink())

    def test_pinned_base_bundle_only_reuses_web_and_rejects_link(self):
        self.archive = self.root / 'base.tar.gz'
        def create(link=False):
            with tarfile.open(self.archive, 'w:gz') as bundle:
                for name in [*('web/' + name for name in prepare.REQUIRED_WEB), 'gateway/server.mjs', 'auth.json']:
                    data = ('old:' + name).encode()
                    info = tarfile.TarInfo('personal-os-oracle-experiment/' + name)
                    info.size = len(data)
                    bundle.addfile(info, io.BytesIO(data))
                if link:
                    info = tarfile.TarInfo('personal-os-oracle-experiment/web/link')
                    info.type = tarfile.SYMTYPE
                    info.linkname = '../../private'
                    bundle.addfile(info)
            return prepare.digest(self.archive)
        with patch.object(prepare, 'BASE_SHA256', {create()}):
            self.build(base_bundle=True)
        self.assertFalse((self.output / 'auth.json').exists())
        self.assertEqual((self.output / 'gateway/server.mjs').read_text(), 'committed:services/agent_gateway/server.mjs')
        import shutil
        shutil.rmtree(self.output)
        with patch.object(prepare, 'BASE_SHA256', {create(link=True)}):
            with self.assertRaises(ValueError):
                self.build(base_bundle=True)
        self.assertFalse(self.output.exists())

    def test_missing_committed_source_leaves_no_output(self):
        sha = self.zip()
        self.git('rm', '-q', 'services/agent_gateway/acceptance.mjs')
        self.git('commit', '-qm', 'Missing runtime')
        self.commit = self.git('rev-parse', 'HEAD').strip()
        with patch.object(prepare, 'WEB_SHA256', sha):
            with self.assertRaises(subprocess.CalledProcessError):
                self.build()
        self.assertFalse(self.output.exists())


if __name__ == '__main__':
    unittest.main()
