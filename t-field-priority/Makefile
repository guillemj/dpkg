TESTS_DEB := pkg-priority

include ../Test.mk

test-case:
	# test for unknown priority values
	$(DPKG_INSTALL) pkg-priority.deb
	test "`$(PKG_STATUS) pkg-priority`" = "install ok installed"
	test "`$(DPKG_QUERY) -f '$${Priority}' -W pkg-priority`" = \
	     "value not known"

test-clean:
	$(DPKG_PURGE) pkg-priority
