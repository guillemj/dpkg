TESTS_DEB := pkg-symlink

include ../Test.mk

test-case:
	# test unpacking symlinks
	$(DPKG_INSTALL) pkg-symlink.deb
	test "`$(PKG_STATUS) pkg-symlink`" = "install ok installed"

test-clean:
	$(DPKG_PURGE) pkg-symlink

