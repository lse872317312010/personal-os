#!/usr/bin/env python3
"""Build a credential-free deployment directory from pinned Web and committed source."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import tarfile
import tempfile
import zipfile

WEB_SHA256 = 'f0144a03c356998c8a2acde6cd84aa36393f0a3cebdc033ad0de4392e9d3c1bd'
BASE_SHA256 = {
    'b3ec6969b06c3c4e7b7ddf2aeabcb7458ae24c531f3ac2981b947c500ac242ed',
    'a37d6978389396e91e3a34316059fa41ce29d66f69478b938567fd48a7265e74',
    '1a161b7240f3ab71c39a585ef7566e2bccabcd2e470ae69d0ca05a71dbefbc15',
    '7c774de4b89c9287017f081373eaf6e514e033e5495ba876858ee6173e6660d6',
    '219ddb6fbeac362a9236b17848fb3c5edbfbbe20f2a7376d3082ef55d5f0cb4f',
}
RUNTIME = ['server.mjs', 'chatgpt-auth.mjs', 'connections.mjs', 'providers.mjs',
           'codex-cli.mjs', 'diagnostics.mjs', 'acceptance.mjs', 'protected-store.mjs', 'package.json']
DEPLOYMENT = ['Dockerfile', 'compose.yaml', 'install-docker-ubuntu.sh', 'backup-data.sh', 'restore-data.sh', 'validate-backup.py', 'personal-os.sh']
DOCS = {'README.md': 'docs/ORACLE_ALWAYS_FREE_EXPERIMENT.md',
        'START_HERE.md': 'docs/ORACLE_ALWAYS_FREE_START_HERE.md'}
REQUIRED_WEB = {'index.html', 'flutter_bootstrap.js', 'main.dart.js', 'fonts/NotoSansSC.ttf'}


def digest(path: Path) -> str:
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def safe_path(name: str) -> PurePosixPath:
    path = PurePosixPath(name)
    if path.is_absolute() or '..' in path.parts or not path.parts or '\\' in name:
        raise ValueError('Unsafe archive member')
    return path


def web_files(archive: Path, base_bundle: bool) -> dict[str, bytes]:
    sha = digest(archive)
    if sha not in (BASE_SHA256 if base_bundle else {WEB_SHA256}):
        raise ValueError('Archive SHA-256 does not match a pinned input')
    files = {}
    if base_bundle:
        with tarfile.open(archive, 'r:gz') as bundle:
            for member in bundle:
                path = safe_path(member.name)
                if not (member.isfile() or member.isdir()):
                    raise ValueError('Links and special files are not allowed')
                if member.isfile() and path.parts[:2] == ('personal-os-oracle-experiment', 'web'):
                    name = str(PurePosixPath(*path.parts[2:]))
                    if name == '.' or name in files:
                        raise ValueError('Duplicate or invalid Web file')
                    files[name] = bundle.extractfile(member).read()
    else:
        with zipfile.ZipFile(archive) as bundle:
            for member in bundle.infolist():
                path = safe_path(member.filename)
                if (member.external_attr >> 16) & 0o170000 == 0o120000:
                    raise ValueError('Links are not allowed')
                if not member.is_dir():
                    name = str(path)
                    if name in files:
                        raise ValueError('Duplicate Web file')
                    files[name] = bundle.read(member)
    if not REQUIRED_WEB.issubset(files):
        raise ValueError('Required Web entry, script or font is missing')
    return files


def committed_file(root: Path, commit: str, path: str) -> bytes:
    return subprocess.check_output(['git', '-C', str(root), 'show', f'{commit}:{path}'], stderr=subprocess.DEVNULL)


def prepare(archive: Path, output: Path, commit: str, *, base_bundle: bool = False, root: Path | None = None) -> None:
    if not re.fullmatch(r'[0-9a-f]{40}', commit):
        raise ValueError('--gateway-source must be a full 40-character commit SHA')
    root = root or Path(__file__).resolve().parents[2]
    kind = subprocess.check_output(['git', '-C', str(root), 'cat-file', '-t', commit], stderr=subprocess.DEVNULL).decode().strip()
    if kind != 'commit':
        raise ValueError('Gateway source must identify a commit')
    if output.exists() or output.is_symlink():
        raise ValueError('Output directory already exists')
    web = web_files(archive, base_bundle)
    # Read the complete allowlist before creating any output. Never package a
    # dirty working tree, arbitrary profile directories, keys or CLI auth.
    sources = {f'gateway/{name}': committed_file(root, commit, f'services/agent_gateway/{name}') for name in RUNTIME}
    sources.update({name: committed_file(root, commit, f'tool/oracle/{name}') for name in DEPLOYMENT})
    sources.update({name: committed_file(root, commit, path) for name, path in DOCS.items()})
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix='.personal-os-build-', dir=output.parent))
    try:
        for name, content in {**sources, **{f'web/{name}': value for name, value in web.items()}}.items():
            target = temporary / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
            target.chmod(0o755 if name.endswith('.sh') else 0o644)
        manifest = {
            'source_commit_remote': '19cacaefa32cbaf033cc3b5e4341f425e03eb4cb',
            'source_tree': 'a02653aa252a5cc70505c47ae08518d918d74a70',
            'web_artifact_sha256': WEB_SHA256,
            'web_workflow_run': 37745226802,
            'gateway_source_commit': commit,
            'codex_cli_version': '0.162.1',
            'scope': 'private loopback gateway via SSH; ChatGPT-login Codex CLI; cloud/inference validation pending',
        }
        (temporary / 'candidate.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
        entries = [f'{digest(path)}  {path.relative_to(temporary).as_posix()}' for path in sorted(temporary.rglob('*')) if path.is_file()]
        (temporary / 'SHA256SUMS').write_text('\n'.join(entries) + '\n', encoding='utf-8')
        # Do not replace an existing destination, including an empty directory
        # that another process created while we prepared the candidate.
        output.mkdir()
        try:
            for path in temporary.iterdir():
                path.rename(output / path.name)
        except BaseException:
            shutil.rmtree(output)
            raise
    finally:
        shutil.rmtree(temporary, ignore_errors=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--gateway-source', required=True)
    parser.add_argument('--base-bundle', action='store_true')
    args = parser.parse_args()
    try:
        prepare(args.archive, args.output, args.gateway_source, base_bundle=args.base_bundle)
    except (OSError, ValueError, subprocess.CalledProcessError, tarfile.TarError, zipfile.BadZipFile) as error:
        parser.exit(2, f'Cannot prepare deployment: {type(error).__name__}. No credentials are included.\n')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
