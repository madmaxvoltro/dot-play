#!/usr/bin/env bash
# Shared by build-qt.sh and build-app.sh: a Debian Trixie arm64 container with Raspberry Pi's apt
# repository added, so FFmpeg and Mesa match what Raspberry Pi OS ships.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq --no-install-recommends ca-certificates curl xz-utils zstd file > /dev/null
# the keyring package Raspberry Pi OS itself uses (the old raspberrypi.gpg.key is SHA-1 bound, which apt refuses)
curl -fsSL -o /tmp/rpi-keyring.deb \
  https://archive.raspberrypi.com/debian/pool/main/r/raspberrypi-archive-keyring/raspberrypi-archive-keyring_2025.1+rpt1_all.deb
dpkg -i /tmp/rpi-keyring.deb > /dev/null
KEYRING=$(dpkg -L raspberrypi-archive-keyring | grep -E '^/usr/share/keyrings/.*[.](pgp|gpg)$' | head -1)
echo "deb [signed-by=$KEYRING] http://archive.raspberrypi.com/debian trixie main" > /etc/apt/sources.list.d/raspi.list
apt-get update -qq

# what Qt itself is built against (and links to at run time on the Pi)
QT_DEPS="build-essential cmake ninja-build pkg-config python3 perl git
  libgl-dev libegl-dev libgles-dev libdrm-dev libgbm-dev
  libwayland-dev libwayland-bin wayland-protocols libxkbcommon-dev
  libfontconfig-dev libfreetype-dev libharfbuzz-dev libinput-dev libudev-dev libmtdev-dev
  libssl-dev libdbus-1-dev libglib2.0-dev
  libpng-dev libjpeg-dev libwebp-dev zlib1g-dev libzstd-dev libbrotli-dev
  libpcre2-dev libdouble-conversion-dev libb2-dev libmd4c-dev libmd4c-html0-dev"
