TESTS_DEB := pkg-file-original pkg-file-takeover

include ../Test.mk

TEST_CASES += test-two-run-ordered
TEST_CASES += test-one-run-ordered
TEST_CASES += test-two-run-reverse
TEST_CASES += test-one-run-reverse

test-case: $(TEST_CASES)

define VERIFY
test "`$(PKG_STATUS) pkg-file-takeover`" = "install ok installed"
test "`$(DPKG_QUERY) -S /test-file`" = "pkg-file-takeover: /test-file"
cmp ref-file /test-file
endef

test-two-run-ordered:
	# test-two-run-ordered
	$(DPKG_INSTALL) pkg-file-original.deb
	$(DPKG_INSTALL) pkg-file-takeover.deb
	test "`$(PKG_STATUS) pkg-file-original`" = "unknown ok not-installed"
	$(VERIFY)
	$(DPKG_PURGE) pkg-file-original pkg-file-takeover
	test ! -f /test-file

test-one-run-ordered:
	# test-one-run-ordered
	$(DPKG_INSTALL) pkg-file-original.deb pkg-file-takeover.deb
	test "`$(PKG_STATUS) pkg-file-original`" = "unknown ok not-installed"
	$(VERIFY)
	$(DPKG_PURGE) pkg-file-original pkg-file-takeover
	test ! -f /test-file

test-two-run-reverse:
	# test-two-run-reverse
	$(DPKG_INSTALL) pkg-file-takeover.deb
	$(DPKG_INSTALL) pkg-file-original.deb
	test "`$(PKG_STATUS) pkg-file-original`" = "install ok installed"
	$(VERIFY)
	$(DPKG_PURGE) pkg-file-original pkg-file-takeover
	test ! -f /test-file

test-one-run-reverse:
	# test-one-run-reverse
	$(DPKG_INSTALL) pkg-file-takeover.deb pkg-file-original.deb
	test "`$(PKG_STATUS) pkg-file-original`" = "install ok installed"
	$(VERIFY)
	$(DPKG_PURGE) pkg-file-original pkg-file-takeover
	test ! -f /test-file

test-clean:
	$(DPKG_PURGE) pkg-file-original pkg-file-takeover
