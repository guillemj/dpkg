## Process this file with automake to produce Makefile.in

localedir = $(datadir)/locale
INCLUDES = \
	-DLOCALEDIR=\"$(localedir)\" -I$(top_srcdir)/intl \
	-DADMINDIR=\"$(admindir)\" \
	-I$(top_srcdir)/lib


bin_PROGRAMS = dpkg dpkg-query

dpkg_SOURCES = \
	archives.c archives.h \
	cleanup.c \
	configure.c \
	depcon.c \
	enquiry.c \
	errors.c \
	filesdb.c filesdb.h \
	help.c \
	main.c main.h \
	packages.c \
	processarc.c \
	remove.c \
	select.c \
	update.c

dpkg_LDADD = \
	$(LIBINTL) ../lib/libdpkg.a $(ZLIB_LIBS) $(BZ2_LIBS) $(SELINUX_LIBS)

dpkg_query_SOURCES = \
	errors.c \
	filesdb.c filesdb.h \
	query.c

dpkg_query_LDADD = $(LIBINTL) ../lib/libdpkg.a


install-data-local:
	$(mkdir_p) $(DESTDIR)$(admindir)/alternatives
	$(mkdir_p) $(DESTDIR)$(admindir)/info
	$(mkdir_p) $(DESTDIR)$(admindir)/updates
