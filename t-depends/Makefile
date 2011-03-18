TESTS_DEB := pkg-real pkg-depends

include ../Test.mk

test-case:
	# The dependency is not present, fail
	! $(DPKG_INSTALL) pkg-depends.deb
	# Install the real package
	$(DPKG_INSTALL) pkg-real.deb
	# The dependency is present, pass
	$(DPKG_INSTALL) pkg-depends.deb
	# The dependency is removed, fail
	! $(DPKG_PURGE) pkg-real
	# The depending package is removed, pass
	$(DPKG_PURGE) pkg-depends
	# The dependency is removed, pass
	$(DPKG_PURGE) pkg-real

test-clean:
	-$(DPKG_PURGE) pkg-depends
	-$(DPKG_PURGE) pkg-real
