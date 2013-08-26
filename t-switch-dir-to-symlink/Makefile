TESTS_DEB := pkg-dir-real pkg-dir-symlink-0 pkg-dir-symlink-1 \
             pkg-dir-conffile-0 pkg-dir-conffile-1

include ../Test.mk

test-case:
	# Cannot switch a directory containing conffiles
	$(DPKG_INSTALL) pkg-dir-conffile-0.deb
	test -d /test-path
	! $(DPKG_INSTALL) pkg-dir-conffile-1.deb
	test -d /test-path
	$(DPKG_PURGE) pkg-dir-conffile

	# Cannot switch a directory containing files owned by another package
	$(DPKG_INSTALL) pkg-dir-real.deb
	$(DPKG_INSTALL) pkg-dir-symlink-0.deb
	test -d /test-path
	! test -h /test-path
	! $(DPKG_INSTALL) pkg-dir-symlink-1.deb
	test -d /test-path
	! test -h /test-path
	$(DPKG_PURGE) pkg-dir-symlink
	$(DPKG_PURGE) pkg-dir-real

	# Cannot switch a directory containing local files
	$(DPKG_INSTALL) pkg-dir-symlink-0.deb
	test -d /test-path
	! test -h /test-path
	touch '/test-path/local file'
	! $(DPKG_INSTALL) pkg-dir-symlink-1.deb
	test -d /test-path
	! test -h /test-path
	rm '/test-path/local file'
	$(DPKG_PURGE) pkg-dir-symlink

	# Otherwise allow the switch
	$(DPKG_INSTALL) pkg-dir-symlink-0.deb
	test -d /test-path
	! test -h /test-path
	$(DPKG_INSTALL) pkg-dir-symlink-1.deb
	test -h /test-path
	$(DPKG_PURGE) pkg-dir-symlink
	! test -e /test-path

test-clean:
	$(DPKG_PURGE) pkg-dir-conffile
	$(DPKG_PURGE) pkg-dir-symlink
	$(DPKG_PURGE) pkg-dir-real
