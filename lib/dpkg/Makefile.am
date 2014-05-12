## Process this file with automake to produce Makefile.in

SUBDIRS = . test

localedir = $(datadir)/locale
pkgconfdir = $(sysconfdir)/@PACKAGE@
AM_CPPFLAGS = \
	-DLOCALEDIR=\"$(localedir)\" \
	-DCONFIGDIR=\"$(pkgconfdir)\" \
	-DADMINDIR=\"$(admindir)\" \
	-DDEFAULT_TEXT_DOMAIN=\"@PACKAGE@\" \
	-idirafter $(top_srcdir)/lib/compat \
	-I$(top_builddir) \
	-I$(top_srcdir)/lib


EXTRA_DIST = \
	libdpkg.map \
	libdpkg.pc.in

pkgconfigdir = $(libdir)/pkgconfig
pkgconfig_DATA = libdpkg.pc

lib_LTLIBRARIES = libdpkg.la

if HAVE_LINKER_VERSION_SCRIPT
libdpkg_la_LDFLAGS = \
	-Wl,--version-script=$(srcdir)/libdpkg.map
endif
libdpkg_la_LIBADD = \
	../compat/libcompat.la
if BUILD_SHARED
libdpkg_la_LIBADD += \
	$(LIBINTL) \
	$(ZLIB_LIBS) \
	$(LIBLZMA_LIBS) \
	$(BZ2_LIBS)
endif
libdpkg_la_DEPENDENCIES = \
	libdpkg.map
libdpkg_la_SOURCES = \
	dlist.h \
	ar.c \
	arch.c \
	atomic-file.c \
	buffer.c \
	cleanup.c \
	command.c \
	compress.c \
	dbdir.c \
	dbmodify.c \
	deb-version.c \
	debug.c \
	depcon.c \
	dir.c \
	dump.c \
	ehandle.c \
	error.c \
	fdio.c \
	file.c \
	fields.c \
	glob.c \
	i18n.c i18n.h \
	log.c \
	mlib.c \
	namevalue.c \
	nfmalloc.c \
	options.c \
	parse.c \
	parsehelp.c \
	path.c \
	pkg.c \
	pkg-db.c \
	pkg-array.c \
	pkg-format.c \
	pkg-list.c \
	pkg-queue.c \
	pkg-show.c \
	pkg-spec.c \
	progname.c \
	program.c \
	progress.c \
	report.c \
	string.c \
	strwide.c \
	subproc.c \
	tarfn.c \
	test.h \
	trigname.c \
	trignote.c \
	triglib.c \
	trigdeferred.l \
	utils.c \
	varbuf.c \
	version.c

pkginclude_HEADERS = \
	ar.h \
	arch.h \
	atomic-file.h \
	buffer.h \
	command.h \
	compress.h \
	deb-version.h \
	debug.h \
	dir.h \
	dpkg.h \
	dpkg-db.h \
	ehandle.h \
	error.h \
	fdio.h \
	file.h \
	glob.h \
	macros.h \
	namevalue.h \
	options.h \
	parsedump.h \
	path.h \
	pkg.h \
	pkg-array.h \
	pkg-format.h \
	pkg-list.h \
	pkg-queue.h \
	pkg-show.h \
	pkg-spec.h \
	progname.h \
	program.h \
	progress.h \
	report.h \
	string.h \
	subproc.h \
	tarfn.h \
	trigdeferred.h \
	triglib.h \
	varbuf.h \
	version.h
