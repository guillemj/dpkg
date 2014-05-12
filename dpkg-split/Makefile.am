## Process this file with automake to produce Makefile.in

localedir = $(datadir)/locale
AM_CPPFLAGS = \
	-DLOCALEDIR=\"$(localedir)\" \
	-DADMINDIR=\"$(admindir)\" \
	-idirafter $(top_srcdir)/lib/compat \
	-I$(top_builddir) \
	-I$(top_srcdir)/lib


bin_PROGRAMS = dpkg-split

dpkg_split_SOURCES = \
	dpkg-split.h \
	info.c \
	join.c \
	main.c \
	queue.c \
	split.c

dpkg_split_LDADD = \
	../lib/dpkg/libdpkg.la \
	$(LIBINTL)

install-data-local:
	$(MKDIR_P) $(DESTDIR)$(admindir)/parts
