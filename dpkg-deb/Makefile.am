## Process this file with automake to produce Makefile.in

localedir = $(datadir)/locale
INCLUDES = \
	-DLOCALEDIR=\"$(localedir)\" \
	-idirafter $(top_srcdir)/libcompat \
	-I$(top_srcdir)/lib


bin_PROGRAMS = dpkg-deb

dpkg_deb_SOURCES = \
	dpkg-deb.h \
	build.c \
	extract.c \
	info.c \
	main.c

dpkg_deb_LDADD = \
	../libcompat/libcompat.a \
	$(LIBINTL) ../lib/libdpkg.a $(ZLIB_LIBS) $(BZ2_LIBS) $(SELINUX_LIBS)
