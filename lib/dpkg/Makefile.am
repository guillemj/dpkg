## Process this file with automake to produce Makefile.in

SUBDIRS = . test

localedir = $(datadir)/locale
pkgconfdir = $(sysconfdir)/@PACKAGE@
AM_CPPFLAGS = \
	-DLOCALEDIR=\"$(localedir)\" \
	-DCONFIGDIR=\"$(pkgconfdir)\" \
	-idirafter $(top_srcdir)/lib/compat \
	-I$(top_builddir) \
	-I$(top_srcdir)/lib


EXTRA_DIST = \
	libdpkg.Versions \
	libdpkg.pc.in

pkgconfigdir = $(libdir)/pkgconfig
pkgconfig_DATA = libdpkg.pc

lib_LIBRARIES = libdpkg.a

libdpkg_a_SOURCES = \
	dlist.h \
	ar.c \
	buffer.c \
	cleanup.c \
	command.c \
	compress.c \
	database.c \
	dbmodify.c \
	dir.c \
	dump.c \
	ehandle.c \
	file.c \
	fields.c \
	i18n.h \
	log.c \
	md5.c md5.h \
	mlib.c \
	myopt.c \
	nfmalloc.c \
	parse.c \
	parsehelp.c \
	path.c \
	pkg.c \
	pkg-array.c \
	pkg-format.c \
	pkg-list.c \
	pkg-queue.c \
	progress.c \
	string.c \
	subproc.c \
	tarfn.c \
	test.h \
	triglib.c \
	trigdeferred.l \
	utils.c \
	varbuf.c \
	vercmp.c

pkginclude_HEADERS = \
	ar.h \
	buffer.h \
	command.h \
	compress.h \
	dir.h \
	dpkg.h \
	dpkg-db.h \
	file.h \
	macros.h \
	myopt.h \
	parsedump.h \
	path.h \
	pkg.h \
	pkg-array.h \
	pkg-format.h \
	pkg-list.h \
	pkg-queue.h \
	progress.h \
	string.h \
	subproc.h \
	tarfn.h \
	trigdeferred.h \
	triglib.h \
	varbuf.h
