#!/usr/bin/env bash
# Only restore into empty volumes. Existing user data is never replaced.
set -Eeuo pipefail
archive=${1:?Provide an absolute backup filename}
[[ "$archive" == /* && -f "$archive" ]] || { echo 'Provide an existing absolute file.' >&2; exit 1; }
python3 - "$archive" <<'PY'
import sys, tarfile
from pathlib import PurePosixPath
with tarfile.open(sys.argv[1], 'r:gz') as bundle:
    roots = set()
    for item in bundle:
        path = PurePosixPath(item.name)
        if (path.is_absolute() or '..' in path.parts or not path.parts
            or path.parts[0] not in {'history', 'codex-auth'}
            or not (item.isfile() or item.isdir())
            or path == PurePosixPath('history/runtime.lock')):
            raise SystemExit('Unsafe backup; nothing restored')
        roots.add(path.parts[0])
    if roots != {'history', 'codex-auth'}:
        raise SystemExit('Incomplete backup; nothing restored')
PY
docker_cmd=(docker)
docker info >/dev/null 2>&1 || docker_cmd=(sudo docker)
container=$("${docker_cmd[@]}" compose ps -a -q gateway)
if [[ -n "$container" ]]; then
  [[ $("${docker_cmd[@]}" inspect --format '{{.State.Running}}' "$container") == false ]] || { echo 'Stop the gateway before restore; nothing changed.' >&2; exit 1; }
else
  "${docker_cmd[@]}" compose create gateway >/dev/null
  container=$("${docker_cmd[@]}" compose ps -a -q gateway)
fi
[[ $("${docker_cmd[@]}" inspect --format '{{.State.Running}}' "$container") == false ]] || { echo 'Stop the gateway before restore.' >&2; exit 1; }
image=$("${docker_cmd[@]}" inspect --format '{{.Image}}' "$container")
history=$("${docker_cmd[@]}" inspect --format '{{range .Mounts}}{{if eq .Destination "/var/lib/personal-os"}}{{.Name}}{{end}}{{end}}' "$container")
auth=$("${docker_cmd[@]}" inspect --format '{{range .Mounts}}{{if eq .Destination "/home/node/.codex"}}{{.Name}}{{end}}{{end}}' "$container")
[[ -n "$history" && -n "$auth" ]] || { echo 'Both persistent volumes are required.' >&2; exit 1; }
"${docker_cmd[@]}" run --rm -i --network none --read-only --user 0:0 \
  --mount "type=volume,src=$history,dst=/restore/history" \
  --mount "type=volume,src=$auth,dst=/restore/codex-auth" \
  --entrypoint sh "$image" -ec \
  'test -z "$(ls -A /restore/history)" && test -z "$(ls -A /restore/codex-auth)" || { echo "Volumes are not empty; nothing restored" >&2; exit 1; }; tar -xzf - -C /restore; chown -R node:node /restore/history /restore/codex-auth; chmod 700 /restore/history /restore/codex-auth' < "$archive"
echo 'Restored into empty volumes. Start with: sudo docker compose up -d'
