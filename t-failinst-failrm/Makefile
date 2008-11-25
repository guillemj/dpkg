TESTS_DEB := pkg-failinst-failrm

include ../Test.mk

test-case:
	-$(DPKG_INSTALL) pkg-failinst-failrm.deb
	test "`$(PKG_STATUS) pkg-failinst-failrm`" eq "install ok half-configured"

test-clean:
	# FIXME: this will fail, need --force-scripts
	-$(DPKG_PURGE) pkg-dbg-dir

