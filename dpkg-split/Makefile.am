## Process this file with automake to produce Makefile.in

localedir = $(datadir)/locale
INCLUDES = \
	-DLOCALEDIR=\"$(localedir)\" -I$(top_srcdir)/intl \
	-DADMINDIR=\"$(admindir)\" -DMKSPLITSCRIPT=\"$(pkglibdir)/mksplit\" \
	-I$(top_srcdir)/lib


bin_PROGRAMS = dpkg-split

dpkg_split_SOURCES = \
	dpkg-split.h \
	info.c \
	join.c \
	main.c \
	queue.c \
	split.c

dpkg_split_LDADD = $(LIBINTL) ../lib/libdpkg.a


pkglib_SCRIPTS = mksplit
EXTRA_DIST = mksplit.pl
CLEANFILES = $(pkglib_SCRIPTS)


do_perl_subst = sed -e "s:^\#![:space:]*/usr/bin/perl:\#!$(PERL):"


%: %.pl Makefile
	@test -d `dirname $@` || $(mkdir_p) `dirname $@`
	$(do_perl_subst) <$< >$@
	chmod +x $@


install-data-local:
	$(mkdir_p) $(DESTDIR)$(admindir)/parts
