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
	$(mkinstalldirs) $(methodsmnt)

install-methods-data:
	set -e; for m in $(METHODS); do \
		$(mkinstalldirs) $(methodsdir)/$$m $(methodsdatadir)/$$m; \
		$(INSTALL_DATA) $(srcdir)/$$m.names $(methodsdir)/$$m/names; \
	done

install-descs-data:
	set -e; for x in $(DESCS); do \
		d=`echo $$x | sed 's:.*/\([^/]*\)$$:\1:; s:\.:/:'`; \
		$(INSTALL_DATA) $(srcdir)/$$x $(methodsdir)/$$d; \
	done

install-exec-local:
	set -e; for m in $(METHODS); do \
		$(mkinstalldirs) $(methodsdir)/$$m $(methodsdatadir)/$$m; \
	done
	set -e; for m in $(METHODS); do \
		for s in $(MSCRIPTS); do \
			$(INSTALL_PROGRAM) $(srcdir)/$$m.$$s $(methodsdir)/$$m/$$s; \
		done; \
	done

uninstall-local:
	-for m in $(METHODS); do \
		rm -f $(methodsdir)/$$m/names; \
		[ -e $(methodsdir)/$$m ] && rmdir $(methodsdir)/$$m; \
	done
	-for x in $(DESCS); do \
		d=`echo $$x | sed 's:\.:/:'`; \
		dir=`echo $$d | sed 's:\(.*\)/[^/]*$$:\1:'`; \
		rm -f $(methodsdir)/$$d; \
		[ -e $$dir ] && rmdir $$dir; \
	done
	-for m in $(METHODS); do \
		for s in $(MSCRIPTS); do \
			rm -f $(methodsdir)/$$m/$$s; \
		done; \
		[ -e $(methodsdir)/$$m ] && rmdir $(methodsdir)/$$m; \
		[ -e $(methodsdatadir)/$$m ] && rmdir $(methodsdatadir)/$$m; \
		[ -e $(methodsmnt)/$$m ] && rmdir $(methodsmnt)/$$m; \
	done
	-[ -e $(methodsmnt) ] && rmdir $(methodsmnt)
	-[ -e $(methodsdir) ] && rmdir $(methodsdir)
	-[ -e $(methodsdatadir) ] && rmdir $(methodsdatadir)

dist-hook:
	set -e; for m in $(METHODS); do \
		cp -p $(srcdir)/$$m.names $(distdir)/; \
		for s in $(MSCRIPTS); do \
			cp -p $(srcdir)/$$m.$$s $(distdir)/; \
		done; \
	done
	for d in $(DESCS); do \
		cp -p $(srcdir)/$$d $(distdir)/; \
	done

## End of file.
