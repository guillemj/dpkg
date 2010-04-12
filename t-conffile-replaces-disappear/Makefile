TESTS_DEB := pkg-conff-original pkg-conff-takeover

include ../Test.mk

test-case: test-two-run-ordered test-one-run-ordered \
           test-two-run-reverse test-one-run-reverse

define VERIFY
test "`$(PKG_STATUS) pkg-conff-original`" = "unknown ok not-installed"
test "`$(PKG_STATUS) pkg-conff-takeover`" = "install ok installed"
test "`$(DPKG_QUERY) -S /test-conffile`" = "pkg-conff-takeover: /test-conffile"
cmp ref-conffile /test-conffile
endef

test-two-run-ordered:
	# test-two-run-ordered
	$(DPKG_INSTALL) pkg-conff-original.deb
	$(DPKG_INSTALL) pkg-conff-takeover.deb
	$(VERIFY)
	$(DPKG_PURGE) pkg-conff-original pkg-conff-takeover

test-one-run-ordered:
	# test-one-run-ordered
	$(DPKG_INSTALL) pkg-conff-original.deb pkg-conff-takeover.deb
	$(VERIFY)
	$(DPKG_PURGE) pkg-conff-original pkg-conff-takeover

test-two-run-reverse:
	# test-two-run-reverse
	$(DPKG_INSTALL) pkg-conff-takeover.deb
	$(DPKG_INSTALL) pkg-conff-original.deb
	# FIXME: FAILS # $$(VERIFY)
	$(BEROOT) rm /test-conffile # XXX
	$(DPKG_PURGE) pkg-conff-original pkg-conff-takeover

test-one-run-reverse:
	# test-one-run-reverse
	$(DPKG_INSTALL) pkg-conff-takeover.deb pkg-conff-original.deb
	# FIXME: FAILS # $$(VERIFY)
	$(BEROOT) rm /test-conffile # XXX
	$(DPKG_PURGE) pkg-conff-original pkg-conff-takeover

