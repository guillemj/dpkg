TESTS_DEB := pkg-depends-0 pkg-depends-1 pkg-files pkg-trigger

include ../Test.mk

test-case:
	$(DPKG_INSTALL) pkg-depends-0.deb
	$(DPKG_INSTALL) pkg-trigger.deb
	$(DPKG_INSTALL) pkg-files.deb
	$(DPKG_UNPACK) pkg-depends-1.deb
	$(DPKG_UNPACK) pkg-files.deb
	$(DPKG_CONFIGURE) --pending

	# Make sure everything is left in a correct state.
	$(call pkg_is_installed,pkg-files)
	$(call pkg_is_installed,pkg-depends)
	$(call pkg_is_installed,pkg-trigger)

	# Cleanup.
	$(DPKG_PURGE) pkg-files
	$(DPKG_PURGE) pkg-trigger
	$(DPKG_PURGE) pkg-depends

test-clean:
	-$(DPKG_PURGE) pkg-depends pkg-files pkg-trigger
