#!/bin/bash
# shellcheck disable=SC1091
set -euo pipefail

HYPERCHROMIA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILDROOT_TAG=2026.08
JOBS="${JOBS:-8}"
EXTERNAL_PATH=/opt/hyperchromia/build
CONTAINER=""
WORKVOL=""

hy_stop_container() {
  if [ -n "$CONTAINER" ]; then
    if [ "${HY_CI_CLEANUP:-}" = "1" ]; then
      docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
      [ -n "$WORKVOL" ] && docker volume rm "$WORKVOL" >/dev/null 2>&1 || true
    else
      docker stop "$CONTAINER" >/dev/null 2>&1 || true
    fi
  fi
}

hy_cleanup_on_interrupt() {
  echo
  echo "==> Interrupted -- stopping the build container..." >&2
  hy_stop_container
  exit 130
}
trap hy_cleanup_on_interrupt INT TERM
trap hy_stop_container EXIT

echo "==> Preflight checks"
if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker is not installed. Install Docker Desktop and re-run." >&2
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  echo "ERROR: docker is installed but the daemon isn't running (docker info failed). Start Docker Desktop and re-run." >&2
  exit 1
fi
if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: git is not installed." >&2
  exit 1
fi

if [ -z "${HY_PRESEED_FILE:-}" ] && [ ! -s "$HYPERCHROMIA_DIR/authorized_keys" ]; then
  echo "WARNING: no $HYPERCHROMIA_DIR/authorized_keys found, and this build has no preseeded" >&2
  echo "         root password -- the resulting image will have NO way to log in as root" >&2
  echo "         (password login is disabled by default). Add your SSH public key to" >&2
  echo "         $HYPERCHROMIA_DIR/authorized_keys before building if you need root access." >&2
fi

if [ -f "$HYPERCHROMIA_DIR/config.env" ]; then
  source "$HYPERCHROMIA_DIR/config.env"
fi
HYPERCHROMIA_DEFAULT_HOSTNAME="${HYPERCHROMIA_DEFAULT_HOSTNAME:-hyperchromia}"
HYPERHDR_DEFAULT_VERSION="${HYPERHDR_DEFAULT_VERSION:-latest}"
if [ "$HYPERHDR_DEFAULT_VERSION" = "latest" ]; then
  HYPERHDR_DEFAULT_VERSION="$(curl -fsSL https://api.github.com/repos/awawa-dev/HyperHDR/releases/latest 2>/dev/null \
    | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
fi
HYPERHDR_DEFAULT_VERSION="${HYPERHDR_DEFAULT_VERSION:-v22.0.0.0}"

HYPERCHROMIA_VERSION="$(cd "$HYPERCHROMIA_DIR" && git describe --tags --exact-match HEAD 2>/dev/null || true)"
if [ -z "$HYPERCHROMIA_VERSION" ]; then
  HYPERCHROMIA_VERSION="v$(cat "$HYPERCHROMIA_DIR/VERSION" 2>/dev/null || echo 0.0.0)-dev"
fi
echo "==> HyperChromia version for this build: $HYPERCHROMIA_VERSION"
echo "==> Default hostname: $HYPERCHROMIA_DEFAULT_HOSTNAME | HyperHDR seed version: $HYPERHDR_DEFAULT_VERSION"

CONTAINER="hyperchromia-build-$BUILDROOT_TAG-$HYPERCHROMIA_VERSION"
WORKVOL="hyperchromia-work-$BUILDROOT_TAG-$HYPERCHROMIA_VERSION"

if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "==> Found existing container $CONTAINER from a previous build of this version"
  if [ -n "${HY_CONTAINER_CHOICE:-}" ]; then
    echo "    Using HY_CONTAINER_CHOICE=$HY_CONTAINER_CHOICE from caller."
  elif [ -t 0 ]; then
    read -r -p "    Resume it, or start from scratch (removes the container and its data)? [resume/scratch] " HY_CONTAINER_CHOICE
  else
    HY_CONTAINER_CHOICE="resume"
    echo "    No TTY attached -- defaulting to resume."
  fi
  if [ "$HY_CONTAINER_CHOICE" = "scratch" ]; then
    echo "==> Removing $CONTAINER and volume $WORKVOL"
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    docker volume rm "$WORKVOL" >/dev/null 2>&1 || true
  fi
