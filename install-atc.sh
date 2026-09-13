#!/usr/bin/env bash
# ATC installer — Made by Pakun & iinze0
set -euo pipefail
VER="${ATC_VER:-1.0.4}"
URL="https://github.com/brazyqueso/ATC/releases/download/v${VER}/atc_${VER}_all.deb"
DEB="/tmp/atc_${VER}_all.deb"

echo "[*] ATC v${VER} installer — Made by Pakun & iinze0"
echo "[*] $URL"

if command -v curl >/dev/null 2>&1; then
  curl -fL --retry 3 -o "$DEB" "$URL"
elif command -v wget >/dev/null 2>&1; then
  wget -O "$DEB" "$URL"
else
  echo "[!] need curl or wget"; exit 1
fi

if ! dpkg-deb -I "$DEB" >/dev/null 2>&1; then
  echo "[!] download is not a Debian package (GitHub HTML?)"
  head -c 180 "$DEB"; echo
  exit 1
fi

echo "[*] installing with dpkg (avoids apt /tmp sandbox errors)"
if [[ ${EUID} -ne 0 ]]; then
  sudo dpkg -i "$DEB"
else
  dpkg -i "$DEB"
fi

echo
echo "[+] $(dpkg-query -W -f='${Package} ${Version}' atc 2>/dev/null || echo atc missing)"
echo "    run:  sudo ATC"
