## Process this file with automake to produce a Makefile.in

AUTOMAKE_OPTIONS		= 1.1 foreign

## Directory definitions

pkglibdir		= $(libdir)/@PACKAGE@
localedir		= $(datadir)/locale

## Various options

CFLAGS			= @CFLAGS@ -g $(XCFLAGS) -DLOCALEDIR=\"$(localedir)\"
OPTCFLAGS		= @CFLAGS@ @OPTCFLAGS@ @CWARNS@ -g $(XCFLAGS) -DLOCALEDIR=\"$(localedir)\"
LDFLAGS			= @LDFLAGS@ $(XLDFLAGS)
LIBS			= @LIBS@ $(XLIBS)

CXXFLAGS		= @CXXFLAGS@ -g $(XCXXFLAGS) -DLOCALEDIR=\"$(localedir)\"
OPTCXXFLAGS		= @CXXFLAGS @OPTCFLAGS@ @CWARNS@ -g $(XCXXFLAGS) -DLOCALEDIR=\"$(localedir)\"

DEFS			= -I$(top_srcdir)/include -I$(top_srcdir) -I$(srcdir) \
			  -I$(top_builddir) -I$(top_builddir)/include -I. \
			  -I$(top_srcdir)/intl -I$(top_builddir)/intl @DEFS@ \
			  -DMKSPLITSCRIPT=\"$(pkglibdir)/mksplit\"
## Automake variables

sbin_PROGRAMS			= start-stop-daemon
start_stop_daemon_SOURCES	= start-stop-daemon.c

man_MANS			= start-stop-daemon.8

## End of file.
