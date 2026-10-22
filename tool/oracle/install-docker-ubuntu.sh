#!/usr/bin/env bash
# New Ubuntu VM only. Uses Docker's official apt repository.
set -Eeuo pipefail

if (( EUID != 0 )); then
  echo 'Run with: sudo bash install-docker-ubuntu.sh' >&2
  exit 1
fi
. /etc/os-release
if [[ "${ID:-}" != ubuntu ]]; then
  echo 'This installer requires an Ubuntu image, not Oracle Linux.' >&2
  exit 1
fi
case "${VERSION_ID:-}" in
  22.04|24.04|26.04) ;;
  *) echo 'Use a supported Ubuntu LTS image (22.04, 24.04 or 26.04).' >&2; exit 1 ;;
esac
oracle_arch="$(dpkg --print-architecture)"
case "$oracle_arch" in
  arm64|amd64) ;;
  *) echo 'Use a 64-bit Arm or x86 Ubuntu image.' >&2; exit 1 ;;
esac

if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1 && docker compose version; then
    echo 'Existing Docker and Compose are ready; no changes made.'
    exit 0
  fi
  echo 'Docker already exists but is not ready. Inspect it before reinstalling.' >&2
  exit 1
fi
for package in docker.io docker-compose docker-compose-v2 podman-docker containerd runc; do
  if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q 'install ok installed'; then
    echo "Existing container package $package found; not removing it automatically." >&2
    exit 1
  fi
done

oracle_suite="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
if [[ -z "$oracle_suite" ]]; then
  echo 'Cannot identify the Ubuntu repository suite.' >&2
  exit 1
fi
if grep -Rqs 'download.docker.com/linux/ubuntu' /etc/apt/sources.list /etc/apt/sources.list.d; then
  echo 'A Docker apt source already exists; inspect it before installing.' >&2
  exit 1
fi

apt-get update
apt-get install -y ca-certificates curl
install -d -m 0755 /etc/apt/keyrings
curl --fail --silent --show-error --location \
  https://download.docker.com/linux/ubuntu/gpg \
  --output /etc/apt/keyrings/personal-os-docker.asc
chmod 0644 /etc/apt/keyrings/personal-os-docker.asc
cat > /etc/apt/sources.list.d/personal-os-docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $oracle_suite
Components: stable
Architectures: $oracle_arch
Signed-By: /etc/apt/keyrings/personal-os-docker.asc
EOF
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
docker info >/dev/null
docker compose version
echo 'Docker and Compose are ready. No Personal OS container has been started yet.'
