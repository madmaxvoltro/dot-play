#!/usr/bin/env bash
# Shared by build-qt.sh and build-app.sh: a Debian Trixie arm64 container with Raspberry Pi's apt
# repository added, so FFmpeg and Mesa match what Raspberry Pi OS ships.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq --no-install-recommends ca-certificates curl gnupg xz-utils zstd file > /dev/null
curl -fsSL https://archive.raspberrypi.com/debian/raspberrypi.gpg.key | gpg --dearmor -o /usr/share/keyrings/raspberrypi.gpg
echo "deb [signed-by=/usr/share/keyrings/raspberrypi.gpg] http://archive.raspberrypi.com/debian trixie main" \
  > /etc/apt/sources.list.d/raspi.list
apt-get update -qq

# what Qt itself is built against (and links to at run time on the Pi)
QT_DEPS="build-essential cmake ninja-build pkg-config python3 perl git
  libgl-dev libegl-dev libgles-dev libdrm-dev libgbm-dev
  libwayland-dev libwayland-bin wayland-protocols libxkbcommon-dev
  libfontconfig-dev libfreetype-dev libharfbuzz-dev libinput-dev libudev-dev libmtdev-dev
  libssl-dev libdbus-1-dev libglib2.0-dev
  libpng-dev libjpeg-dev libwebp-dev zlib1g-dev libzstd-dev libbrotli-dev
  libpcre2-dev libdouble-conversion-dev libb2-dev libmd4c-dev libmd4c-html0-dev"
