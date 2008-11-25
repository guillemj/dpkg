TESTS_DEB := pkg-dir pkg-file pkg-symlink-0 pkg-symlink-1

include ../Test.mk

test-case:
	$(DPKG_INSTALL) pkg-dir.deb
	$(DPKG_INSTALL) pkg-symlink-0.deb
	$(DPKG_INSTALL) pkg-file.deb
	$(DPKG_INSTALL) pkg-symlink-1.deb

test-clean:
	$(DPKG_PURGE) pkg-symlink
	$(DPKG_PURGE) pkg-file
	$(DPKG_PURGE) pkg-dir

