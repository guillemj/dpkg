## Process this file with automake to produce a Makefile.in

AUTOMAKE_OPTIONS	= 1.1 foreign

## Directory definitions

pkglibdir		= $(libdir)/@PACKAGE@
localedir		= $(datadir)/locale

## Various options

CFLAGS			= @CFLAGS@ @CWARNS@ -g $(XCFLAGS) -DLOCALEDIR=\"$(localedir)\"
OPTCFLAGS		= @CFLAGS@ @OPTCFLAGS@ @CWARNS@ -g $(XCFLAGS) -DLOCALEDIR=\"$(localedir)\"
LDFLAGS			= @LDFLAGS@ $(XLDFLAGS)
LIBS			= @INTLLIBS@ @LIBS@ $(XLIBS)

CXXFLAGS		= @CXXFLAGS@ @CWARNS@ -g $(XCXXFLAGS) -DLOCALEDIR=\"$(localedir)\"
OPTCXXFLAGS		= @CXXFLAGS @OPTCFLAGS@ @CWARNS@ -g $(XCXXFLAGS) -DLOCALEDIR=\"$(localedir)\"

DEFS			= -I$(top_srcdir)/include -I$(top_srcdir) -I$(srcdir) \
			  -I$(top_builddir) -I$(top_builddir)/include -I. \
			  -I$(top_srcdir)/intl -I$(top_builddir)/intl @DEFS@ \
			  -DMKSPLITSCRIPT=\"$(pkglibdir)/mksplit\"

## Automake variables

bin_PROGRAMS		= dpkg-split
pkglib_SCRIPTS		= mksplit
man_MANS		= dpkg-split.8

EXTRA_DIST		= mksplit.pl dpkg-split.8

dpkg_split_SOURCES	= main.c split.c info.c queue.c join.c dpkg-split.h
dpkg_split_LDADD	= ../lib/libdpkg.la ../lib/myopt.o


CLEANFILES		= $(pkglib_SCRIPTS)
MAINTAINERCLEANFILES	= $(srcdir)/Makefile.in

## Rules

SUFFIXES		= .pl

.pl:
	sed -e "s:^#![:space:]*/usr/bin/perl:#! $(perlpath):;" \
		< $< > $@.new
	chmod 755 $@.new
	mv $@.new $@

## End of file.
