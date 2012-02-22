include ../Test.mk

test-case:
	# test building package with bogus control files
	! $(DPKG_BUILD_DEB) pkg-bogus-colon
	
	# build bogus packages
	$(DPKG_BUILD_DEB) --nocheck pkg-bogus-colon
	
	# test installing packages with bogus control files
	! $(DPKG_INSTALL) pkg-bogus-colon.deb
	test "`$(PKG_STATUS) pkg-bogus-colon`" = ""

test-clean:
	rm -f pkg-bogus-colon.deb
