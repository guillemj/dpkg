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
	ftp/README.mirrors.txt

nobase_dist_methods_SCRIPTS = \
	disk/setup \
	disk/update \
	disk/install \
	floppy/setup \
	floppy/update \
	floppy/install \
	ftp/setup \
	ftp/update \
	ftp/install

perllibdir = $(PERL_LIBDIR)
nobase_dist_perllib_DATA = Debian/Dselect/Ftp.pm

install-data-local:
	$(mkdir_p) $(DESTDIR)$(admindir)/methods/mnt
	$(mkdir_p) $(DESTDIR)$(admindir)/methods/disk
	$(mkdir_p) $(DESTDIR)$(admindir)/methods/floppy
	$(mkdir_p) $(DESTDIR)$(admindir)/methods/ftp
