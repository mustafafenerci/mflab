#!/usr/bin/env bash
# MF Lab - macOS .dmg. Önce: flutter build macos --release
# Kullanım: scripts/package_macos.sh <sürüm> [çıktı klasörü]
# İmzalama / noter onayı için ortam değişkenleri (hepsi isteğe bağlı; yoksa ad-hoc imzalı dmg üretilir):
#   MACOS_SIGN_IDENTITY   "Developer ID Application: Ad Soyad (TAKIMID)"
#   APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD   (notarytool için; uygulamaya özel parola)
set -euo pipefail
VERSION="${1:?sürüm gerekli (örn. 1.2.0)}"
OUT="${2:-dist}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/macos/Build/Products/Release/MFLab.app"
[ -d "$APP" ] || { echo "Önce 'flutter build macos --release' çalıştır." >&2; exit 1; }
mkdir -p "$ROOT/$OUT"
OUT_ABS="$(cd "$ROOT/$OUT" && pwd)"
DMG="MFLab-v${VERSION}-macos.dmg"

if [ -n "${MACOS_SIGN_IDENTITY:-}" ]; then
  echo "Uygulama imzalanıyor: $MACOS_SIGN_IDENTITY"
  codesign --force --deep --timestamp --options runtime \
    --entitlements "$ROOT/macos/Runner/Release.entitlements" \
    -s "$MACOS_SIGN_IDENTITY" "$APP"
else
  echo "UYARI: imza kimliği yok, ad-hoc imza kullanılıyor (Gatekeeper uyarı verir)."
  codesign --force --deep -s - "$APP"
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/MF Lab.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "MF Lab" -srcfolder "$STAGE" -ov -format UDZO "$OUT_ABS/$DMG"

if [ -n "${MACOS_SIGN_IDENTITY:-}" ]; then
  codesign --force --timestamp -s "$MACOS_SIGN_IDENTITY" "$OUT_ABS/$DMG"
  if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ] && [ -n "${APPLE_APP_PASSWORD:-}" ]; then
    echo "Apple noter onayına gönderiliyor (birkaç dakika sürer)..."
    xcrun notarytool submit "$OUT_ABS/$DMG" --apple-id "$APPLE_ID" \
      --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" --wait
    xcrun stapler staple "$OUT_ABS/$DMG"
  fi
fi
( cd "$OUT_ABS" && shasum -a 256 "$DMG" > "$DMG.sha256" )
echo "Hazır: $OUT_ABS/$DMG"
