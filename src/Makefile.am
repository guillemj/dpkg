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
	../lib/dpkg/libdpkg.la \
	$(LIBINTL)


EXTRA_DIST = \
	$(test_scripts) \
	$(nil)

bin_PROGRAMS = \
	dpkg \
	dpkg-divert \
	dpkg-query \
	dpkg-statoverride \
	dpkg-trigger

dpkg_SOURCES = \
	archives.c archives.h \
	cleanup.c \
	configure.c \
	depcon.c \
	enquiry.c \
	errors.c \
	file-match.c file-match.h \
	filters.c filters.h \
	force.c force.h \
	help.c \
	main.c main.h \
	packages.c \
	perpkgstate.c \
	remove.c \
	script.c \
	select.c \
	selinux.c \
	trigproc.c \
	unpack.c \
	update.c \
	verify.c \
	$(nil)

dpkg_LDADD = \
	$(LDADD) \
	$(SELINUX_LIBS)

dpkg_divert_SOURCES = \
	divertcmd.c

dpkg_query_SOURCES = \
	querycmd.c

dpkg_statoverride_SOURCES = \
	force.c force.h \
	selinux.c \
	statcmd.c

dpkg_statoverride_LDADD = \
	$(LDADD) \
	$(SELINUX_LIBS)

dpkg_trigger_SOURCES = \
	trigcmd.c

install-data-local:
	$(MKDIR_P) $(DESTDIR)$(pkgconfdir)/dpkg.cfg.d
	$(MKDIR_P) $(DESTDIR)$(admindir)/info
	$(MKDIR_P) $(DESTDIR)$(admindir)/updates

test_tmpdir = t.tmp

test_scripts = \
	t/dpkg_divert.t

include $(top_srcdir)/check.am

clean-local: check-clean
