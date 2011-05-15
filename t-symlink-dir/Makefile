TESTS_DEB := pkg-dir-real pkg-dir-symlink-0 pkg-dir-symlink-1 pkg-file

include ../Test.mk

test-case:
	$(DPKG_INSTALL) pkg-dir-real.deb
	$(DPKG_INSTALL) pkg-dir-symlink-0.deb
	$(DPKG_INSTALL) pkg-file.deb
	$(DPKG_INSTALL) pkg-dir-symlink-1.deb
	
	$(DPKG_PURGE) pkg-dir-symlink
	$(DPKG_PURGE) pkg-file
	$(DPKG_PURGE) pkg-dir-real
	
	test ! -L /test-symlink

test-clean:
	$(DPKG_PURGE) pkg-dir-symlink
	$(DPKG_PURGE) pkg-file
	$(DPKG_PURGE) pkg-dir-real
	$(BEROOT) $(RM) -f /test-symlink
