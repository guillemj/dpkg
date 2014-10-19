TESTS_DEB := \
	pkg-depends-a pkg-depends-b \
	pkg-files-0 pkg-files-1 \
	pkg-trigger

include ../Test.mk

test-case:
	# Now provoke the trigger cycle
	$(DPKG_INSTALL) pkg-depends-a.deb pkg-files-0.deb \
	                pkg-depends-b.deb pkg-trigger.deb
	$(DPKG_UNPACK) pkg-files-1.deb
	$(BEROOT) $(DPKG) --configure --pending

	# Make sure everything is left in a correct state.
	$(call pkg_is_installed,pkg-files)
	$(call pkg_is_installed,pkg-depends-a)
	$(call pkg_is_installed,pkg-depends-b)
	$(call pkg_is_installed,pkg-trigger)

	# Cleanup.
	$(DPKG_PURGE) pkg-trigger pkg-files pkg-depends-a pkg-depends-b

test-clean:
	-$(DPKG_PURGE) pkg-trigger pkg-files pkg-depends-a pkg-depends-b
