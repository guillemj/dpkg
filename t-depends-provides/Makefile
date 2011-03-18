TESTS_DEB := pkg-provides pkg-depends

include ../Test.mk

test-case:
	# The provided dependency is not present, fail
	! $(DPKG_INSTALL) pkg-depends.deb
	# Install the providing package
	$(DPKG_INSTALL) pkg-provides.deb
	# The provided dependency is present, pass
	$(DPKG_INSTALL) pkg-depends.deb
	# The provided dependency is removed, fail
	! $(DPKG_PURGE) pkg-provides
	# The depending package is removed, pass
	$(DPKG_PURGE) pkg-depends
	# The provided dependency is removed, pass
	$(DPKG_PURGE) pkg-provides

test-clean:
	-$(DPKG_PURGE) pkg-depends
	-$(DPKG_PURGE) pkg-provides
