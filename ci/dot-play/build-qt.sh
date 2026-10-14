#!/usr/bin/env bash
# Builds Qt $QT_VERSION (modules: $QT_MODULES) into $PREFIX and packs it as out/qt-*.tar.zst.
set -euo pipefail
. "$(dirname "$0")/common.sh"
# shellcheck disable=SC2086
apt-get install -y -qq --no-install-recommends $QT_DEPS > /dev/null

SERIES=${QT_VERSION%.*}
WORK=/tmp/qt
mkdir -p "$WORK"
cd "$WORK"
for m in $QT_MODULES; do
  echo "::group::$m"
  curl -fsSL "https://download.qt.io/official_releases/qt/$SERIES/$QT_VERSION/submodules/$m-everywhere-src-$QT_VERSION.tar.xz" | tar -xJ
  mkdir -p "build-$m"
  cd "build-$m"
  if [ "$m" = qtbase ]; then
    "../$m-everywhere-src-$QT_VERSION/configure" -prefix "$PREFIX" -release \
      -opengl es2 -no-xcb -nomake examples -nomake tests -- -G Ninja
  else
    "$PREFIX/bin/qt-configure-module" "../$m-everywhere-src-$QT_VERSION"
  fi
  cmake --build . --parallel "$(nproc)"
  cmake --install . > /dev/null
  cd "$WORK"
  rm -rf "build-$m" "$m-everywhere-src-$QT_VERSION"
  echo "::endgroup::"
done

mkdir -p /src/out
tar -C / --zstd -cf "/src/out/qt-$QT_VERSION-trixie-arm64.tar.zst" "${PREFIX#/}"
ls -lh /src/out
