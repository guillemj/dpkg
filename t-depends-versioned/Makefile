TESTS_DEB := \
	pkg-version-1 pkg-version-2 pkg-version-3 pkg-depends-eq \
	pkg-depends-lt pkg-depends-le pkg-depends-ge pkg-depends-gt

include ../Test.mk

define purge-all
$(DPKG_PURGE) pkg-depends-lt
$(DPKG_PURGE) pkg-depends-le
$(DPKG_PURGE) pkg-depends-eq
$(DPKG_PURGE) pkg-depends-ge
$(DPKG_PURGE) pkg-depends-gt
endef

test-case:
	$(purge-all)

	# The dependency is not present, fail
	! $(DPKG_INSTALL) pkg-depends-lt.deb
	! $(DPKG_INSTALL) pkg-depends-le.deb
	! $(DPKG_INSTALL) pkg-depends-eq.deb
	! $(DPKG_INSTALL) pkg-depends-ge.deb
	! $(DPKG_INSTALL) pkg-depends-gt.deb

	# Install the package v1
	$(DPKG_INSTALL) pkg-version-1.deb
	$(DPKG_INSTALL) pkg-depends-lt.deb
	$(DPKG_INSTALL) pkg-depends-le.deb
	! $(DPKG_INSTALL) pkg-depends-eq.deb
	! $(DPKG_INSTALL) pkg-depends-ge.deb
	! $(DPKG_INSTALL) pkg-depends-gt.deb

	$(purge-all)

	# Install the package v2
	$(DPKG_INSTALL) pkg-version-2.deb
	! $(DPKG_INSTALL) pkg-depends-lt.deb
	$(DPKG_INSTALL) pkg-depends-le.deb
	$(DPKG_INSTALL) pkg-depends-eq.deb
	$(DPKG_INSTALL) pkg-depends-ge.deb
	! $(DPKG_INSTALL) pkg-depends-gt.deb

	$(purge-all)

	# Install the package v3
	$(DPKG_INSTALL) pkg-version-3.deb
	! $(DPKG_INSTALL) pkg-depends-lt.deb
	! $(DPKG_INSTALL) pkg-depends-le.deb
	! $(DPKG_INSTALL) pkg-depends-eq.deb
	$(DPKG_INSTALL) pkg-depends-ge.deb
	$(DPKG_INSTALL) pkg-depends-gt.deb

	$(purge-all)

test-clean:
	-$(DPKG_PURGE) pkg-depends-lt
	-$(DPKG_PURGE) pkg-depends-le
	-$(DPKG_PURGE) pkg-depends-eq
	-$(DPKG_PURGE) pkg-depends-ge
	-$(DPKG_PURGE) pkg-depends-gt
	-$(DPKG_PURGE) pkg-version
