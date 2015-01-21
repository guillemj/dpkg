## Process this file with automake to produce Makefile.in

methodsdir = $(pkglibdir)/methods

nobase_dist_methods_DATA = \
	disk/names \
	disk/desc.cdrom \
	disk/desc.nfs \
	disk/desc.harddisk \
	disk/desc.mounted \
	floppy/names \
	floppy/desc.floppy \
	ftp/names \
	ftp/desc.ftp \
	ftp/README.mirrors.txt \
	multicd/names \
	multicd/desc.multi_cd \
	multicd/desc.multi_mount \
	multicd/desc.multi_nfs

nobase_methods_SCRIPTS = \
	ftp/setup \
	ftp/update \
	ftp/install \
	$(nil)

nobase_dist_methods_SCRIPTS = \
	disk/setup \
	disk/update \
	disk/install \
	floppy/setup \
	floppy/update \
	floppy/install \
	multicd/setup \
	multicd/update \
	multicd/install

perllibdir = $(PERL_LIBDIR)
nobase_dist_perllib_DATA = Dselect/Ftp.pm

EXTRA_DIST = \
	ftp/setup.pl \
	ftp/update.pl \
	ftp/install.pl \
	multicd/README.multicd

CLEANFILES = \
	$(nobase_methods_SCRIPTS) \
	$(nil)

do_perl_subst = $(AM_V_GEN) \
	sed -e "s:^\#![[:space:]]*/usr/bin/perl:\#!$(PERL):"

%: %.pl Makefile
	@test -d `dirname $@` || $(MKDIR_P) `dirname $@`
	$(do_perl_subst) <$< >$@
	$(AM_V_at) chmod +x $@

install-data-local:
	$(MKDIR_P) $(DESTDIR)$(admindir)/methods/mnt
	$(MKDIR_P) $(DESTDIR)$(admindir)/methods/disk
	$(MKDIR_P) $(DESTDIR)$(admindir)/methods/floppy
	$(MKDIR_P) $(DESTDIR)$(admindir)/methods/ftp
	$(MKDIR_P) $(DESTDIR)$(admindir)/methods/multicd
