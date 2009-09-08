TESTS_DEB := pkg-conff-forcenew-0 pkg-conff-forcenew-1

include ../Test.mk

test-case:
	$(DPKG_INSTALL) pkg-conff-forcenew-0.deb
	# test if we get the new conffile
	$(DPKG_INSTALL) --force-confnew pkg-conff-forcenew-1.deb
	cmp ref-conffile /test-conffile

test-clean:
	$(DPKG_PURGE) pkg-conff-forcenew

