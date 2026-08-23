# endroidd package for Buildroot

################################################################################
#
# endroidd
#
################################################################################

ENDROIDD_VERSION = 0.1.0
ENDROIDD_SITE = $(BR2_EXTERNAL_ENDROID_PATH)/../../daemon
ENDROIDD_SITE_METHOD = local
ENDROIDD_LICENSE = MIT
ENDROIDD_LICENSE_FILES = LICENSE

# Build using Cargo (Rust)
ENDROIDD_DEPENDENCIES = host-rust

define ENDROIDD_BUILD_CMDS
	cd $(@D)/.. && \
	$(CARGO_ENV) cargo build --release --target x86_64-unknown-linux-musl
	cp $(@D)/../target/x86_64-unknown-linux-musl/release/endroidd $(@D)/endroidd
endef

define ENDROIDD_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/endroidd $(TARGET_DIR)/usr/bin/endroidd
endef

$(eval $(generic-package))
