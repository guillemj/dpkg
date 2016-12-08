TESTS_DEB := pkg-conff-forcemiss-0 pkg-conff-forcemiss-1

include ../Test.mk

test-case:
	# Test if we get the new conffile after a missing one.
	$(DPKG_INSTALL) pkg-conff-forcemiss-0.deb
	$(BEROOT) rm /test-conffile
	$(DPKG_INSTALL) pkg-conff-forcemiss-1.deb
	! test -f /test-conffile
	$(DPKG_INSTALL) --force-confmiss pkg-conff-forcemiss-1.deb
	cmp ref-conffile /test-conffile
	$(DPKG_PURGE) pkg-conff-forcemiss

test-clean:
	$(DPKG_PURGE) pkg-conff-forcemiss
