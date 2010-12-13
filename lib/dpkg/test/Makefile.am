## Process this file with automake to produce Makefile.in

AM_CPPFLAGS = \
	-idirafter $(top_srcdir)/lib/compat \
	-I$(top_builddir) \
	-I$(top_srcdir)/lib
LDADD = ../libdpkg.a


# The tests are sorted in order of increasing complexity.
check_PROGRAMS = \
	t-test \
	t-macros \
	t-string \
	t-buffer \
	t-path \
	t-command \
	t-varbuf \
	t-ar \
	t-version \
	t-pkginfo \
	t-pkg-list \
	t-pkg-queue

TESTS = $(check_PROGRAMS)
