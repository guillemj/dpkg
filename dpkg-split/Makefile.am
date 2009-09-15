## Process this file with automake to produce Makefile.in

localedir = $(datadir)/locale
AM_CPPFLAGS = \
	-DLOCALEDIR=\"$(localedir)\" \
	-DADMINDIR=\"$(admindir)\" -DMKSPLITSCRIPT=\"$(pkglibdir)/mksplit\" \
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
	../lib/dpkg/libdpkg.a \
	../lib/compat/libcompat.a \
	$(LIBINTL)


pkglib_SCRIPTS = mksplit
EXTRA_DIST = mksplit.pl
CLEANFILES = $(pkglib_SCRIPTS)


do_perl_subst = $(AM_V_GEN) sed -e "s:^\#![:space:]*/usr/bin/perl:\#!$(PERL):"


%: %.pl Makefile
	@test -d `dirname $@` || $(mkdir_p) `dirname $@`
	$(do_perl_subst) <$< >$@
	$(AM_V_at) chmod +x $@


install-data-local:
	$(mkdir_p) $(DESTDIR)$(admindir)/parts
