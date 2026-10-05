#!/usr/bin/env bash
# Concept: Mukesh Kesharwani
# Contact: mukesh.kesharwani@adobe.com
# Called only during bootstrap, before any browser process starts.
set -euo pipefail

apt_options=(
  -o APT::Update::Error-Mode=any
  -o APT::Get::AllowUnauthenticated=false
  -o Acquire::AllowInsecureRepositories=false
  -o Acquire::AllowDowngradeToInsecureRepositories=false
  -o Acquire::Check-Valid-Until=true
  -o Acquire::https::Verify-Peer=true
  -o Acquire::https::Verify-Host=true
  -o Acquire::Retries=2
  -o Acquire::http::Timeout=30
  -o Acquire::https::Timeout=30
  -o DPkg::Lock::Timeout=60
  -o Dpkg::Use-Pty=0
  -o Dpkg::Options::=--force-confdef
  -o Dpkg::Options::=--force-confold
)
export DEBIAN_FRONTEND=noninteractive
apt-get "${apt_options[@]}" update
# Refresh installed libraries too; refuse upgrades that would remove packages.
apt-get "${apt_options[@]}" --no-remove --with-new-pkgs -y upgrade

for package in chromium chromium-common chromium-sandbox; do
  candidate="$(apt-cache policy "$package" | awk '/Candidate:/ {print $2; exit}')"
  installed="$(dpkg-query -W -f='${Version}' "$package")"
  if [ "$candidate" != "$installed" ]; then
    echo 'A Chromium package does not match the signed repository candidate.' >&2
    exit 1
  fi
done
test -z "$(dpkg --audit)"
chromium --version
manifest="$(mktemp /usr/share/headless-chrome/packages.XXXXXX)"
trap 'rm -f "$manifest"' EXIT
dpkg-query -W -f='${Package}\t${Version}\n' > "$manifest"
chmod 644 "$manifest"
mv "$manifest" /usr/share/headless-chrome/packages.txt
