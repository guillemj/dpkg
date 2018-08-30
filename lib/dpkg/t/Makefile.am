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

TEST_ENV_VARS = \
	DPKG_PROGTAR=$(TAR) \
	$(nil)

t_headers_cpp_SOURCES = t-headers-cpp.cc

# The tests are sorted in order of increasing complexity.
test_programs = \
	t-test \
	t-test-skip \
	t-macros \
	t-headers-cpp \
	t-c-ctype \
	t-namevalue \
	t-ehandle \
	t-error \
	t-string \
	t-file \
	t-buffer \
	t-path \
	t-progname \
	t-subproc \
	t-command \
	t-pager \
	t-varbuf \
	t-ar \
	t-tar \
	t-deb-version \
	t-arch \
	t-version \
	t-pkginfo \
	t-pkg-list \
	t-pkg-queue \
	t-pkg-hash \
	t-pkg-show \
	t-fsys-dir \
	t-fsys-hash \
	t-trigger \
	t-mod-db \
	$(nil)

test_scripts = \
	t-tarextract.t \
	t-treewalk.t \
	t-trigdeferred.t \
	$(nil)

check_PROGRAMS = \
	$(test_programs) \
	c-tarextract \
	c-treewalk \
	c-trigdeferred \
	$(nil)

test_tmpdir = t.tmp

include $(top_srcdir)/check.am

clean-local: check-clean
