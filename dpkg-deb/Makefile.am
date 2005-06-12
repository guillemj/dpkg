## Process this file with automake to produce Makefile.in

localedir = $(datadir)/locale
INCLUDES = \
	-DLOCALEDIR=\"$(localedir)\" -I$(top_srcdir)/intl -I$(top_srcdir)/lib


bin_PROGRAMS = dpkg-deb

dpkg_deb_SOURCES = \
	dpkg-deb.h \
	build.c \
	extract.c \
	info.c \
	main.c

dpkg_deb_LDADD = \
	$(LIBINTL) ../lib/libdpkg.a $(ZLIB_LIBS) $(BZ2_LIBS) $(SELINUX_LIBS)
