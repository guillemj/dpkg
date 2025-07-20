TESTS_DEB := pkg-abort-notice-0 pkg-abort-notice-1 pkg-abort-notice-2

include ../Test.mk

test-case:
	$(DPKG_INSTALL) pkg-abort-notice-0.deb
	-$(DPKG_INSTALL) pkg-abort-notice-1.deb
	#$(call pkg_status_is,pkg-failinst-failrm,install ok half-configured)

test-clean:
	# Upgrade to a working version to allow the purge.
	-$(DPKG_INSTALL) pkg-abort-notice-2.deb
	$(DPKG_PURGE) pkg-abort-notice
