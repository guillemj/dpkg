TESTS_DEB := pkg-file-original pkg-file-takeover

include ../Test.mk

test-case: test-two-run-ordered test-one-run-ordered \
           test-two-run-reverse test-one-run-reverse

define VERIFY
test "`$(PKG_STATUS) pkg-file-original`" = "unknown ok not-installed"
test "`$(PKG_STATUS) pkg-file-takeover`" = "install ok installed"
test "`$(DPKG_QUERY) -S /test-file`" = "pkg-file-takeover: /test-file"
cmp ref-file /test-file
endef

test-two-run-ordered:
	# test-two-run-ordered
	$(DPKG_INSTALL) pkg-file-original.deb
	$(DPKG_INSTALL) pkg-file-takeover.deb
	$(VERIFY)
	$(DPKG_PURGE) pkg-file-original pkg-file-takeover

test-one-run-ordered:
	# test-one-run-ordered
	$(DPKG_INSTALL) pkg-file-original.deb pkg-file-takeover.deb
	$(VERIFY)
	$(DPKG_PURGE) pkg-file-original pkg-file-takeover

test-two-run-reverse:
	# test-two-run-reverse
	$(DPKG_INSTALL) pkg-file-takeover.deb
	$(DPKG_INSTALL) pkg-file-original.deb
	# FIXME: FAIL # $$(VERIFY)
	$(BEROOT) rm -f /test-file
	$(DPKG_PURGE) pkg-file-original pkg-file-takeover

test-one-run-reverse:
	# test-one-run-reverse
	$(DPKG_INSTALL) pkg-file-takeover.deb pkg-file-original.deb
	# FIXME: FAIL # $$(VERIFY)
	$(BEROOT) rm -f /test-file
	$(DPKG_PURGE) pkg-file-original pkg-file-takeover

