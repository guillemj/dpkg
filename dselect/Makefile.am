## Process this file with automake to produce Makefile.in

localedir = $(datadir)/locale
INCLUDES = \
	-DLOCALEDIR=\"$(localedir)\" -I$(top_srcdir)/intl \
	-DADMINDIR=\"$(admindir)\" -DLIBDIR=\"$(pkglibdir)\" \
	-I$(top_srcdir)/lib


bin_PROGRAMS = dselect

dselect_SOURCES = \
	dselect.h \
	basecmds.cc \
	baselist.cc \
	basetop.cc \
	bindings.cc bindings.h \
	curkeys.cc \
	helpmsgs.cc helpmsgs.h \
	main.cc \
	methkeys.cc \
	methlist.cc \
	method.cc method.h \
	methparse.cc \
	pkgcmds.cc \
	pkgdepcon.cc \
	pkgdisplay.cc \
	pkginfo.cc \
	pkgkeys.cc \
	pkglist.cc pkglist.h \
	pkgsublist.cc \
	pkgtop.cc

dselect_LDADD = $(LIBINTL) ../lib/libdpkg.a $(CURSES_LIBS)


EXTRA_DIST = keyoverride mkcurkeys.pl
CLEANFILES = curkeys.h

curkeys.$(OBJEXT): curkeys.h
curkeys.h: $(srcdir)/keyoverride $(srcdir)/mkcurkeys.pl
	cursesfile=`echo '#include <curses.h>' | \
		$(CC) -E - | grep 'curses.h' | head -n 1 | \
		sed -e 's/^[^"]*"//; s/".*$$//'`; \
	if [ "$$cursesfile" = "" ]; then \
		echo "can't find curses file"; exit 1; \
	fi; \
	perl $(srcdir)/mkcurkeys.pl $< $$cursesfile >$@
