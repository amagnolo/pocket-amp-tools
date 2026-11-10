#!/bin/sh
# Wraps the Flutter release bundle in an AppImage.
#   linux/packaging/build-appimage.sh <bundle dir> <appimagetool> <output>
set -eu
bundle="$1"; tool="$2"; out="$3"
here="$(dirname "$(readlink -f "$0")")"
appdir="$(mktemp -d)/AppDir"
mkdir -p "$appdir/opt"
cp -r "$bundle" "$appdir/opt/pocket-amp-tools"
cp "$here/AppRun" "$appdir/AppRun"
cp "$here/pocket-amp-tools.desktop" "$appdir/"
cp "$bundle/data/app_icon.png" "$appdir/pocket-amp-tools.png"
ln -s pocket-amp-tools.png "$appdir/.DirIcon"
# RUNTIME_FILE pins the AppImage runtime; without it appimagetool downloads
# the latest one.
if [ -n "${RUNTIME_FILE:-}" ]; then
  set -- --runtime-file "$RUNTIME_FILE"
else
  set --
fi
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$tool" --no-appstream "$@" "$appdir" "$out"
