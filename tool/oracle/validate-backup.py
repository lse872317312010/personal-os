#!/usr/bin/env python3
"""Validate the non-link, two-volume backup format without extracting files."""
from pathlib import PurePosixPath
import sys
import tarfile


def validate(archive):
    roots = set()
    files = set()
    with tarfile.open(archive, 'r:gz') as bundle:
        for item in bundle:
            path = PurePosixPath(item.name)
            if (path.is_absolute() or '..' in path.parts or not path.parts
                or path.parts[0] not in {'history', 'codex-auth'}
                or not (item.isfile() or item.isdir())
                or path == PurePosixPath('history/runtime.lock')
                or (len(path.parts) == 1 and not item.isdir())):
                raise ValueError('Unsafe backup; nothing restored')
            if item.isfile():
                if path in files:
                    raise ValueError('Duplicate backup file; nothing restored')
                files.add(path)
            roots.add(path.parts[0])
    if roots != {'history', 'codex-auth'}:
        raise ValueError('Incomplete backup; nothing restored')


if __name__ == '__main__':
    try:
        if len(sys.argv) != 2:
            raise ValueError('Provide a backup archive')
        validate(sys.argv[1])
    except (ValueError, OSError, tarfile.TarError):
        # Do not echo archive contents, paths or errors that may contain secrets.
        raise SystemExit('Backup validation failed: expected regular files in history and codex-auth; no links, traversal, duplicate files or runtime lock')
