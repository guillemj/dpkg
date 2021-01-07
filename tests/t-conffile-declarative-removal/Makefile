TESTS_DEB := pkg-conffile-v1 pkg-conffile-v2

include ../Test.mk

test-case:
	# Conffile marked for removal but present, cannot be installed.
	$(DPKG_BUILD_DEB) --nocheck pkg-conffile-removal-present
	! $(DPKG_INSTALL) pkg-conffile-removal-present.deb
	$(call pkg_is_not_installed,pkg-conffile-removal-present)
	$(DPKG_PURGE) pkg-conffile-removal-present

	# Unmodified case.
	$(DPKG_INSTALL) pkg-conffile-v1.deb
	test -f "$(DPKG_INSTDIR)/test-dir/test-conffile-to-be-removed"
	$(DPKG_INSTALL) pkg-conffile-v2.deb
	test ! -f "$(DPKG_INSTDIR)/test-dir/test-conffile-to-be-removed"

	# Reset.
	$(DPKG_PURGE) pkg-conffile
	test ! -f "$(DPKG_INSTDIR)/test-dir/test-conffile-to-be-removed"

	# Unmodified case; but force it to happen via two invocations.
	$(DPKG_INSTALL) pkg-conffile-v1.deb
	test -f "$(DPKG_INSTDIR)/test-dir/test-conffile-to-be-removed"
	$(DPKG_UNPACK) pkg-conffile-v2.deb
	# The old file is still present when unpacked.
	test -f "$(DPKG_INSTDIR)/test-dir/test-conffile-to-be-removed"
	test ! -f "$(DPKG_INSTDIR)/test-dir/test-conffile-to-be-removed.dpkg-old"
	$(DPKG_CONFIGURE) pkg-conffile
	# After configure, the file is removed.
	test ! -f "$(DPKG_INSTDIR)/test-dir/test-conffile-to-be-removed"
	test ! -f "$(DPKG_INSTDIR)/test-dir/test-conffile-to-be-removed.dpkg-old"

	# Reset.
	$(DPKG_PURGE) pkg-conffile
	test ! -f "$(DPKG_INSTDIR)/test-dir/test-conffile-to-be-removed"

	# Modified; should store .dpkg-old.
	$(DPKG_INSTALL) pkg-conffile-v1.deb
	test -f "$(DPKG_INSTDIR)/test-dir/test-conffile-to-be-removed"
	echo "modify this" >"$(DPKG_INSTDIR)/test-dir/test-conffile-to-be-removed"
	$(DPKG_INSTALL) pkg-conffile-v2.deb
	test ! -f "$(DPKG_INSTDIR)/test-dir/test-conffile-to-be-removed"
	test -f "$(DPKG_INSTDIR)/test-dir/test-conffile-to-be-removed.dpkg-old"

test-clean:
	$(DPKG_PURGE) pkg-conffile-removal-present
	$(DPKG_PURGE) pkg-conffile
	$(BEROOT) $(RM) -rf "$(DPKG_INSTDIR)/test-dir"
