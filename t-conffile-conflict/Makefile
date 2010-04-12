TESTS_DEB := pkg-conff-a pkg-conff-b

include ../Test.mk

test-case:
	# test if packages fail on install
	$(DPKG_INSTALL) pkg-conff-a.deb
	! $(DPKG_INSTALL) pkg-conff-b.deb

test-clean:
	-$(DPKG_PURGE) pkg-conff-b
	$(DPKG_PURGE) pkg-conff-a

