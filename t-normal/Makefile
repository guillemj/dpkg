TESTS_DEB := pkg-normal

include ../Test.mk

test-case:
	# test normal working packages
	$(DPKG_INSTALL) pkg-normal.deb
	test "`$(PKG_STATUS) pkg-normal`" = "install ok installed"

test-clean:
	$(DPKG_PURGE) pkg-normal

