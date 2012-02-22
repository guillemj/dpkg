include ../Test.mk

test-case:
	# test building package with bogus control files
	! $(DPKG_BUILD_DEB) pkg-bogus
	
	# build bogus packages
	$(DPKG_BUILD_DEB) --nocheck pkg-bogus
	
	# test installing packages with bogus control files
	! $(DPKG_INSTALL) pkg-bogus.deb
	test "`$(PKG_STATUS) pkg-bogus`" = ""

test-clean:
	rm -f pkg-bogus.deb
