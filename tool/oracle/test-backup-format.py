#!/usr/bin/env python3
import importlib.util
import io
from pathlib import Path
import tarfile
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location('backup_format', Path(__file__).with_name('validate-backup.py'))
backup_format = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(backup_format)


class BackupFormatTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.archive = Path(self.temporary.name) / 'backup.tar.gz'

    def create(self, extra=(), roots=True):
        with tarfile.open(self.archive, 'w:gz') as bundle:
            if roots:
                for name in ['history', 'codex-auth']:
                    info = tarfile.TarInfo(name)
                    info.type = tarfile.DIRTYPE
                    bundle.addfile(info)
            for name, kind in extra:
                info = tarfile.TarInfo(name)
                info.type = kind
                if kind in [tarfile.SYMTYPE, tarfile.LNKTYPE]:
                    info.linkname = '/outside'
                if kind == tarfile.REGTYPE:
                    info.size = 7
                    bundle.addfile(info, io.BytesIO(b'fixture'))
                else:
                    bundle.addfile(info)

    def test_history_key_and_auth_files_are_valid_without_extraction(self):
        self.create([('history/history.private', tarfile.REGTYPE), ('history/installation-key.private', tarfile.REGTYPE), ('codex-auth/auth.json', tarfile.REGTYPE)])
        backup_format.validate(self.archive)
        self.assertEqual([p.name for p in self.archive.parent.iterdir()], ['backup.tar.gz'])

    def test_symlinks_hardlinks_and_special_files_are_rejected(self):
        for kind in [tarfile.SYMTYPE, tarfile.LNKTYPE, tarfile.FIFOTYPE, tarfile.CHRTYPE]:
            with self.subTest(kind=kind):
                self.create([('codex-auth/unsafe', kind)])
                with self.assertRaises(ValueError):
                    backup_format.validate(self.archive)

    def test_traversal_absolute_paths_and_normalized_locks_are_rejected(self):
        for name in ['/outside', 'history/../outside', '../outside', 'other/file', 'history/runtime.lock', 'history/./runtime.lock']:
            with self.subTest(name=name):
                self.create([(name, tarfile.REGTYPE)])
                with self.assertRaises(ValueError):
                    backup_format.validate(self.archive)

    def test_missing_volume_and_file_at_volume_root_are_rejected(self):
        for members in [[('history', tarfile.DIRTYPE)], [('history', tarfile.REGTYPE), ('codex-auth', tarfile.DIRTYPE)]]:
            self.create(members, roots=False)
            with self.assertRaises(ValueError):
                backup_format.validate(self.archive)

    def test_duplicate_normalized_file_paths_are_rejected(self):
        self.create([('history/data', tarfile.REGTYPE), ('history/./data', tarfile.REGTYPE)])
        with self.assertRaises(ValueError):
            backup_format.validate(self.archive)


if __name__ == '__main__':
    unittest.main()
