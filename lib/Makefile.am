## Process this file with automake to produce a Makefile.in

AUTOMAKE_OPTIONS	= 1.1 foreign

## Directory definitions

docdir			= $(prefix)/doc
pkgdocdir		= $(docdir)/@PACKAGE@
copyingfile		= $(pkgdocdir)/copyright

## Various options

CFLAGS			= @CFLAGS@ @CWARNS@ -g $(XCFLAGS)
OPTCFLAGS		= @CFLAGS@ @OPTCFLAGS@ @CWARNS@ -g $(XCFLAGS)
LDFLAGS			= @LDFLAGS@ $(XLDFLAGS)
LIBS			= @LIBS@ $(XLIBS)

CXXFLAGS		= @CXXFLAGS@ @CWARNS@ -g $(XCXXFLAGS)
OPTCXXFLAGS		= @CXXFLAGS@ @OPTCFLAGS@ @CWARNS@ -g $(XCXXFLAGS)

DEFS			= -I$(top_srcdir)/include -I$(top_srcdir) -I$(srcdir) \
			  -I$(top_builddir) -I$(top_builddir)/include -I. \
			  -I$(top_srcdir)/intl -I$(top_builddir)/intl @DEFS@ \
			  -DCOPYINGFILE=\"$(copyingfile)\"

## Automake variables

lib_LTLIBRARIES		= libdpkg.la
noinst_OBJECTS		= myopt.o

libdpkg_la_SOURCES	= ehandle.c mlib.c parse.c parsehelp.c fields.c dump.c \
			  nfmalloc.c varbuf.c database.c vercmp.c \
			  compat.c lock.c dbmodify.c showcright.c \
			  tarfn.c parsedump.h
libdpkg_la_LDFLAGS	= -version-info 0:0:0 -rpath $(libdir)

EXTRA_DIST		= myopt.c

all: myopt.o

MAINTAINERCLEANFILES	= $(srcdir)/Makefile.in

## End of file.
