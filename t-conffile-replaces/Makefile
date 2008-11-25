TESTS_DEB := pkg-conff-original pkg-conff-takeover

include ../Test.mk

test-case:
	# Fail
	# $(DPKG_INSTALL) pkg-conff-takeover.deb pkg-conff-original.deb
	# Fail
	$(DPKG_INSTALL) pkg-conff-takeover.deb
	$(DPKG_INSTALL) pkg-conff-original.deb
	# Pass
	# $(DPKG_INSTALL) pkg-conff-original.deb pkg-conff-takeover.deb
	# Pass
	# $(DPKG_INSTALL) pkg-conff-original.deb
	# $(DPKG_INSTALL) pkg-conff-takeover.deb
	
	$(DPKG_PURGE) pkg-conff-original pkg-conff-takeover

