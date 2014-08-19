TESTS_DEB := pkg-dir-real pkg-dir-symlink-0 pkg-dir-symlink-1

include ../Test.mk

test-case:
	$(DPKG_INSTALL) pkg-dir-real.deb

	$(DPKG_INSTALL) pkg-dir-symlink-0.deb
	test -h /test-path/test-symlink

	$(DPKG_INSTALL) pkg-dir-symlink-1.deb
	! test -h /test-path/test-symlink
	test -d /test-path/test-symlink

	$(DPKG_PURGE) pkg-dir-symlink
	! test -e /test-path/test-symlink

	$(DPKG_PURGE) pkg-dir-real

test-clean:
	$(DPKG_PURGE) pkg-dir-symlink
	$(DPKG_PURGE) pkg-dir-real
