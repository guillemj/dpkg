## Process this file with automake to produce a Makefile.in

AUTOMAKE_OPTIONS	= 1.1 foreign

## Directory definitions

localedir		= $(datadir)/locale

## Various options

CFLAGS			= @CFLAGS@ @CWARNS@ -g $(XCFLAGS) -DLOCALEDIR=\"$(localedir)\"
OPTCFLAGS		= @CFLAGS@ @OPTCFLAGS@ @CWARNS@ -g $(XCFLAGS)
LDFLAGS			= @LDFLAGS@ $(XLDFLAGS)
LIBS			= @INTLLIBS@ @LIBS@ $(XLIBS)

CXXFLAGS		= @CXXFLAGS@ @CWARNS@ -g $(XCXXFLAGS)
OPTCXXFLAGS		= @CXXFLAGS @OPTCFLAGS@ @CWARNS@ -g $(XCXXFLAGS)

DEFS			= -I$(top_srcdir)/include -I$(top_srcdir) -I$(srcdir) \
			  -I$(top_builddir) -I$(top_builddir)/include -I. \
			  -I$(top_srcdir)/intl -I$(top_builddir)/intl @DEFS@

## Automake variables

MAINTAINERCLEANFILES	= $(srcdir)/Makefile.in
EXTRA_DIST		= dpkg-deb.1

## Rules

bin_PROGRAMS		= dpkg-deb
man_MANS		= dpkg-deb.1

dpkg_deb_SOURCES	= main.c build.c extract.c info.c dpkg-deb.h
dpkg_deb_LDADD		= ../lib/libdpkg.la ../lib/myopt.o

## End of file.
