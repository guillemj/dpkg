TESTS_DEB := pkg-conff-obsolete-0 pkg-conff-obsolete-1

include ../Test.mk

test-case:
	$(DPKG_INSTALL) pkg-conff-obsolete-0.deb
	$(DPKG_INSTALL) pkg-conff-obsolete-1.deb
	test -f /test-conffile
	$(DPKG_PURGE) pkg-conff-obsolete
	test ! -f /test-conffile

test-clean:

