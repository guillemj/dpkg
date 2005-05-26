
srcdir		= .
top_srcdir	= ..
top_builddir	= ..

default: all
include ../Makefile.conf

CXX_SOURCES	= basecmds.cc baselist.cc basetop.cc bindings.cc curkeys.cc \
		  main.cc methkeys.cc methlist.cc method.cc methparse.cc \
		  pkgcmds.cc pkgdepcon.cc pkgdisplay.cc pkginfo.cc pkgkeys.cc \
		  pkglist.cc pkgsublist.cc pkgtop.cc helpmsgs.cc

MAN8PAGES	= dselect.8

OBJECTS		= $(patsubst %.cc, %.o, $(CXX_SOURCES))
GENFILES	= $(OBJECTS) dselect curkeys.h

.PHONY: all
all:: dselect

.PHONY: install
install:: all

.PHONY: clean
clean::
	$(RM) $(GENFILES)

.PHONY: distclean
cvslean:: clean
	$(RM) Makefile

.PHONY: install
install:: install-program install-doc

.PHONY: install-program
install-program:
	$(mkinstalldirs) $(DESTDIR)/$(bindir)
	$(INSTALL_PROGRAM) dselect $(DESTDIR)/$(bindir)

.PHONY: install-doc
install-doc:
	$(mkinstalldirs) $(DESTDIR)/$(man8dir)
	set -e ; for i in $(MAN8PAGES) ; do \
	    if test -f $$i ; then d= ; else d="$(srcdir)/" ; fi ; \
	    $(INSTALL_DATA) $$d$$i $(DESTDIR)/$(man8dir) ; \
	done

dselect: $(OBJECTS) ../lib/libdpkg.a
	$(CXX) $(LDFLAGS) -o $@ $(OBJECTS) $(CURSES_LIBS) $(LIBS) $(NLS_LIBS)

basecmds.o: helpmsgs.h
curkeys.o: curkeys.h

curkeys.h: keyoverride $(srcdir)/mkcurkeys.pl
	cursesfile=`echo '#include <curses.h>' | \
		 $(CC) -E - | grep 'curses.h' | head -n 1 | \
		 $(SED) -e 's/^[^"]*"//; s/".*$$//'`; \
	if [ "$$cursesfile" = "" ]; then echo "can't find curses file"; exit 1; fi; \
	perl $(srcdir)/mkcurkeys.pl $< $$cursesfile > $@
