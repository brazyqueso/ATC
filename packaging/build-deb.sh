#!/usr/bin/env bash
set -euo pipefail
# rebuild atc_1.0.0_all.deb from this repo (run from repo root)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VER="$(cat "$ROOT/VERSION" | tr -d '[:space:]')"
PKG="/tmp/atc-deb-build/atc_${VER}_all"
rm -rf /tmp/atc-deb-build
mkdir -p "$PKG/DEBIAN" "$PKG/usr/bin" "$PKG/usr/lib/atc" \
  "$PKG/usr/share/applications" "$PKG/usr/share/pixmaps" "$PKG/usr/share/doc/atc" "$PKG/var/lib/atc"
install -m 0755 "$ROOT/ATC.sh" "$PKG/usr/lib/atc/ATC.sh"
install -m 0644 "$ROOT/atc.svg" "$PKG/usr/share/pixmaps/atc.svg"
install -m 0755 "$ROOT/packaging/DEBIAN/"* "$PKG/DEBIAN/" 2>/dev/null || true
# wrappers + desktop recreated in case
printf '%s\n' '#!/usr/bin/env bash' 'exec /usr/lib/atc/ATC.sh "$@"' > "$PKG/usr/bin/ATC"
chmod 0755 "$PKG/usr/bin/ATC"
ln -sf ATC "$PKG/usr/bin/atc"
dpkg-deb --root-owner-group --build "$PKG" "$ROOT/apt/atc_${VER}_all.deb"
(
  cd "$ROOT/apt"
  dpkg-scanpackages -m . /dev/null > Packages
  gzip -9c Packages > Packages.gz
)
echo "built $ROOT/apt/atc_${VER}_all.deb"
