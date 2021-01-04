TESTS_DEB := pkg-symlink

include ../Test.mk

test-case:
	# test unpacking symlinks
	$(DPKG_INSTALL) pkg-symlink.deb
	$(call pkg_is_installed,pkg-symlink)

test-clean:
	$(DPKG_PURGE) pkg-symlink