fi

if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "==> Reusing existing container $CONTAINER"
  docker start "$CONTAINER" >/dev/null
else
  echo "==> Creating container $CONTAINER"
  docker volume create "$WORKVOL" > /dev/null
  docker run -d --name "$CONTAINER" \
    --platform linux/arm64 \
    -v "$HYPERCHROMIA_DIR/build:$EXTERNAL_PATH" \
    -v "$WORKVOL:/work" \
    --cpus 8 --memory 7g \
    debian:trixie sleep infinity
  docker exec "$CONTAINER" bash -c "
    apt-get update -qq
    apt-get install -y -qq build-essential git cmake ninja-build bc cpio rsync unzip wget \
      python3 python3-pip libncurses-dev file patch bzip2 gzip perl tar util-linux \
      libssl-dev pkg-config sed make gcc g++ e2fsprogs grub-common
    dpkg --add-architecture amd64
    apt-get update -qq
    apt-get install -y -qq grub-efi-amd64-bin:amd64
    grub-mkimage -O x86_64-efi -o /opt/hyperchromia-grubx64.efi -p /EFI/debian \
      -d /usr/lib/grub/x86_64-efi \
      boot linux fat part_gpt normal efi_gop loadenv test
    apt-get download busybox-static:amd64
    dpkg-deb -x busybox-static_*_amd64.deb /tmp/busybox-extract
    install -m 755 /tmp/busybox-extract/usr/bin/busybox /opt/hyperchromia-busybox
    rm -rf busybox-static_*_amd64.deb /tmp/busybox-extract
  "
fi

if ! docker exec "$CONTAINER" test -d /work/buildroot; then
  echo "==> Cloning Buildroot $BUILDROOT_TAG"
  docker exec "$CONTAINER" git clone --depth 1 --branch "$BUILDROOT_TAG" \
    https://github.com/buildroot/buildroot.git /work/buildroot
fi

if ! docker exec "$CONTAINER" test -f /work/buildroot/.config; then
  echo "==> Generating base config (pc_x86_64_efi_defconfig)"
  docker exec "$CONTAINER" bash -c "cd /work/buildroot && make BR2_EXTERNAL=$EXTERNAL_PATH pc_x86_64_efi_defconfig"
fi

echo "==> Patching connman to push DHCP-learned DNS servers to systemd-resolved"
docker exec "$CONTAINER" bash -c "
  grep -q 'with-dns-backend=systemd-resolved' /work/buildroot/package/connman/connman.mk || \
    sed -i 's|^CONNMAN_CONF_OPTS = --with-dbusconfdir=/etc\$|CONNMAN_CONF_OPTS = --with-dbusconfdir=/etc --with-dns-backend=systemd-resolved|' \
      /work/buildroot/package/connman/connman.mk
"

echo "==> Applying HyperChromia config options"
docker exec "$CONTAINER" bash -c "
  cd /work/buildroot
  ./utils/config --file .config \\
    --enable BR2_TOOLCHAIN_BUILDROOT_CXX \\
    --enable BR2_INIT_SYSTEMD \\
    --disable BR2_INIT_BUSYBOX \\
    --enable BR2_PACKAGE_OPENSSH \\
    --enable BR2_PACKAGE_ETHTOOL \\
    --enable BR2_PACKAGE_HYPERHDR \\
    --enable BR2_PACKAGE_BASH \\
    --enable BR2_PACKAGE_UTIL_LINUX \\
    --enable BR2_PACKAGE_UTIL_LINUX_BINARIES \\
    --enable BR2_PACKAGE_NCURSES \\
    --enable BR2_PACKAGE_NCURSES_TARGET_PROGS \\
    --enable BR2_PACKAGE_DIALOG \\
    --enable BR2_PACKAGE_KBD \\
    --enable BR2_PACKAGE_JQ \\
    --enable BR2_PACKAGE_ONIGURUMA \\
    --enable BR2_PACKAGE_SQLITE \\
    --enable BR2_PACKAGE_MOSQUITTO \\
    --disable BR2_PACKAGE_MOSQUITTO_BROKER \\
    --enable BR2_TARGET_GRUB2_INSTALL_TOOLS \\
    --set-str BR2_TARGET_GRUB2_BUILTIN_MODULES_EFI 'boot linux fat part_gpt normal efi_gop loadenv test' \\
    --enable BR2_PACKAGE_TAR \\
    --enable BR2_PACKAGE_CONNMAN_LOOPBACK \\
    --enable BR2_PACKAGE_WGET \\
    --enable BR2_PACKAGE_CA_CERTIFICATES \\
    --enable BR2_PACKAGE_E2FSPROGS \\
    --enable BR2_PACKAGE_DOSFSTOOLS \\
    --enable BR2_PACKAGE_DOSFSTOOLS_MKFS_FAT \\
    --enable BR2_PACKAGE_GPTFDISK \\
    --enable BR2_PACKAGE_GPTFDISK_SGDISK \\
    --enable BR2_PACKAGE_PARTED \\
    --disable BR2_TARGET_ROOTFS_EXT2 \\
    --enable BR2_TARGET_ROOTFS_SQUASHFS \\
    --set-str BR2_ROOTFS_OVERLAY '$EXTERNAL_PATH/board/rootfs-overlay' \\
    --set-str BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES '$EXTERNAL_PATH/board/kernel-fragment.config' \\
    --set-str BR2_ROOTFS_POST_BUILD_SCRIPT '$EXTERNAL_PATH/board/post-build-hyperchromia.sh' \\
    --set-str BR2_ROOTFS_POST_IMAGE_SCRIPT '$EXTERNAL_PATH/board/post-image-hyperchromia.sh'
  make olddefconfig
