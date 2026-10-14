#!/usr/bin/env bash
# Builds Dot Play against the Qt from build-qt.sh and packs $PREFIX as out/dot-play-arm64.tar.zst,
# plus out/dot-play-arm64.deps: the Debian packages it needs at run time (Dot's installer installs them).
set -euo pipefail
. "$(dirname "$0")/common.sh"
# shellcheck disable=SC2086
apt-get install -y -qq --no-install-recommends $QT_DEPS \
  libsdl2-dev libsdl2-ttf-dev libopus-dev libavcodec-dev libavutil-dev libswscale-dev \
  libva-dev > /dev/null

tar -C / --zstd -xf /src/out/qt-*.tar.zst

git config --global --add safe.directory '*'
mkdir -p /tmp/build
cd /tmp/build
"$PREFIX/bin/qmake" /src/moonlight-qt.pro CONFIG+=release PREFIX="$PREFIX" QMAKE_RPATHDIR+="$PREFIX/lib"
make -j"$(nproc)"
make install > /dev/null

# only what runs on the Pi: no headers, build tools or Qt's own programs
cd "$PREFIX"
rm -rf include mkspecs doc metatypes modules sbom libexec lib/cmake lib/pkgconfig lib/objects-* lib/*.prl lib/*.a
find bin -type f ! -name dot-play -delete

# run-time packages, from every ELF file's libraries outside the bundle
find "$PREFIX" -type f \( -name '*.so*' -o -path '*/bin/*' \) -exec file {} + | grep -F ELF | cut -d: -f1 \
  | { xargs ldd 2>/dev/null || true; } | awk '/=> \// {print $3}' | grep -v "^$PREFIX" \
  | xargs -r realpath | sort -u \
  | { xargs -r dpkg -S 2>/dev/null || true; } | cut -d: -f1 | sort -u > /src/out/dot-play-arm64.deps
echo "run-time packages:"; cat /src/out/dot-play-arm64.deps

echo "${GITHUB_SHA:-local}" > "$PREFIX/BUILD"
tar -C / --zstd -cf /src/out/dot-play-arm64.tar.zst "${PREFIX#/}"
ls -lh /src/out
