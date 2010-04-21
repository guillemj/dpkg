TESTS_DEB := pkg-conff-original-0 pkg-conff-original-1 pkg-conff-takeover

include ../Test.mk

define VERIFY
test "`$(PKG_STATUS) pkg-conff-original`" = "install ok installed"
test "`$(PKG_STATUS) pkg-conff-takeover`" = "install ok installed"
test "`$(DPKG_QUERY) -S /test-conffile`" = "pkg-conff-takeover: /test-conffile"
cmp ref-conffile /test-conffile
endef

test-case:
	# Install packages
	$(DPKG_INSTALL) pkg-conff-original-1.deb
	$(DPKG_INSTALL) pkg-conff-takeover.deb
	# Downgrade to test versioned Replaces
	$(DPKG_INSTALL) pkg-conff-original-0.deb
	$(VERIFY)
	$(DPKG_PURGE) pkg-conff-original pkg-conff-takeover

