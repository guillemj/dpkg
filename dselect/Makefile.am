## Process this file with automake to produce Makefile.in

SUBDIRS = methods po

localedir = $(datadir)/locale
pkgconfdir = $(sysconfdir)/@PACKAGE@

AM_CPPFLAGS = \
	-DLOCALEDIR=\"$(localedir)\" \
	-DADMINDIR=\"$(admindir)\" -DLIBDIR=\"$(pkglibdir)\" \
	-DLOCALLIBDIR=\"/usr/local/lib/dpkg\" \
	-idirafter $(top_srcdir)/lib/compat \
	-iquote $(builddir) \
	-I$(top_builddir) \
	-I$(top_srcdir)/lib


bin_PROGRAMS = dselect

dselect_SOURCES = \
	dselect.h \
	dselect-curses.h \
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

dselect_LDADD = \
	$(CURSES_LIBS) \
	../lib/dpkg/libdpkg.a \
	../lib/compat/libcompat.a \
	$(LIBINTL)


EXTRA_DIST = keyoverride mkcurkeys.pl
CLEANFILES = curkeys.h

curkeys.$(OBJEXT): curkeys.h
curkeys.h: $(srcdir)/keyoverride $(srcdir)/mkcurkeys.pl
	$(AM_V_GEN) cursesfile=`echo '#include "dselect-curses.h"' | \
		$(CPP) -I$(top_builddir) -I $(srcdir) - | \
		grep 'curses.h' | head -n 1 | \
		sed -e 's/^[^"]*"//; s/".*$$//'`; \
	if [ "$$cursesfile" = "" ]; then \
		echo "can't find curses file"; exit 1; \
	fi; \
	perl $(srcdir)/mkcurkeys.pl $< $$cursesfile >$@

install-data-local:
	$(MKDIR_P) $(DESTDIR)$(pkgconfdir)/dselect.cfg.d
