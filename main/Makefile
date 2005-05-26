
srcdir		= .
top_srcdir	= ..
top_builddir	= ..

default: all
include ../Makefile.conf

SOURCES		= main.c enquiry.c filesdb.c archives.c processarc.c \
		  cleanup.c select.c packages.c configure.c remove.c \
		  help.c depcon.c errors.c update.c 

MAN8PAGES	= dpkg.8 dpkg-query.8

OBJECTS		= $(patsubst %.c, %.o, $(SOURCES))
GENFILES	= $(OBJECTS) archtable.h dpkg dpkg-static

QUERY_SOURCES	= query.c filesdb.c errors.c 
QUERY_OBJECTS	= $(patsubst %.c, %.o, $(QUERY_SOURCES))
QUERY_GENFILES	= $(QUERY_OBJECTS) dpkg-query

.PHONY: all
all:: dpkg dpkg-query

ifdef ALSO_STATIC
all:: dpkg-static
endif

.PHONY: install
install:: all

.PHONY: clean
clean::
	$(RM) $(GENFILES) $(QUERY_GENFILES)

.PHONY: distclean
cvslean:: clean
	$(RM) Makefile

.PHONY: install
install:: install-program install-doc

.PHONY: install-program
install-program:
	$(mkinstalldirs) $(DESTDIR)/$(bindir)
	$(INSTALL_PROGRAM) dpkg $(DESTDIR)/$(bindir)
ifdef ALSO_STATIC
	$(INSTALL_PROGRAM) dpkg-static $(DESTDIR)/$(bindir)
endif
	$(INSTALL_PROGRAM) dpkg-query $(DESTDIR)/$(bindir)
	$(mkinstalldirs) $(DESTDIR)/$(admindir)/alternatives
	$(mkinstalldirs) $(DESTDIR)/$(admindir)/info
	$(mkinstalldirs) $(DESTDIR)/$(admindir)/updates

.PHONY: install-doc
install-doc:
	$(mkinstalldirs) $(DESTDIR)/$(man8dir)
	set -e ; for i in $(MAN8PAGES) ; do \
	    if test -f $$i ; then d= ; else d="$(srcdir)/" ; fi ; \
	    $(INSTALL_DATA) $$d$$i $(DESTDIR)/$(man8dir) ; \
	done

dpkg-static: LDFLAGS += -static
dpkg-static: ZLIB_LIBS = $(ZLIBS_LIBS_ALSO_STATIC)
dpkg dpkg-static: $(OBJECTS) ../lib/libdpkg.a
	$(CC) $(LDFLAGS) -o $@ $(OBJECTS) $(LIBS) $(NLS_LIBS)

dpkg-query: $(QUERY_OBJECTS) ../lib/libdpkg.a
	$(CC) $(LDFLAGS) -o $@ $(QUERY_OBJECTS) $(LIBS) $(NLS_LIBS)

enquiry.o: archtable.h

archtable.h: $(top_srcdir)/archtable
	expand $< | \
	 perl -ne 'print "  { \"$$1\",$$2\"$$3\",$$4\"$$5\" },\n" \
		   if m/^(?!\s*#)\s*(\S+)(\s+)(\S+)(\s+)(\S+)\s*$$/' \
		>$@
