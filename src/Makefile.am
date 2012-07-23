## Process this file with automake to produce Makefile.in

localedir = $(datadir)/locale
pkgconfdir = $(sysconfdir)/@PACKAGE@

AM_CPPFLAGS = \
	-DLOCALEDIR=\"$(localedir)\" \
	-DADMINDIR=\"$(admindir)\" \
	-idirafter $(top_srcdir)/lib/compat \
	-I$(top_builddir) \
	-I$(top_srcdir)/lib
LDADD = \
	../lib/dpkg/libdpkg.a \
	../lib/compat/libcompat.a \
	$(LIBINTL)


EXTRA_DIST = \
	$(test_cases)

bin_PROGRAMS = \
	dpkg \
	dpkg-divert \
	dpkg-query \
	dpkg-statoverride \
	dpkg-trigger

noinst_HEADERS = \
	filesdb.h \
	infodb.h

dpkg_SOURCES = \
	archives.c archives.h \
	cleanup.c \
	configure.c \
	depcon.c \
	enquiry.c \
	errors.c \
	filesdb.c \
	filesdb-hash.c \
	file-match.c file-match.h \
	filters.c filters.h \
	infodb-access.c \
	infodb-format.c \
	infodb-upgrade.c \
	divertdb.c \
	statdb.c \
	help.c \
	main.c main.h \
	packages.c \
	remove.c \
	script.c \
	select.c \
	trigproc.c \
	unpack.c \
	update.c \
	verify.c \
	$(nil)

dpkg_LDADD = \
	$(LDADD) \
	$(SELINUX_LIBS)

dpkg_divert_SOURCES = \
	filesdb.c \
	infodb-format.c \
	divertdb.c \
	divertcmd.c

dpkg_query_SOURCES = \
	filesdb.c \
	infodb-access.c \
	infodb-format.c \
	divertdb.c \
	querycmd.c

dpkg_statoverride_SOURCES = \
	filesdb.c \
	infodb-format.c \
	statdb.c \
	statcmd.c

dpkg_trigger_SOURCES = \
	trigcmd.c

install-data-local:
	$(MKDIR_P) $(DESTDIR)$(pkgconfdir)/dpkg.cfg.d
	$(MKDIR_P) $(DESTDIR)$(admindir)/info
	$(MKDIR_P) $(DESTDIR)$(admindir)/updates

test_tmpdir = t.tmp

test_cases = \
	t/100_dpkg_divert.t

include $(top_srcdir)/Makecheck.am

clean-local: check-clean
