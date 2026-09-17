#!/usr/bin/env bash
# Turn build/Silo.app into a distributable DMG: bundle Qt with macdeployqt, then
# (when a Developer ID identity is available) sign with the hardened runtime,
# notarize and staple both the .app and the .dmg.
#
#   scripts/package-macos.sh <build-dir> <version> [out-dir]
#
# Environment:
#   MACOS_SIGN_IDENTITY          "Developer ID Application: Name (TEAMID)". Unset => unsigned DMG.
#   APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD, APPLE_TEAM_ID
#                                Notarization credentials. All three required to notarize.
#   MACOS_ARCH_LABEL             Suffix in the DMG name (default: derived from the binary,
#                                "universal" when it contains both arm64 and x86_64).
set -euo pipefail

BUILD_DIR="${1:?usage: package-macos.sh <build-dir> <version> [out-dir]}"
VERSION="${2:?usage: package-macos.sh <build-dir> <version> [out-dir]}"
OUT_DIR="${3:-dist}"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="$BUILD_DIR/Silo.app"
ENTITLEMENTS="$ROOT_DIR/packaging/macos/entitlements.plist"
IDENTITY="${MACOS_SIGN_IDENTITY:-}"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

[ -d "$APP" ] || { echo "error: $APP not found (build first)" >&2; exit 1; }

ARCH_LABEL="${MACOS_ARCH_LABEL:-}"
if [ -z "$ARCH_LABEL" ]; then
  ARCHS="$(lipo -archs "$APP/Contents/MacOS/Silo" 2>/dev/null || true)"
  case "$ARCHS" in
    *arm64*x86_64*|*x86_64*arm64*) ARCH_LABEL="universal" ;;
    "")                            ARCH_LABEL="universal" ;;
    *)                             ARCH_LABEL="$ARCHS" ;;
  esac
fi
DMG_NAME="Silo-$VERSION-macos-$ARCH_LABEL.dmg"
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

# ---------------------------------------------------------------------------
# 1. Bundle Qt frameworks, plugins, QML imports and the WebEngine helper.
# ---------------------------------------------------------------------------
log "macdeployqt"
macdeployqt "$APP" -qmldir="$ROOT_DIR/qml" -verbose=1

# Development leftovers codesign refuses inside frameworks.
find "$APP/Contents/Frameworks" -name "Headers" -prune -exec rm -rf {} + 2>/dev/null || true
find "$APP/Contents/Frameworks" -name "*.prl" -delete 2>/dev/null || true

# ---------------------------------------------------------------------------
# 2. Sign, inside-out. Every Mach-O gets a hardened-runtime signature; the
#    executables (main binary, QtWebEngineProcess helper) get the entitlements.
# ---------------------------------------------------------------------------
if [ -n "$IDENTITY" ]; then
  log "codesign with identity: $IDENTITY"
  sign() { codesign --force --options runtime --timestamp --sign "$IDENTITY" "$@"; }

  # Loose binaries: dylibs, plugin bundles, helper executables. Skip the main
  # executable, it is signed together with the bundle at the end.
  while IFS= read -r -d '' f; do
    if file -b "$f" | grep -q "Mach-O"; then
      sign --entitlements "$ENTITLEMENTS" "$f"
    fi
  done < <(find "$APP/Contents" -type f \( -name "*.dylib" -o -name "*.so" -o -perm -u+x \) \
             -not -path "$APP/Contents/MacOS/Silo" -print0)

  # Nested bundles, deepest first (QtWebEngineProcess.app lives inside QtWebEngineCore.framework).
  while IFS= read -r -d '' bundle; do
    case "$bundle" in
      *.app) sign --entitlements "$ENTITLEMENTS" "$bundle" ;;
      *)     sign "$bundle" ;;
    esac
  done < <(find "$APP/Contents" -depth -type d \( -name "*.framework" -o -name "*.app" \) -print0)

  sign --entitlements "$ENTITLEMENTS" "$APP"

  log "codesign --verify"
  codesign --verify --deep --strict --verbose=2 "$APP"
else
  log "MACOS_SIGN_IDENTITY not set: producing an unsigned bundle"
fi

# ---------------------------------------------------------------------------
# 3. Notarization helpers.
# ---------------------------------------------------------------------------
can_notarize() {
  [ -n "$IDENTITY" ] && [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ]
}

notarize() {
  local target="$1" out id
  log "notarize $(basename "$target")"
  out="$(xcrun notarytool submit "$target" \
          --apple-id "$APPLE_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" --team-id "$APPLE_TEAM_ID" \
          --wait 2>&1)" || true
  echo "$out"
  id="$(echo "$out" | awk '/^  id: /{print $2; exit}')"
  if ! echo "$out" | grep -q "status: Accepted"; then
    echo "error: notarization failed" >&2
    if [ -n "$id" ]; then
      xcrun notarytool log "$id" \
        --apple-id "$APPLE_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" --team-id "$APPLE_TEAM_ID" || true
    fi
    exit 1
  fi
}

if can_notarize; then
  ZIP="$OUT_DIR/Silo-notarize.zip"
  ditto -c -k --keepParent "$APP" "$ZIP"
  notarize "$ZIP"
  rm -f "$ZIP"
  log "staple Silo.app"
  xcrun stapler staple "$APP"
else
  log "notarization credentials not set: skipping app notarization"
fi

# ---------------------------------------------------------------------------
# 4. DMG with an /Applications shortcut.
# ---------------------------------------------------------------------------
log "hdiutil create $DMG_NAME"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$OUT_DIR/$DMG_NAME"
# hdiutil occasionally fails with "Resource busy" on CI runners; retry a few times.
for attempt in 1 2 3 4 5; do
  if hdiutil create -volname "Silo" -srcfolder "$STAGING" -ov -format UDZO "$OUT_DIR/$DMG_NAME"; then
    break
  fi
  [ "$attempt" -eq 5 ] && { echo "error: hdiutil failed" >&2; exit 1; }
  sleep 5
done

if [ -n "$IDENTITY" ]; then
  log "codesign DMG"
  codesign --force --timestamp --sign "$IDENTITY" "$OUT_DIR/$DMG_NAME"
fi

if can_notarize; then
  notarize "$OUT_DIR/$DMG_NAME"
  log "staple DMG"
  xcrun stapler staple "$OUT_DIR/$DMG_NAME"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$OUT_DIR/$DMG_NAME" || true
fi

log "done: $OUT_DIR/$DMG_NAME"
