## Process this file with automake to produce Makefile.in

AM_CPPFLAGS = \
	-DADMINDIR=\"$(admindir)\" \
	-idirafter $(top_srcdir)/lib/compat \
	-I$(top_builddir) \
	-I$(top_srcdir)/lib
LDADD = \
	$(top_builddir)/lib/dpkg/libdpkg.a \
	$(top_builddir)/lib/compat/libcompat.a \
	$(LIBINTL)


# The tests are sorted in order of increasing complexity.
check_PROGRAMS = \
	t-test \
	t-macros \
	t-string \
	t-buffer \
	t-path \
	t-progname \
	t-subproc \
	t-command \
	t-varbuf \
	t-ar \
	t-version \
	t-pkginfo \
	t-pkg-list \
	t-pkg-queue \
	t-mod-db

TESTS = $(check_PROGRAMS)
