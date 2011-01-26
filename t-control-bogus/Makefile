TESTS_DEB := pkg-bogus

DPKG_DEB_OPTIONS = --nocheck

include ../Test.mk

test-case:
	# test handling of package with bogus control file
	! $(DPKG_INSTALL) pkg-bogus.deb
	test "`$(PKG_STATUS) pkg-bogus`" = ""
