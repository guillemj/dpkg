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

bin_PROGRAMS		= dselect
man_MANS		= dselect.8

EXTRA_DIST		= keyoverride mkcurkeys.pl mkhelpmsgs.pl helpmsgs.src \
			  checkunimp.pl $(man_MANS)

dselect_SOURCES		= main.cc bindings.cc curkeys.cc helpmsgs.cc \
			  basecmds.cc baselist.cc basetop.cc \
			  pkgcmds.cc pkgdepcon.cc pkgdisplay.cc pkginfo.cc \
			  pkgkeys.cc pkglist.cc pkgsublist.cc pkgtop.cc \
			  methkeys.cc method.cc methparse.cc methlist.cc \
			  dselect.h bindings.h pkglist.h method.h
dselect_LDADD		= ../lib/libdpkg.la ../lib/myopt.o -lncurses


BUILT_SOURCES		= curkeys.h helpmsgs.h helpmsgs.cc
CLEANFILES		= curkeys.h.new helpmsgs.h.new helpmsgs.cc.new $(BUILT_SOURCES)

DISTCLEANFILES		= updates status available *.old
MAINTAINERCLEANFILES	= $(srcdir)/Makefile.in

## Rules

helpmsgs.h helpmsgs.cc: helpmsgs.src $(srcdir)/mkhelpmsgs.pl
	perl $(srcdir)/mkhelpmsgs.pl $<

curkeys.h: keyoverride $(srcdir)/mkcurkeys.pl
	cursesfile=`echo '#include <curses.h>' | \
		 $(CC) -E - | grep 'curses.h' | head -1 | \
		 sed -e 's/^[^"]*"//; s/".*$$//'`; \
	if [ "$$cursesfile" == "" ]; then echo "can't find curses file"; exit 1; fi; \
	perl $(srcdir)/mkcurkeys.pl $< $$cursesfile > $@.new
	mv $@.new $@

$(DEP_FILES): helpmsgs.h curkeys.h

## Optimize for speed, not space, for most commonly used files

pkgdepcon.o: pkgdepcon.cc
	$(CXX) $(DEFS) $(INCLUDES) $(CPPFLAGS) $(OPTCXXFLAGS) -c $<

pkgdisplay.o: pkgdisplay.cc
	$(CXX) $(DEFS) $(INCLUDES) $(CPPFLAGS) $(OPTCXXFLAGS) -c $<

curkeys.o: curkeys.cc
	$(CXX) $(DEFS) $(INCLUDES) $(CPPFLAGS) $(OPTCXXFLAGS) -c $<

dist-hook:
	cp -p helpmsgs.h helpmsgs.cc curkeys.h $(distdir)/

## End of file.
