## Process this file with automake to produce Makefile.in

AM_CPPFLAGS = \
	-DLOCALEDIR=\"$(localedir)\" \
	-DADMINDIR=\"$(admindir)\" \
	-idirafter $(top_srcdir)/lib/compat \
	-I$(top_builddir) \
	-I$(top_srcdir)/lib \
	# EOL
LDADD = \
	../lib/dpkg/libdpkg.la \
	$(LIBINTL) \
	# EOL


EXTRA_DIST = \
	$(test_scripts) \
	# EOL

bin_PROGRAMS = \
	dpkg \
	dpkg-divert \
	dpkg-query \
	dpkg-statoverride \
	dpkg-trigger \
	# EOL

dpkg_SOURCES = \
	actions.h \
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
	security-mac.h \
	select.c \
	selinux.c \
	trigproc.c \
	unpack.c \
	update.c \
	verify.c \
	# EOL

dpkg_LDADD = \
	$(LDADD) \
	$(SELINUX_LIBS) \
	# EOL

dpkg_divert_SOURCES = \
	divertcmd.c \
	# EOL

dpkg_query_SOURCES = \
	actions.h \
	querycmd.c \
	# EOL

dpkg_statoverride_SOURCES = \
	actions.h \
	force.c force.h \
	security-mac.h \
	selinux.c \
	statcmd.c \
	# EOL

dpkg_statoverride_LDADD = \
	$(LDADD) \
	$(SELINUX_LIBS) \
	# EOL

dpkg_trigger_SOURCES = \
	trigcmd.c \
	# EOL

install-data-local:
	$(MKDIR_P) $(DESTDIR)$(pkgconfdir)/dpkg.cfg.d
	$(MKDIR_P) $(DESTDIR)$(admindir)/info
	$(MKDIR_P) $(DESTDIR)$(admindir)/updates

test_tmpdir = t.tmp

test_scripts = \
	t/dpkg_divert.t \
	# EOL

include $(top_srcdir)/build-aux/check.am

clean-local: check-clean
