#!/usr/bin/env bash
# Turn the Linux build into a self-contained AppImage with linuxdeploy and its Qt plugin.
#
#   scripts/package-linux.sh <build-dir> <version> [out-dir]
#
# Environment:
#   QT_ROOT_DIR   Qt installation prefix (set by install-qt-action). Falls back to `qmake` on PATH.
set -euo pipefail

BUILD_DIR="${1:?usage: package-linux.sh <build-dir> <version> [out-dir]}"
VERSION="${2:?usage: package-linux.sh <build-dir> <version> [out-dir]}"
OUT_DIR="${3:-dist}"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="$(uname -m)"
APPDIR="$(pwd)/AppDir"
TOOLS_DIR="$(pwd)/.linuxdeploy"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

mkdir -p "$OUT_DIR" "$TOOLS_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

# ---------------------------------------------------------------------------
# 1. Fetch linuxdeploy + qt plugin.
# ---------------------------------------------------------------------------
fetch() {
  local url="$1" dest="$2"
  if [ ! -x "$dest" ]; then
    log "download $(basename "$dest")"
    curl -fsSL --retry 3 -o "$dest" "$url"
    chmod +x "$dest"
  fi
}
fetch "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-$ARCH.AppImage" \
      "$TOOLS_DIR/linuxdeploy"
fetch "https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-$ARCH.AppImage" \
      "$TOOLS_DIR/linuxdeploy-plugin-qt"

# ---------------------------------------------------------------------------
# 2. Stage the app into AppDir (uses the install() rules from CMakeLists.txt).
# ---------------------------------------------------------------------------
log "cmake --install"
rm -rf "$APPDIR"
cmake --install "$BUILD_DIR" --prefix "$APPDIR/usr"

ICON="$TOOLS_DIR/silo.png"
cp "$ROOT_DIR/icons/logo/logo-512.png" "$ICON"

# Chromium's sandbox needs unprivileged user namespaces. Ubuntu >= 24.04 blocks
# them through AppArmor for non-profiled binaries (an AppImage is one), and some
# distros disable them altogether; fall back to running WebEngine unsandboxed
# there, otherwise every web tab dies with "No usable sandbox!".
mkdir -p "$APPDIR/apprun-hooks"
cat > "$APPDIR/apprun-hooks/silo-webengine-sandbox.sh" <<'EOF'
if [ -z "${QTWEBENGINE_DISABLE_SANDBOX:-}" ]; then
  if [ "$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns 2>/dev/null)" = "1" ] \
     || [ "$(cat /proc/sys/kernel/unprivileged_userns_clone 2>/dev/null)" = "0" ]; then
    export QTWEBENGINE_DISABLE_SANDBOX=1
  fi
fi
EOF

# ---------------------------------------------------------------------------
# 3. Bundle Qt and build the AppImage.
# ---------------------------------------------------------------------------
if [ -n "${QT_ROOT_DIR:-}" ]; then
  QMAKE="$QT_ROOT_DIR/bin/qmake"
else
  QMAKE="$(command -v qmake6 || command -v qmake)"
fi
export QMAKE
export QML_SOURCES_PATHS="$ROOT_DIR/qml"
export EXTRA_PLATFORM_PLUGINS="libqwayland-generic.so;libqwayland-egl.so"
export OUTPUT="$OUT_DIR/Silo-$VERSION-linux-$ARCH.AppImage"
# Runners have no FUSE; run the AppImage tools by extracting them instead.
export APPIMAGE_EXTRACT_AND_RUN=1
export PATH="$TOOLS_DIR:$PATH"

log "linuxdeploy (qmake: $QMAKE)"
linuxdeploy \
  --appdir "$APPDIR" \
  --executable "$APPDIR/usr/bin/Silo" \
  --desktop-file "$ROOT_DIR/packaging/linux/silo.desktop" \
  --icon-file "$ICON" \
  --plugin qt \
  --output appimage

log "done: $OUTPUT"
