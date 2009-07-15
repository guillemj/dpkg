## Process this file with automake to produce Makefile.in

SUBDIRS = test

localedir = $(datadir)/locale
pkgconfdir = $(sysconfdir)/@PACKAGE@
INCLUDES = \
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
	dpkg-priv.h \
	dpkg-test.h \
	dlist.h \
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
	path.c \
	progress.c progress.h \
	showpkg.c \
	string.c \
	subproc.c \
	tarfn.c tarfn.h \
	triglib.c \
	trigdeferred.l \
	utils.c \
	varbuf.c \
	vercmp.c
