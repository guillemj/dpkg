## Process this file with automake to produce Makefile.in

AM_CPPFLAGS = \
	-DLOCALEDIR=\"$(localedir)\" \
	-DADMINDIR=\"$(admindir)\" \
	-idirafter $(top_srcdir)/lib/compat \
	-I$(top_builddir) \
	-I$(top_srcdir)/lib \
	-I$(srcdir)/common \
	# EOL
LDADD = \
	../lib/dpkg/libdpkg.la \
	$(LIBINTL) \
	../lib/compat/libcompat.la \
	# EOL

EXTRA_DIST =

DISTCLEANFILES =

bin_PROGRAMS = \
	dpkg \
	dpkg-deb \
	dpkg-divert \
	dpkg-query \
	dpkg-split \
	dpkg-statoverride \
	dpkg-trigger \
	# EOL

dpkg_SOURCES = \
	common/actions.h \
	common/force.c \
	common/force.h \
	common/security-mac.h \
	common/selinux.c \
	main/archives.c \
	main/archives.h \
	main/cleanup.c \
	main/configure.c \
	main/depcon.c \
	main/enquiry.c \
	main/errors.c \
	main/file-match.c \
	main/file-match.h \
	main/filters.c \
	main/filters.h \
	main/help.c \
	main/main.c \
	main/main.h \
	main/packages.c \
	main/perpkgstate.c \
	main/remove.c \
	main/script.c \
	main/select.c \
	main/trigproc.c \
	main/unpack.c \
	main/update.c \
	main/verify.c \
	# EOL

dpkg_LDADD = \
	$(LDADD) \
	$(SELINUX_LIBS) \
	# EOL

dpkg_deb_SOURCES = \
	deb/dpkg-deb.h \
	deb/build.c \
	deb/extract.c \
	deb/info.c \
	deb/main.c \
	# EOL

dpkg_deb_LDADD = \
	$(LDADD) \
	$(Z_LIBS) \
	$(LZMA_LIBS) \
	$(BZ2_LIBS) \
	# EOL

dpkg_divert_SOURCES = \
	divert/main.c \
	# EOL

dpkg_query_SOURCES = \
	common/actions.h \
	query/main.c \
	# EOL

dpkg_split_SOURCES = \
	split/dpkg-split.h \
	split/info.c \
	split/join.c \
	split/main.c \
	split/queue.c \
	split/split.c \
	# EOL

dpkg_statoverride_SOURCES = \
	common/actions.h \
	common/force.c \
	common/force.h \
	common/security-mac.h \
	common/selinux.c \
	statoverride/main.c \
	# EOL

dpkg_statoverride_LDADD = \
	$(LDADD) \
	$(SELINUX_LIBS) \
	# EOL

dpkg_trigger_SOURCES = \
	trigger/main.c \
	# EOL

install-data-local:
	$(MKDIR_P) $(DESTDIR)$(pkgconfdir)/dpkg.cfg.d
	$(MKDIR_P) $(DESTDIR)$(admindir)/info
	$(MKDIR_P) $(DESTDIR)$(admindir)/parts
	$(MKDIR_P) $(DESTDIR)$(admindir)/updates

test_tmpdir = t.tmp

test_scripts = \
	t/dpkg_divert.t \
	# EOL

EXTRA_DIST += $(test_scripts)

include $(top_srcdir)/build-aux/tap.am

EXTRA_DIST += $(srcdir)/at/atlocal.in
EXTRA_DIST += $(srcdir)/at/package.m4

TESTSUITE_AT = $(srcdir)/at/testsuite.at
TESTSUITE_AT += $(srcdir)/at/local.at
TESTSUITE_AT += $(srcdir)/at/deb-format.at
TESTSUITE_AT += $(srcdir)/at/deb-fields.at
TESTSUITE_AT += $(srcdir)/at/deb-content.at
TESTSUITE_AT += $(srcdir)/at/deb-split.at
EXTRA_DIST += $(TESTSUITE_AT)

TESTSUITE = $(srcdir)/at/testsuite
EXTRA_DIST += $(TESTSUITE)

DISTCLEANFILES += at/atconfig

include $(top_srcdir)/build-aux/autotest.am

check-local: tap-check autotest-check

installcheck-local: autotest-installcheck

clean-local: tap-clean autotest-clean
