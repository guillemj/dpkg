## Process this file with automake to produce a Makefile.in

AUTOMAKE_OPTIONS	= 1.1 foreign

## Directory definitions

localedir		= $(datadir)/locale

## Various options

CFLAGS			= @CFLAGS@ @CWARNS@ -g $(XCFLAGS) -DLOCALEDIR=\"$(localedir)\"
OPTCFLAGS		= @CFLAGS@ @OPTCFLAGS@ @CWARNS@ -g $(XCFLAGS) -DLOCALEDIR=\"$(localedir)\"
LDFLAGS			= @LDFLAGS@ $(XLDFLAGS)
LIBS			= @INTLLIBS@ @LIBS@ $(XLIBS)

CXXFLAGS		= @CXXFLAGS@ @CWARNS@ -g $(XCXXFLAGS) -DLOCALEDIR=\"$(localedir)\"
OPTCXXFLAGS		= @CXXFLAGS@ @OPTCFLAGS@ @CWARNS@ -g $(XCXXFLAGS) -DLOCALEDIR=\"$(localedir)\"

DEFS			= -I$(top_srcdir)/include -I$(top_srcdir) -I$(srcdir) \
			  -I$(top_builddir) -I$(top_builddir)/include -I. \
			  -I$(top_srcdir)/intl -I$(top_builddir)/intl @DEFS@

MAINTAINERCLEANFILES	= $(srcdir)/Makefile.in

## Automake variables

bin_PROGRAMS		= md5sum
man_MANS		= md5sum.1

md5sum_SOURCES		= md5.c md5sum.c md5.h
EXTRA_DIST		= md5sum.1

## End of file.