"

CONTAINER_PRESEED=""
if [ -n "${HY_PRESEED_FILE:-}" ] && [ -f "$HY_PRESEED_FILE" ]; then
  cp "$HY_PRESEED_FILE" "$HYPERCHROMIA_DIR/build/.preseed-firstboot.conf"
  CONTAINER_PRESEED="$EXTERNAL_PATH/.preseed-firstboot.conf"
fi

CONTAINER_AUTHKEYS=""
if [ -f "$HYPERCHROMIA_DIR/authorized_keys" ]; then
  cp "$HYPERCHROMIA_DIR/authorized_keys" "$HYPERCHROMIA_DIR/build/.authorized_keys"
  CONTAINER_AUTHKEYS="$EXTERNAL_PATH/.authorized_keys"
fi

echo "==> Building (log: docker exec $CONTAINER tail -f /work/build.log)"
docker exec -t \
  -e HYPERCHROMIA_VERSION="$HYPERCHROMIA_VERSION" \
  -e HYPERCHROMIA_DEFAULT_HOSTNAME="$HYPERCHROMIA_DEFAULT_HOSTNAME" \
  -e HYPERHDR_DEFAULT_VERSION="$HYPERHDR_DEFAULT_VERSION" \
  -e HY_PRESEED_FILE="$CONTAINER_PRESEED" \
  -e HY_AUTHORIZED_KEYS="$CONTAINER_AUTHKEYS" \
  -e HY_GRUB_EFI_PATH=/opt/hyperchromia-grubx64.efi \
  -e HY_BUSYBOX_PATH=/opt/hyperchromia-busybox \
  "$CONTAINER" bash -c "cd /work/buildroot && make -j$JOBS" 2>&1 | tee "$HYPERCHROMIA_DIR/build.log"

if [ -n "$CONTAINER_PRESEED" ]; then
  shred -u "$HYPERCHROMIA_DIR/build/.preseed-firstboot.conf" 2>/dev/null \
    || rm -f "$HYPERCHROMIA_DIR/build/.preseed-firstboot.conf"
fi
if [ -n "$CONTAINER_AUTHKEYS" ]; then
  rm -f "$HYPERCHROMIA_DIR/build/.authorized_keys"
fi

echo "==> Copying final images to $HYPERCHROMIA_DIR"
docker cp "$CONTAINER:/work/buildroot/output/images/factory.img" "$HYPERCHROMIA_DIR/factory.img"
docker cp "$CONTAINER:/work/buildroot/output/images/update.img" "$HYPERCHROMIA_DIR/update.img"
echo "==> Done: $HYPERCHROMIA_DIR/factory.img ($(du -h "$HYPERCHROMIA_DIR/factory.img" | cut -f1)), $HYPERCHROMIA_DIR/update.img ($(du -h "$HYPERCHROMIA_DIR/update.img" | cut -f1))"
