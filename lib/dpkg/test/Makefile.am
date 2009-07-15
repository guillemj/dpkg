## Process this file with automake to produce Makefile.in

INCLUDES = \
	-idirafter $(top_srcdir)/lib/compat \
	-I$(top_srcdir)/lib/dpkg \
	-I$(top_srcdir)/lib


# The tests are sorted in order of increasing complexity.
check_PROGRAMS = \
	t-test \
	t-macros \
	t-string \
	t-path \
	t-varbuf \
	t-version \
	t-pkginfo

CHECK_LDADD = ../libdpkg.a

t_macros_LDADD = $(CHECK_LDADD)
t_path_LDADD = $(CHECK_LDADD)
t_pkginfo_LDADD = $(CHECK_LDADD)
t_string_LDADD = $(CHECK_LDADD)
t_test_LDADD = $(CHECK_LDADD)
t_varbuf_LDADD = $(CHECK_LDADD)
t_version_LDADD = $(CHECK_LDADD)

TESTS = $(check_PROGRAMS)

