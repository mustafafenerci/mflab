#!/usr/bin/env bash
# MF Lab - Linux paketleri (.deb ve .tar.gz). Önce: flutter build linux --release
# Kullanım: scripts/package_linux.sh <sürüm> [çıktı klasörü]
set -euo pipefail
VERSION="${1:?sürüm gerekli (örn. 1.2.0)}"
OUT="${2:-dist}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE="$ROOT/build/linux/x64/release/bundle"
[ -d "$BUNDLE" ] || { echo "Önce 'flutter build linux --release' çalıştır." >&2; exit 1; }
mkdir -p "$ROOT/$OUT"
OUT_ABS="$(cd "$ROOT/$OUT" && pwd)"

# --- .tar.gz (kurulumsuz, herhangi bir dağıtım)
TAR="MFLab-v${VERSION}-linux-x64.tar.gz"
tar -C "$BUNDLE" -czf "$OUT_ABS/$TAR" .

# --- .deb (Debian / Ubuntu / Mint)
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
install -d "$STAGE/opt/mflab" "$STAGE/usr/bin" "$STAGE/usr/share/applications" \
  "$STAGE/usr/share/icons/hicolor/256x256/apps" "$STAGE/DEBIAN"
cp -r "$BUNDLE"/. "$STAGE/opt/mflab/"
ln -s /opt/mflab/mflab "$STAGE/usr/bin/mflab"
install -m 644 "$ROOT/linux/packaging/mflab.desktop" "$STAGE/usr/share/applications/mflab.desktop"
install -m 644 "$ROOT/linux/packaging/mflab.png" "$STAGE/usr/share/icons/hicolor/256x256/apps/mflab.png"
SIZE_KB="$(du -sk "$STAGE/opt" | cut -f1)"
cat > "$STAGE/DEBIAN/control" <<CTL
Package: mflab
Version: ${VERSION}
Section: education
Priority: optional
Architecture: amd64
Installed-Size: ${SIZE_KB}
Maintainer: Mustafa Fenerci <mustafa.fenerci@kapadokya.edu.tr>
Depends: libgtk-3-0, zip, xdg-utils
Recommends: docker.io | docker-ce, docker-compose-v2 | docker-compose-plugin
Homepage: https://github.com/mustafafenerci/mflab
Description: MF Lab - one-click lab environments for software courses
 Installs and manages Docker-based course environments (Apache, PHP,
 MariaDB, PostgreSQL, phpMyAdmin) with a single click.
CTL
DEB="MFLab-v${VERSION}-linux-amd64.deb"
dpkg-deb --build --root-owner-group "$STAGE" "$OUT_ABS/$DEB"

( cd "$OUT_ABS" && sha256sum "$TAR" > "$TAR.sha256" && sha256sum "$DEB" > "$DEB.sha256" )
echo "Hazır: $OUT_ABS/$DEB  $OUT_ABS/$TAR"
