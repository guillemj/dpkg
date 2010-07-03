TESTS_DEB := pkg-conff-forceask-0 pkg-conff-forceask-1

include ../Test.mk

test-case:
	# test if we get the new conffile after a missing one
	$(DPKG_INSTALL) pkg-conff-forceask-0.deb
	$(BEROOT) rm /test-conffile
	$(DPKG_INSTALL) --force-confask --force-confmiss pkg-conff-forceask-1.deb
	cmp ref-conffile /test-conffile
	$(DPKG_PURGE) pkg-conff-forceask
	
	# test if we get the new conffile after a modified one
	$(DPKG_INSTALL) pkg-conff-forceask-0.deb
	$(BEROOT) cp mod-conffile /test-conffile
	$(DPKG_INSTALL) --force-confask --force-confnew pkg-conff-forceask-1.deb
	cmp mod-conffile /test-conffile.dpkg-old
	cmp ref-conffile /test-conffile
	$(DPKG_PURGE) pkg-conff-forceask

test-clean:

