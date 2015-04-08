include ../Test.mk

test-case:
	# This should produce a warning
	LC_ALL=C $(DPKG_BUILD_DEB) pkg-conff-dupe 2>&1 | \
	  grep "warning: conffile name '.*' is duplicated" && echo Pass || \
	  ( echo Fail: missing warning in output && exit 1 )

ifdef DPKG_HAS_STRICT_CONFFILE_PARSER
	# Conffiles need a final newline to guarantee there's been no
	# accidental file truncation.
	! $(DPKG_BUILD_DEB) pkg-conff-noel
else
	LC_ALL=C $(DPKG_BUILD_DEB) pkg-conff-noel 2>&1 | \
	  grep "warning: conffile name '.*' is too long" && echo Pass || \
	  ( echo Fail: missing warning in output && exit 1 )
endif

test-clean:
	$(RM) pkg-conff-dupe.deb
	$(RM) pkg-conff-noel.deb
