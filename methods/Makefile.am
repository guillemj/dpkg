## Process this file with automake to produce a Makefile.in

AUTOMAKE_OPTIONS	= 1.1 foreign

## Directory definitions

pkglibdir		= $(libdir)/@PACKAGE@
pkglocalstatedir	= $(sharedstatedir)/@PACKAGE@

methodsdir		= $(pkglibdir)/methods
methodsdatadir		= $(pkglocalstatedir)/methods
methodsmnt		= $(methodsdatadir)/mnt

## Automake variables

MSCRIPTS		= setup update install
METHODS			= disk floppy
DESCS			= disk.desc.harddisk disk.desc.mounted disk.desc.cdrom \
			  disk.desc.nfs floppy.desc.floppy

MAINTAINERCLEANFILES	= $(srcdir)/Makefile.in

## Rules

.PHONY: install-data-local install-methods-data install-descs-data \
	install-exec-local dist-hook uninstall-local

install-data-local: install-methods-data install-descs-data
	$(mkinstalldirs) $(DESTDIR)$(methodsmnt)

install-methods-data:
	set -e; for m in $(METHODS); do \
		$(mkinstalldirs) $(DESTDIR)$(methodsdir)/$$m \
			$(DESTDIR)$(methodsdatadir)/$$m; \
		$(INSTALL_DATA) $(srcdir)/$$m.names \
			$(DESTDIR)$(methodsdir)/$$m/names; \
	done

install-descs-data:
	set -e; for x in $(DESCS); do \
		d=`echo $$x | sed 's:.*/\([^/]*\)$$:\1:; s:\.:/:'`; \
		$(INSTALL_DATA) $(srcdir)/$$x $(DESTDIR)$(methodsdir)/$$d; \
	done

install-exec-local:
	set -e; for m in $(METHODS); do \
		$(mkinstalldirs) $(DESTDIR)$(methodsdir)/$$m \
			$(DESTDIR)$(methodsdatadir)/$$m; \
	done
	set -e; for m in $(METHODS); do \
		for s in $(MSCRIPTS); do \
			$(INSTALL_PROGRAM) $(srcdir)/$$m.$$s \
				$(DESTDIR)$(methodsdir)/$$m/$$s; \
		done; \
	done

uninstall-local:
	-for m in $(METHODS); do \
		rm -f $(DESTDIR)$(methodsdir)/$$m/names; \
		[ -e $(DESTDIR)$(methodsdir)/$$m ] && rmdir \
			$(DESTDIR)$(methodsdir)/$$m; \
	done
	-for x in $(DESCS); do \
		d=`echo $$x | sed 's:\.:/:'`; \
		dir=`echo $$d | sed 's:\(.*\)/[^/]*$$:\1:'`; \
		rm -f $(DESTDIR)$(methodsdir)/$$d; \
		[ -e $(DESTDIR)$$dir ] && rmdir $(DESTDIR)$$dir; \
	done
	-for m in $(METHODS); do \
		for s in $(MSCRIPTS); do \
			rm -f $(DESTDIR)$(methodsdir)/$$m/$$s; \
		done; \
		[ -e $(DESTDIR)$(methodsdir)/$$m ] && rmdir \
			$(DESTDIR)$(methodsdir)/$$m; \
		[ -e $(DESTDIR)$(methodsdatadir)/$$m ] && rmdir \
			$(DESTDIR)$(methodsdatadir)/$$m; \
		[ -e $(DESTDIR)$(methodsmnt)/$$m ] && rmdir \
			$(DESTDIR)$(methodsmnt)/$$m; \
	done
	-[ -e $(DESTDIR)$(methodsmnt) ] && rmdir \
		$(DESTDIR)$(methodsmnt)
	-[ -e $(DESTDIR)$(methodsdir) ] && rmdir \
		$(DESTDIR)$(methodsdir)
	-[ -e $(DESTDIR)$(methodsdatadir) ] && rmdir \
		$(DESTDIR)$(methodsdatadir)

dist-hook:
	set -e; for m in $(METHODS); do \
		cp -p $(srcdir)/$$m.names $(DESTDIR)$(distdir)/; \
		for s in $(MSCRIPTS); do \
			cp -p $(srcdir)/$$m.$$s $(DESTDIR)$(distdir)/; \
		done; \
	done
	for d in $(DESCS); do \
		cp -p $(srcdir)/$$d $(DESTDIR)$(distdir)/; \
	done

## End of file.
