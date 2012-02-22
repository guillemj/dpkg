include ../Test.mk

test-case:
	# test building package with bogus control files
	! $(DPKG_BUILD_DEB) pkg-bogus-colon
	! $(DPKG_BUILD_DEB) pkg-bogus-blank
	
	# build bogus packages
	$(DPKG_BUILD_DEB) --nocheck pkg-bogus-colon
	$(DPKG_BUILD_DEB) --nocheck pkg-bogus-blank
	
	# test installing packages with bogus control files
	! $(DPKG_INSTALL) pkg-bogus-colon.deb
	test "`$(PKG_STATUS) pkg-bogus-colon`" = ""
	! $(DPKG_INSTALL) pkg-bogus-blank.deb
	test "`$(PKG_STATUS) pkg-bogus-blank`" = ""

test-clean:
	rm -f pkg-bogus-colon.deb
	rm -f pkg-bogus-blank.deb
