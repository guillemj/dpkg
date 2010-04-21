TESTS_DEB := pkg-failinst-failrm

include ../Test.mk

test-case:
	-$(DPKG_INSTALL) pkg-failinst-failrm.deb
	test "`$(PKG_STATUS) pkg-failinst-failrm`" = "install ok half-configured"

test-clean:
	# FIXME: The purge will fail, need --force-scripts. We'll just remove
	#        the failing script for now.
	$(DPKG_QUERY) --control-path pkg-failinst-failrm | xargs $(BEROOT) rm
	$(DPKG_PURGE) pkg-failinst-failrm

