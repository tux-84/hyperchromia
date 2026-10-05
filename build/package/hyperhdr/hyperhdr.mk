################################################################################
#
# hyperhdr
#
################################################################################

HYPERHDR_VERSION = $(or $(HYPERHDR_DEFAULT_VERSION),v22.0.0.0)
HYPERHDR_SITE = https://github.com/awawa-dev/HyperHDR.git
HYPERHDR_SITE_METHOD = git
HYPERHDR_GIT_SUBMODULES = YES
HYPERHDR_LICENSE = MIT
HYPERHDR_LICENSE_FILES = LICENSE
HYPERHDR_INSTALL_STAGING = NO
HYPERHDR_DEPENDENCIES = qt6base qt6serialport jpeg openssl dbus alsa-lib libusb avahi flatbuffers host-pkgconf

# Force an out-of-source build. HyperHDR's CMakeLists.txt adds
# PROJECT_BINARY_DIR to the include path; with an in-source build (the
# Buildroot cmake-package default) that's the same directory as a
# plain-text "version" file HyperHDR keeps at its source root, which then
# shadows the real C++ standard library <version> header Qt's headers
# include, breaking compilation. Building out-of-tree keeps the two
# directories separate so the real system header resolves correctly.
HYPERHDR_SUPPORTS_IN_SOURCE_BUILD = NO

HYPERHDR_CONF_OPTS = \
	-DPLATFORM=linux \
	-DENABLE_V4L2=ON \
	-DENABLE_X11=OFF \
	-DENABLE_FRAMEBUFFER=OFF \
	-DENABLE_PIPEWIRE=OFF \
	-DENABLE_PIPEWIRE_EGL=OFF \
	-DENABLE_SYSTRAY=OFF \
	-DENABLE_CEC=OFF \
	-DENABLE_MQTT=OFF \
	-DENABLE_BONJOUR=ON \
	-DENABLE_PROTOBUF=ON \
	-DENABLE_ZSTD=ON \
	-DENABLE_SPIDEV=OFF \
	-DENABLE_SPI_FTDI=OFF \
	-DENABLE_WS281XPWM=OFF \
	-DENABLE_SOUNDCAPLINUX=OFF \
	-DENABLE_POWER_MANAGEMENT=OFF \
	-DUSE_SYSTEM_FLATBUFFERS_LIBS=ON \
	-DUSE_EMBEDDED_WEB_RESOURCES=ON \
	-DUSE_STATIC_QT_PLUGINS=OFF \
	-DUSE_PRECOMPILED_HEADERS=OFF \
	-DUSE_CCACHE_CACHING=OFF \
	-DCMAKE_BUILD_TYPE=Release

# The binary+libs are installed under a read-only "factory seed" tree on
# SYSTEM, not directly into /usr/bin. hyperchromia-seed-data.service copies this
# into the writable DATA partition (/data/hyperhdr) on first boot, and
# `hy factoryreset` re-copies it on demand — the copy actually executed at
# runtime always lives on DATA, so `hy upgrade`/`hy restore` never touch
# this read-only SYSTEM image. See board/rootfs-overlay/usr/share/hyperchromia/.
#
# Layout mirrors HyperHDR's own official release tarball on purpose
# (bin/hyperhdr + lib/hyperhdr/*.so as siblings): empirically confirmed
# (live test against the real tarball) that upstream's Linux release is a
# self-contained tree with its own companion libs and a bundled Qt6/OpenSSL
# under lib/hyperhdr/external/, resolved via the binary's own $ORIGIN-relative
# RPATH. hyperhdr.service instead sets LD_LIBRARY_PATH explicitly to the same
# two directories, so both our own build's simpler lib set (this recipe) and
# a future `hy upgrade`-installed official tarball resolve identically,
# without depending on RPATH being present in either binary.
HYPERHDR_SEED_ROOT = $(TARGET_DIR)/usr/share/hyperchromia/factory-seed/hyperhdr

define HYPERHDR_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/buildroot-build/bin/hyperhdr $(HYPERHDR_SEED_ROOT)/bin/hyperhdr
	mkdir -p $(HYPERHDR_SEED_ROOT)/lib/hyperhdr
	cp -a $(@D)/buildroot-build/lib/*.so* $(HYPERHDR_SEED_ROOT)/lib/hyperhdr/
	$(INSTALL) -D -m 0644 $(HYPERHDR_PKGDIR)/hyperhdr.service \
		$(TARGET_DIR)/usr/lib/systemd/system/hyperhdr.service
endef

define HYPERHDR_INSTALL_INIT_SYSTEMD
	mkdir -p $(TARGET_DIR)/etc/systemd/system/multi-user.target.wants
	ln -sf ../../../../usr/lib/systemd/system/hyperhdr.service \
		$(TARGET_DIR)/etc/systemd/system/multi-user.target.wants/hyperhdr.service
endef

$(eval $(cmake-package))
