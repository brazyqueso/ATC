#!/usr/bin/env bash
# ATC — Made by Pakun & iinze0
# Adds a local apt source, then:  sudo apt install atc
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run:  sudo bash install.sh"
  echo "Then: sudo apt install atc"
  echo "Then: sudo ATC"
  exit 1
fi

src_dir=""
if [[ -n ${BASH_SOURCE[0]:-} && ${BASH_SOURCE[0]} != bash && ${BASH_SOURCE[0]} != - ]]; then
  src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
fi
[[ -n ${src_dir:-} ]] || { echo "Could not find installer directory"; exit 1; }

APTDIR="$src_dir/apt"
DEB="$APTDIR/atc_1.0.4_all.deb"
[[ -f $DEB ]] || { echo "Missing $DEB — clone the full repo"; exit 1; }

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y curl ca-certificates dpkg-dev 2>/dev/null || apt-get install -y curl ca-certificates

# local trusted file:// repo so later machines can: sudo apt install atc
mkdir -p /usr/local/share/atc-apt
cp -a "$APTDIR/." /usr/local/share/atc-apt/
# refresh Packages in case
(
  cd /usr/local/share/atc-apt
  if command -v dpkg-scanpackages >/dev/null; then
    dpkg-scanpackages -m . /dev/null > Packages 2>/dev/null || true
    gzip -9c Packages > Packages.gz 2>/dev/null || true
  fi
)

cat >/etc/apt/sources.list.d/atc.list << 'LIST'
deb [trusted=yes] file:/usr/local/share/atc-apt ./
LIST

apt-get update -o Dir::Etc::sourcelist=/etc/apt/sources.list.d/atc.list -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0
apt-get install -y atc

echo
echo "ATC installed via apt. Made by Pakun & iinze0"
echo "  sudo ATC"
echo "  sudo apt remove atc     # uninstall"
echo "  sudo apt purge atc      # uninstall + leftover config"
