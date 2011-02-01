TESTS_DEB := pkg-no-arch

include ../Test.mk

test-case:
	# test handling of package without the Architecture field
	! $(DPKG_INSTALL) pkg-no-arch.deb
	$(call is_not_installed,pkg-no-arch)
	# these ancient/bogus packages need to be forced now
	$(DPKG_INSTALL) --force-architecture pkg-no-arch.deb
	$(call is_installed,pkg-no-arch)
	! $(call stdout_has,$(DPKG_QUERY) --status pkg-no-arch,^Architecture:)
	$(DPKG_PURGE) pkg-no-arch
