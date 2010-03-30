TESTS_DEB := pkg-normal pkg-disappear-0 pkg-disappear-1

include ../Test.mk

test-case:
	$(DPKG_INSTALL) pkg-disappear-0.deb
	# test that an upgraded empty package does not get disappeared
	$(DPKG_INSTALL) pkg-disappear-1.deb
	test "`$(PKG_STATUS) pkg-disappear`" = "install ok installed"
	$(DPKG_INSTALL) pkg-normal.deb
	test "`$(PKG_STATUS) pkg-normal`" = "install ok installed"

test-clean:
	$(DPKG_PURGE) pkg-disappear
	$(DPKG_PURGE) pkg-normal

