## Process this file with automake to produce a Makefile.in

AUTOMAKE_OPTIONS	= 1.1 foreign

## Directory definitions

pkgincludedir		= $(includedir)/@PACKAGE@
pkglocalstatedir	= $(localstatedir)/@PACKAGE@
pkgsysconfdir		= $(sysconfdir)/@PACKAGE@

methods_suffix		= methods
pinfo_suffix		= info
pupdates_suffix		= updates
parts_suffix		= parts

## Automake variables

pkginclude_HEADERS	= dpkg.h dpkg-db.h tarfn.h
noinst_HEADERS		= myopt.h
EXTRA_DIST		= dpkg.h.in

BUILT_SOURCES		= # dpkg.h
CLEANFILES		= dpkg.h dpkg.h.new $(BUILT_SOURCES)

MAINTAINERCLEANFILES	= $(srcdir)/Makefile.in

## Rules

.PHONY: install-data-local uninstall-local

install-data-local:
	$(mkinstalldirs) $(DESTDIR)$(pkglocalstatedir)/{$(pinfo_suffix),$(pupdates_suffix)}

uninstall-local:
	-for d in $(pkglocalstatedir)/{$(pinfo_suffix),$(pupdates_suffix)} \
		$(pkgincludedir) $(pkglocalstatedir) $(pkglocalstatedir); do \
		[ -e $$d ] && rmdir $(DESTDIR)$$d; \
	done

dpkg.h: stamp-dpkg.h
stamp-dpkg.h: dpkg.h.in Makefile
	sed 's:^\(#define ADMINDIR[ 	]*"\).*\(".*\):\1$(pkglocalstatedir)\2:; \
		s:^\(#define UPDATESDIR[ 	]*"\).*\(".*\):\1$(pupdates_suffix)/\2:; \
		s:^\(#define INFODIR[ 	]*"\).*\(".*\):\1$(pinfo_suffix)/\2:; \
		s:^\(#define PARTSDIR[ 	]*"\).*\(".*\):\1$(parts_suffix)/\2:; \
		s:^\(#define LIBDIR[ 	]*"\).*\(".*\):\1$(pkglibdir)/\2:; \
		s:^\(#define METHODSDIR[ 	]*"\).*\(".*\):\1$(methods_suffix)\2:' \
		< $< > dpkg.h.new
	(cmp -s dpkg.h.new dpkg.h) || mv -f dpkg.h.new dpkg.h
	touch $@

## End of file.
