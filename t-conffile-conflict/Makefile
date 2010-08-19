TESTS_DEB := pkg-conff-a pkg-conff-b pkg-conff-c

include ../Test.mk

test-case: test-conflict-installed-implicit test-conflict-removed-implicit \
           test-conflict-removed-explicit

test-conflict-installed-implicit:
	# test if packages fail on install due to conflicting conffile
	$(DPKG_INSTALL) pkg-conff-a.deb
	! $(DPKG_INSTALL) pkg-conff-b.deb
	-$(DPKG_PURGE) pkg-conff-b
	$(DPKG_PURGE) pkg-conff-a

test-conflict-removed-implicit:
	# test that conffile of removed package can be taken over
	$(DPKG_INSTALL) pkg-conff-a.deb
	$(DPKG_REMOVE) pkg-conff-a
	$(DPKG_INSTALL) pkg-conff-b.deb
	# Veriy the new conffile has been installed
	grep -q pkg-conff-b /test-conffile
	# Verify it's kept after purge of old package
	$(DPKG_PURGE) pkg-conff-a
	test -e /test-conffile
	$(DPKG_PURGE) pkg-conff-b

test-conflict-removed-explicit:
	# test that conffile of removed package can be taken over even if
	# the new package is conflicting with the old one
	$(DPKG_INSTALL) pkg-conff-a.deb
	$(DPKG_REMOVE) pkg-conff-a
	$(DPKG_INSTALL) pkg-conff-c.deb
	# Veriy the new conffile has been installed
	grep -q pkg-conff-c /test-conffile
	# Verify it's kept after purge of old package
	$(DPKG_PURGE) pkg-conff-a
	test -e /test-conffile
	$(DPKG_PURGE) pkg-conff-c

test-clean:
	-$(DPKG_PURGE) pkg-conff-a pkg-conff-b pkg-conff-c
