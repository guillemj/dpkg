TESTS_DEB := \
	pkg-dir-conffile-0 pkg-dir-conffile-1 \
	pkg-dir-file-other pkg-dir-symlink-int-0 pkg-dir-symlink-int-1 \
	pkg-dir-file-moved pkg-dir-symlink-ext-0 pkg-dir-symlink-ext-1

include ../Test.mk

test-case:
	# Cannot switch a directory containing conffiles
	$(DPKG_INSTALL) pkg-dir-conffile-0.deb
	test -d /test-path
	! $(DPKG_INSTALL) pkg-dir-conffile-1.deb
	test -d /test-path
	$(DPKG_PURGE) pkg-dir-conffile

	# Cannot switch a directory containing files owned by another package
	$(DPKG_INSTALL) pkg-dir-file-other.deb
	$(DPKG_INSTALL) pkg-dir-symlink-int-0.deb
	test -d /test-path
	! test -h /test-path
	! $(DPKG_INSTALL) pkg-dir-symlink-int-1.deb
	test -d /test-path
	! test -h /test-path
	$(DPKG_PURGE) pkg-dir-symlink-int
	$(DPKG_PURGE) pkg-dir-file-other

	# Cannot switch a directory containing local files
	$(DPKG_INSTALL) pkg-dir-symlink-int-0.deb
	test -d /test-path
	! test -h /test-path
	touch '/test-path/local file'
	! $(DPKG_INSTALL) pkg-dir-symlink-int-1.deb
	test -d /test-path
	! test -h /test-path
	rm '/test-path/local file'
	$(DPKG_PURGE) pkg-dir-symlink-int

	#
	# Otherwise allow the switch
	#

	# Switch a directory to a symlink, contents moved within the package,
	# with intermediate full installs.
	$(DPKG_INSTALL) pkg-dir-symlink-int-0.deb
	test -d /test-path
	! test -h /test-path
	$(DPKG_INSTALL) pkg-dir-symlink-int-1.deb
	test -h /test-path
	$(DPKG_PURGE) pkg-dir-symlink-int
	! test -e /test-path

	# Switch a directory to a symlink, contents moved within the package,
	# with full install, upgrade with upack and configure.
	$(DPKG_INSTALL) pkg-dir-symlink-int-0.deb
	! test -h /test-path
	test -d /test-path
	$(DPKG_UNPACK) pkg-dir-symlink-int-1.deb
	! test -h /test-path
	test -d /test-path
	$(DPKG_CONFIGURE) pkg-dir-symlink-int
	test -h /test-path
	$(DPKG_PURGE) pkg-dir-symlink-int
	! test -e /test-path

	# Switch a directory to a symlink, contents moved within the package,
	# with two unpacks and configure.
	$(DPKG_UNPACK) pkg-dir-symlink-int-0.deb
	! test -h /test-path
	test -d /test-path
	$(DPKG_UNPACK) pkg-dir-symlink-int-1.deb
	! test -h /test-path
	test -d /test-path
	$(DPKG_CONFIGURE) pkg-dir-symlink-int
	test -h /test-path
	$(DPKG_PURGE) pkg-dir-symlink-int
	! test -e /test-path

	# Switch a directory to a symlink, contents moved to another package,
	# with intermediate full installs.
	$(DPKG_INSTALL) pkg-dir-symlink-ext-0.deb
	test -d /test-path
	$(DPKG_INSTALL) pkg-dir-file-moved.deb
	test -d /test-path
	test -d /test-dir
	$(DPKG_INSTALL) pkg-dir-symlink-ext-1.deb
	test -h /test-path
	test -d /test-path
	test "`readlink -f /test-path`" = "/test-dir"
	! test -h /test-dir
	test -d /test-dir
	test -f /test-dir/file-normal
	$(DPKG_PURGE) pkg-dir-symlink-ext
	$(DPKG_PURGE) pkg-dir-file-moved

	# Switch a directory to a symlink, contents moved to another package,
	# with full installs, upgrade with upack and configure.
	$(DPKG_INSTALL) pkg-dir-symlink-ext-0.deb
	test -d /test-path
	$(DPKG_INSTALL) pkg-dir-file-moved.deb
	test -d /test-path
	test -d /test-dir
	$(DPKG_UNPACK) pkg-dir-symlink-ext-1.deb
	test -d /test-path
	test -d /test-dir
	$(DPKG_CONFIGURE) -a
	test -h /test-path
	test -d /test-path
	test "`readlink -f /test-path`" = "/test-dir"
	! test -h /test-dir
	test -d /test-dir
	test -f /test-dir/file-normal
	$(DPKG_PURGE) pkg-dir-symlink-ext
	$(DPKG_PURGE) pkg-dir-file-moved

	# Switch a directory to a symlink, contents moved to another package,
	# with three unpacks and configure.
	$(DPKG_UNPACK) pkg-dir-symlink-ext-0.deb
	test -d /test-path
	$(DPKG_UNPACK) pkg-dir-file-moved.deb
	test -d /test-path
	test -d /test-dir
	$(DPKG_UNPACK) pkg-dir-symlink-ext-1.deb
	test -d /test-path
	test -d /test-dir
	$(DPKG_CONFIGURE) -a
	test -h /test-path
	test -d /test-path
	test "`readlink -f /test-path`" = "/test-dir"
	! test -h /test-dir
	test -d /test-dir
	test -f /test-dir/file-normal
	$(DPKG_PURGE) pkg-dir-symlink-ext
	$(DPKG_PURGE) pkg-dir-file-moved

test-clean:
	$(DPKG_PURGE) pkg-dir-conffile
	$(DPKG_PURGE) pkg-dir-symlink-int
	$(DPKG_PURGE) pkg-dir-symlink-ext
	$(DPKG_PURGE) pkg-dir-file-other
	$(DPKG_PURGE) pkg-dir-file-moved
