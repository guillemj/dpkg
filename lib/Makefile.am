## Process this file with automake to produce Makefile.in

localedir = $(datadir)/locale
pkgconfdir = $(sysconfdir)/@PACKAGE@
INCLUDES = \
	-DLOCALEDIR=\"$(localedir)\" \
	-DCONFIGDIR=\"$(pkgconfdir)\" \
	-DCOPYINGFILE=\"$(datadir)/common-licenses/GPL-2\" \
	-idirafter $(top_srcdir)/libcompat


noinst_LIBRARIES = libdpkg.a

libdpkg_a_SOURCES = \
	dpkg-def.h \
	dpkg.h \
	dpkg-db.h \
	dlist.h \
	cleanup.c \
	compat.c \
	compression.c \
	database.c \
	dbmodify.c \
	dump.c \
	ehandle.c \
	fields.c \
	gettext.h \
	lock.c \
	log.c \
	md5.c md5.h \
	mlib.c \
	myopt.c myopt.h \
	myopt-util.c \
	nfmalloc.c \
	parse.c \
	parsehelp.c \
	parsedump.h \
	showpkg.c \
	tarfn.c tarfn.h \
	triglib.c \
	trigdeferred.l \
	utils.c \
	varbuf.c \
	vercmp.c
