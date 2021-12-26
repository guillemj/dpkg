## Process this file with automake to produce Makefile.in

methodsdir = $(pkglibexecdir)/methods

nobase_dist_methods_DATA = \
	disk/names \
	disk/desc.mounted \
	ftp/names \
	ftp/desc.ftp \
	multicd/names \
	multicd/desc.multi_cd \
	# EOL

nobase_methods_SCRIPTS = \
	disk/install \
	disk/setup \
	disk/update \
	ftp/install \
	ftp/setup \
	ftp/update \
	multicd/install \
	multicd/setup \
	multicd/update \
	# EOL

perllibdir = $(PERL_LIBDIR)
nobase_dist_perllib_DATA = \
	Dselect/Ftp.pm \
	# EOL

EXTRA_DIST = \
	disk/setup.sh \
	disk/update.sh \
	disk/install.sh \
	ftp/setup.pl \
	ftp/update.pl \
	ftp/install.pl \
	multicd/setup.sh \
	multicd/update.sh \
	multicd/install.sh \
	multicd/README.multicd \
	# EOL

CLEANFILES = \
	$(nobase_methods_SCRIPTS) \
	# EOL

do_perl_subst = $(AM_V_GEN) $(SED) \
	-e "s:^\#![[:space:]]*/usr/bin/perl:\#!$(PERL):" \
	# EOL

SUFFIXES = .pl .sh

.pl:
	@test -d `dirname $@` || $(MKDIR_P) `dirname $@`
	$(do_perl_subst) <$< >$@
	$(AM_V_at) chmod +x $@

do_shell_subst = $(AM_V_GEN) \
	cat

.sh: Makefile
	@test -d `dirname $@` || $(MKDIR_P) `dirname $@`
	$(do_shell_subst) <$< >$@
	$(AM_V_at) chmod +x $@

install-data-local:
	$(MKDIR_P) $(DESTDIR)$(admindir)/methods/mnt
	$(MKDIR_P) $(DESTDIR)$(admindir)/methods/disk
	$(MKDIR_P) $(DESTDIR)$(admindir)/methods/ftp
	$(MKDIR_P) $(DESTDIR)$(admindir)/methods/multicd
