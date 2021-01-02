include ../Test.mk

test-case:
	# This should produce a warning
	LC_ALL=C $(DPKG_BUILD_DEB) pkg-conff-duped 2>&1 | \
	  grep "warning: conffile name '.*' is duplicated" && echo Pass || \
	  ( echo Fail: missing warning in output && exit 1 )

	# Conffiles need a final newline to guarantee there's been no
	# accidental file truncation.
	! $(DPKG_BUILD_DEB) pkg-conff-noeol

	# Conffiles must use absolute pathnames.
	! $(DPKG_BUILD_DEB) pkg-conff-noabs

test-clean:
	$(RM) pkg-conff-duped.deb
	$(RM) pkg-conff-noeol.deb
	$(RM) pkg-conff-noabs.deb
