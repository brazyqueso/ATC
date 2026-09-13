#!/usr/bin/env bash
# ATC — Advanced Target Control. Made by Pakun.
# Private repo. Clone, then:
#   sudo bash install.sh
# Launch:
#   sudo ATC
set -euo pipefail

REPO_USER="${ATC_GITHUB_USER:-brazyqueso}"
REPO_NAME="${ATC_GITHUB_REPO:-ATC}"
BRANCH="${ATC_GITHUB_BRANCH:-main}"
BIN="/usr/bin/ATC"
BIN_LC="/usr/bin/atc"

if [[ ${EUID} -ne 0 ]]; then
  echo "ATC needs root to land in ${BIN}."
  echo "  cd ATC && sudo bash install.sh"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y curl ca-certificates

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

local_copy=""
if [[ -n ${BASH_SOURCE[0]:-} && ${BASH_SOURCE[0]} != bash && ${BASH_SOURCE[0]} != - ]]; then
  src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
  if [[ -n ${src_dir:-} && -f "$src_dir/ATC.sh" ]]; then
    local_copy="$src_dir/ATC.sh"
  fi
fi

if [[ -n $local_copy && ${ATC_FORCE_REMOTE:-} != 1 ]]; then
  echo "Installing from $local_copy"
  install -m 0755 "$local_copy" "$BIN"
else
  RAW="https://raw.githubusercontent.com/${REPO_USER}/${REPO_NAME}/${BRANCH}/ATC.sh"
  echo "Downloading ATC from $RAW"
  if [[ -n ${GITHUB_TOKEN:-} ]]; then
    curl -fsSL -H "Authorization: Bearer ${GITHUB_TOKEN}" "$RAW" -o "$tmp"
  else
    curl -fsSL "$RAW" -o "$tmp"
  fi
  head -1 "$tmp" | grep -q '^#!' || { echo "download was not a script"; exit 1; }
  grep -q 'Advanced Target Control' "$tmp" || { echo "download was not ATC"; exit 1; }
  install -m 0755 "$tmp" "$BIN"
fi

ln -sf "$BIN" "$BIN_LC"

if [[ -n ${SUDO_USER:-} ]]; then
  user_home="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
  if [[ -n ${user_home:-} && -d $user_home ]]; then
    mkdir -p "$user_home/.local/bin"
    install -m 0755 "$BIN" "$user_home/.local/bin/ATC"
    ln -sf "$user_home/.local/bin/ATC" "$user_home/.local/bin/atc"
    chown "$SUDO_USER:" "$user_home/.local/bin/ATC" 2>/dev/null || true
  fi
fi

mkdir -p /var/lib/atc /usr/share/pixmaps /usr/share/applications
chmod 0755 /var/lib/atc

# icon (hydra-style, not LFD)
cat >/usr/share/pixmaps/atc.svg <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
  <rect width="64" height="64" rx="8" fill="#06140c"/>
  <rect x="2" y="2" width="60" height="60" rx="6" fill="none" stroke="#2ee67a" stroke-width="2"/>
  <!-- three hydra heads -->
  <path d="M18 40 C16 32 10 28 12 20 C14 14 20 16 22 22 C20 28 22 34 24 40 Z" fill="#1a8f4a"/>
  <path d="M32 42 C30 30 26 22 32 12 C38 22 34 30 32 42 Z" fill="#2ee67a"/>
  <path d="M46 40 C48 32 54 28 52 20 C50 14 44 16 42 22 C44 28 42 34 40 40 Z" fill="#1a8f4a"/>
  <!-- eyes -->
  <circle cx="16" cy="22" r="1.4" fill="#0a0a0a"/>
  <circle cx="32" cy="16" r="1.6" fill="#0a0a0a"/>
  <circle cx="48" cy="22" r="1.4" fill="#0a0a0a"/>
  <!-- body -->
  <path d="M24 40 C26 50 38 50 40 40 C38 54 26 54 24 40 Z" fill="#145c32"/>
  <text x="32" y="60" text-anchor="middle" font-family="monospace" font-size="8" fill="#2ee67a">ATC</text>
</svg>
SVG

cat >/usr/share/applications/atc.desktop <<'EOF'
[Desktop Entry]
Name=ATC
GenericName=Advanced Target Control
Comment=ATC — Kali pentest menu. Made by Pakun.
Exec=x-terminal-emulator -e sudo ATC
Icon=atc
Terminal=false
Type=Application
Categories=System;Security;Network;
Keywords=atc;kali;pentest;pakun;hydra;
StartupNotify=false
EOF

# also drop a pixmaps png-less alias
ln -sf /usr/share/pixmaps/atc.svg /usr/share/pixmaps/ATC.svg 2>/dev/null || true

echo
echo "ATC installed at $BIN"
echo "Made by Pakun   $REPO_USER"
echo
echo "Launch:"
echo "    sudo ATC"
echo "or Applications → ATC"
