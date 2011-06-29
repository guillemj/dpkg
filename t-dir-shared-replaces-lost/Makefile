TESTS_DEB := pkg-dir-original pkg-dir-takeover

include ../Test.mk

test-case: test-ordered test-reverse

define VERIFY
test "`$(PKG_STATUS) pkg-dir-original`" = "install ok installed"
test "`$(PKG_STATUS) pkg-dir-takeover`" = "install ok installed"
test -d /test-dir
test "`$(DPKG_QUERY) -S /test-dir/test-original`" = "pkg-dir-original: /test-dir/test-original"
test "`$(DPKG_QUERY) -S /test-dir/test-takeover`" = "pkg-dir-takeover: /test-dir/test-takeover"
endef

test-ordered:
	# test-ordered
	$(DPKG_INSTALL) pkg-dir-original.deb
	$(BEROOT) rm -rf /test-dir
	$(DPKG_INSTALL) pkg-dir-takeover.deb
	$(VERIFY)
	$(DPKG_PURGE) pkg-dir-original pkg-dir-takeover

test-reverse:
	# test-reverse
	$(DPKG_INSTALL) pkg-dir-takeover.deb
	$(BEROOT) rm -rf /test-dir
	$(DPKG_INSTALL) pkg-dir-original.deb
	$(VERIFY)
	$(DPKG_PURGE) pkg-dir-original pkg-dir-takeover

test-clean:
	-$(DPKG_PURGE) pkg-dir-original pkg-dir-takeover
