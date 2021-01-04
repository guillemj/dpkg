TESTS_DEB := pkg-normal pkg-depend pkg-disappear

include ../Test.mk

test-case:
	# test disappearing depended package
	$(DPKG_INSTALL) pkg-disappear.deb
	$(DPKG_INSTALL) pkg-depend.deb
	$(DPKG_INSTALL) pkg-normal.deb
	# should not disappear while it's being depended on
	$(call pkg_is_installed,pkg-disappear)
	$(DPKG_PURGE) pkg-depend
	$(DPKG_INSTALL) pkg-normal.deb
	# should have been disappered now
	$(call pkg_is_not_installed,pkg-disappear)

test-clean:
	-$(DPKG_PURGE) pkg-depend
	-$(DPKG_PURGE) pkg-disappear
	$(DPKG_PURGE) pkg-normal

