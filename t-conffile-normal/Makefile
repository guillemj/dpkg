TESTS_DEB := pkg-conffile

include ../Test.mk

test-case:
	$(DPKG_INSTALL) pkg-conffile.deb
	test -f /test-dir/test-conffile
	$(DPKG_REMOVE) pkg-conffile
	$(DPKG_PURGE) pkg-conffile
	test ! -f /test-dir/test-conffile
	test ! -d /test-dir

test-clean:
	$(DPKG_PURGE) pkg-conffile
	$(BEROOT) $(RM) -rf /test-dir
