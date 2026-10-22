#!/usr/bin/env bash
# Run as the SSH user: bash backup-data.sh /absolute/new-backup.tar.gz
set -Eeuo pipefail
target=${1:?Provide a new absolute backup filename}
[[ "$target" == /* && ! -e "$target" && ! -L "$target" ]] || { echo 'Use a new absolute filename.' >&2; exit 1; }
umask 077
mkdir -p -- "$(dirname -- "$target")"
docker_cmd=(docker)
docker info >/dev/null 2>&1 || docker_cmd=(sudo docker)
container=$("${docker_cmd[@]}" compose ps -a -q gateway)
[[ -n "$container" ]] || { echo 'Create the gateway container first.' >&2; exit 1; }
image=$("${docker_cmd[@]}" inspect --format '{{.Image}}' "$container")
history=$("${docker_cmd[@]}" inspect --format '{{range .Mounts}}{{if eq .Destination "/var/lib/personal-os"}}{{.Name}}{{end}}{{end}}' "$container")
auth=$("${docker_cmd[@]}" inspect --format '{{range .Mounts}}{{if eq .Destination "/home/node/.codex"}}{{.Name}}{{end}}{{end}}' "$container")
[[ -n "$history" && -n "$auth" ]] || { echo 'Both persistent volumes are required.' >&2; exit 1; }
running=$("${docker_cmd[@]}" inspect --format '{{.State.Running}}' "$container")
temporary=$(mktemp "${target}.partial.XXXXXX")
cleanup() {
  rm -f -- "$temporary"
  if [[ "$running" == true ]]; then "${docker_cmd[@]}" start "$container" >/dev/null; fi
}
trap cleanup EXIT
# Freeze writes while capturing the installation key, history and CLI auth.
if [[ "$running" == true ]]; then "${docker_cmd[@]}" stop --time 30 "$container" >/dev/null; fi
"${docker_cmd[@]}" run --rm --network none --read-only --user 0:0 \
  --mount "type=volume,src=$history,dst=/backup/history,readonly" \
  --mount "type=volume,src=$auth,dst=/backup/codex-auth,readonly" \
  --entrypoint tar "$image" -czf - --exclude=history/runtime.lock -C /backup history codex-auth > "$temporary"
tar -tzf "$temporary" >/dev/null
# A hard link refuses to overwrite a file created since the initial check.
ln -- "$temporary" "$target"
echo "Private backup saved: $target"
