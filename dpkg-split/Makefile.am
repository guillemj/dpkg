## Process this file with automake to produce Makefile.in

AM_CPPFLAGS = \
	-DLOCALEDIR=\"$(localedir)\" \
	-DADMINDIR=\"$(admindir)\" \
	-idirafter $(top_srcdir)/lib/compat \
	-I$(top_builddir) \
	-I$(top_srcdir)/lib \
	# EOL


bin_PROGRAMS = dpkg-split

dpkg_split_SOURCES = \
	dpkg-split.h \
	info.c \
	join.c \
	main.c \
	queue.c \
	split.c \
	# EOL

dpkg_split_LDADD = \
	../lib/dpkg/libdpkg.la \
	$(LIBINTL) \
	# EOL

install-data-local:
	$(MKDIR_P) $(DESTDIR)$(admindir)/parts
