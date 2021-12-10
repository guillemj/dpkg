## Process this file with automake to produce Makefile.in

EXTRA_DIST =

EXTRA_DIST += $(srcdir)/package.m4

TESTSUITE_AT = $(srcdir)/testsuite.at
TESTSUITE_AT += $(srcdir)/local.at
TESTSUITE_AT += $(srcdir)/deb-format.at
TESTSUITE_AT += $(srcdir)/deb-fields.at
TESTSUITE_AT += $(srcdir)/deb-content.at
TESTSUITE_AT += $(srcdir)/deb-split.at
EXTRA_DIST += $(TESTSUITE_AT)

TESTSUITE = $(srcdir)/testsuite
EXTRA_DIST += $(TESTSUITE)

DISTCLEANFILES =

include $(top_srcdir)/build-aux/autotest.am

check-local: autotest-check

installcheck-local: autotest-installcheck

clean-local: autotest-clean
