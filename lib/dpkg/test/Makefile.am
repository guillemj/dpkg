## Process this file with automake to produce Makefile.in

AM_CPPFLAGS = \
	-idirafter $(top_srcdir)/lib/compat \
	-I$(top_builddir) \
	-I$(top_srcdir)/lib


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

CHECK_LDADD = ../libdpkg.a

t_ar_LDADD = $(CHECK_LDADD)
t_command_LDADD = $(CHECK_LDADD)
t_macros_LDADD = $(CHECK_LDADD)
t_path_LDADD = $(CHECK_LDADD)
t_pkginfo_LDADD = $(CHECK_LDADD)
t_pkg_list_LDADD = $(CHECK_LDADD)
t_pkg_queue_LDADD = $(CHECK_LDADD)
t_string_LDADD = $(CHECK_LDADD)
t_buffer_LDADD = $(CHECK_LDADD)
t_test_LDADD = $(CHECK_LDADD)
t_varbuf_LDADD = $(CHECK_LDADD)
t_version_LDADD = $(CHECK_LDADD)

TESTS = $(check_PROGRAMS)
