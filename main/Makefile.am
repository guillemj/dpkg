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

## Automake variables

bin_PROGRAMS		= dpkg
man_MANS		= dpkg.8

dpkg_SOURCES		= main.c enquiry.c filesdb.c archives.c processarc.c \
			  cleanup.c select.c packages.c configure.c remove.c \
			  help.c depcon.c errors.c update.c main.h filesdb.h \
			  archives.h
dpkg_LDADD		= ../lib/libdpkg.la ../lib/myopt.o

BUILT_SOURCES		= archtable.h
CLEANFILES		= archtable.h.new $(BUILT_SOURCES)

DISTCLEANFILES		= updates status available *.old
MAINTAINERCLEANFILES	= $(srcdir)/Makefile.in

EXTRA_DIST		= dpkg.8

## Rules

filesdb.o: filesdb.c
	$(CC) $(DEFS) $(INCLUDES) $(CPPFLAGS) $(OPTCFLAGS) -c $<

$(DEP_FILES): archtable.h

archtable.h: $(top_srcdir)/archtable
	expand $(top_srcdir)/archtable | \
	 perl -ne 'print "  { \"$$1\",$$2\"$$3\",$$4\"$$5\" },\n" \
		   if m/^\s*(\w+)(\s+)(\w+)(\s+)(\w+)\s*$$/' \
		>$@.new
	mv $@.new $@

dist-hook:
	cp -p  archtable.h $(distdir)/

## End of file.
