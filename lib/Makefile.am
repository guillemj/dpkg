## Process this file with automake to produce Makefile.in

localedir = $(datadir)/locale
pkgconfdir = $(sysconfdir)/@PACKAGE@
INCLUDES = \
	-DLOCALEDIR=\"$(localedir)\" -I$(top_srcdir)/intl \
	-DCONFIGDIR=\"$(pkgconfdir)\" \
	-DCOPYINGFILE=\"$(datadir)/common-licenses/GPL-2\"


noinst_LIBRARIES = libdpkg.a

libdpkg_a_SOURCES = \
	dpkg.h \
	dpkg-db.h \
	compat.c \
	compression.c \
	database.c \
	dbmodify.c \
	dump.c \
	ehandle.c \
	fields.c \
	gettext.h \
	lock.c \
	md5.c md5.h \
	mlib.c \
	myopt.c myopt.h \
	nfmalloc.c \
	parse.c \
	parsehelp.c \
	parsedump.h \
	showcright.c \
	showpkg.c \
	tarfn.c tarfn.h \
	utils.c \
	varbuf.c \
	vercmp.c
