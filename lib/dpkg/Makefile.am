## Process this file with automake to produce Makefile.in

SUBDIRS = test

localedir = $(datadir)/locale
pkgconfdir = $(sysconfdir)/@PACKAGE@
AM_CPPFLAGS = \
	-DLOCALEDIR=\"$(localedir)\" \
	-DCONFIGDIR=\"$(pkgconfdir)\" \
	-DCOPYINGFILE=\"$(datadir)/common-licenses/GPL-2\" \
	-idirafter $(top_srcdir)/lib/compat \
	-I$(top_builddir) \
	-I$(top_srcdir)/lib


noinst_LIBRARIES = libdpkg.a

libdpkg_a_SOURCES = \
	dpkg.h \
	dpkg-db.h \
	dlist.h \
	buffer.c buffer.h \
	cleanup.c \
	compression.c \
	database.c \
	dbmodify.c \
	dump.c \
	ehandle.c \
	fields.c \
	i18n.h \
	lock.c \
	log.c \
	macros.h \
	md5.c md5.h \
	mlib.c \
	myopt.c myopt.h \
	myopt-util.c \
	nfmalloc.c \
	parse.c \
	parsehelp.c \
	parsedump.h \
	path.c path.h \
	pkg.c pkg.h \
	pkg-array.c pkg-array.h \
	pkg-list.c pkg-list.h \
	progress.c progress.h \
	showpkg.c \
	string.c string.h \
	subproc.c subproc.h \
	tarfn.c tarfn.h \
	test.h \
	triglib.c \
	trigdeferred.l \
	utils.c \
	varbuf.c varbuf.h \
	vercmp.c
