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

nobase_dist_methods_SCRIPTS = \
	disk/setup \
	disk/update \
	disk/install \
	floppy/setup \
	floppy/update \
	floppy/install \
	ftp/setup \
	ftp/update \
	ftp/install \
	multicd/setup \
	multicd/update \
	multicd/install

perllibdir = $(PERL_LIBDIR)
nobase_dist_perllib_DATA = Dselect/Ftp.pm

EXTRA_DIST = multicd/README.multicd

install-data-local:
	$(MKDIR_P) $(DESTDIR)$(admindir)/methods/mnt
	$(MKDIR_P) $(DESTDIR)$(admindir)/methods/disk
	$(MKDIR_P) $(DESTDIR)$(admindir)/methods/floppy
	$(MKDIR_P) $(DESTDIR)$(admindir)/methods/ftp
	$(MKDIR_P) $(DESTDIR)$(admindir)/methods/multicd
