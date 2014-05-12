## Process this file with automake to produce Makefile.in

localedir = $(datadir)/locale
AM_CPPFLAGS = \
	-DLOCALEDIR=\"$(localedir)\" \
	-idirafter $(top_srcdir)/lib/compat \
	-I$(top_builddir) \
	-I$(top_srcdir)/lib


bin_PROGRAMS = dpkg-deb

dpkg_deb_SOURCES = \
	dpkg-deb.h \
	build.c \
	extract.c \
	info.c \
	main.c

dpkg_deb_LDADD = \
	../lib/dpkg/libdpkg.la \
	$(LIBINTL) \
	$(ZLIB_LIBS) \
	$(LIBLZMA_LIBS) \
	$(BZ2_LIBS)
