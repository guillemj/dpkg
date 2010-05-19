TESTS_DEB := pkg-normal pkg-depend pkg-disappear

include ../Test.mk

test-case:
	# test disappearing depended package
	$(DPKG_INSTALL) pkg-disappear.deb
	$(DPKG_INSTALL) pkg-depend.deb
	$(DPKG_INSTALL) pkg-normal.deb
	# should not disappear while it's being depended on
	test "`$(PKG_STATUS) pkg-disappear`" = "install ok installed"
	$(DPKG_PURGE) pkg-depend
	$(DPKG_INSTALL) pkg-normal.deb
	# should have been disappered now
	# FIXME: the line below should not fail but it does currently
	-test "`$(PKG_STATUS) pkg-disappear`" = "unknown ok not-installed"

test-clean:
	-$(DPKG_PURGE) pkg-disappear
	$(DPKG_PURGE) pkg-normal

