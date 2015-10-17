include ../Test.mk

test-case:
	# cannot create package with newline
	! $(DPKG_DEB) -b pkg-newline

test-clean:
	$(RM) pkg-*.deb
