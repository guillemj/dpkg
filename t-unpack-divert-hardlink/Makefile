PKG := pkg-hardlink

TESTS_DEB := $(PKG)

include ../Test.mk

$(PKG)/test-hardlink:
	link $(PKG)/test-file $@

build-hook: $(PKG)/test-hardlink

clean-hook:
	rm -f $(PKG)/test-hardlink

test-case:
	$(DPKG_DIVERT) --add /test-file
	$(DPKG_DIVERT) --add /test-hardlink
	# test if unpack can divert a hardlink
	$(DPKG_INSTALL) pkg-hardlink.deb
	test "`$(PKG_STATUS) pkg-hardlink`" = "install ok installed"
	test -f /test-file.distrib
	test -f /test-hardlink.distrib
	cmp /test-file.distrib /test-hardlink.distrib
	test "`stat -c '%i' /test-file.distrib`" = \
	     "`stat -c '%i' /test-hardlink.distrib`"

test-clean:
	$(DPKG_PURGE) pkg-hardlink
	$(DPKG_DIVERT) --remove /test-file
	$(DPKG_DIVERT) --remove /test-hardlink
