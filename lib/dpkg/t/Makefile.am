## Process this file with automake to produce Makefile.in

AM_CPPFLAGS = \
	-DADMINDIR=\"$(admindir)\" \
	-idirafter $(top_srcdir)/lib/compat \
	-I$(top_builddir) \
	-I$(top_srcdir)/lib
LDADD = \
	$(top_builddir)/lib/dpkg/libdpkg.la \
	$(LIBINTL)

EXTRA_DIST = \
	$(test_scripts) \
	$(nil)


# The tests are sorted in order of increasing complexity.
test_programs = \
	t-test \
	t-test-skip \
	t-macros \
	t-c-ctype \
	t-error \
	t-string \
	t-buffer \
	t-path \
	t-progname \
	t-subproc \
	t-command \
	t-varbuf \
	t-ar \
	t-deb-version \
	t-arch \
	t-version \
	t-pkginfo \
	t-pkg-list \
	t-pkg-queue \
	t-trigger \
	t-mod-db \
	$(nil)

test_scripts = \
	t-tar.t \
	t-tree.t \
	$(nil)

check_PROGRAMS = \
	$(test_programs) \
	t-tarextract \
	t-treewalk \
	$(nil)

test_tmpdir = t.tmp

include $(top_srcdir)/check.am

clean-local: check-clean
