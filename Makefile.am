## Process this file with automake to produce a Makefile.in

AUTOMAKE_OPTIONS	= 1.1 foreign

if HAVE_CPLUSPLUS
CPPSUBDIRS		= dselect methods
else
CPPSUBDIRS		=
endif

SUBDIRS			= po intl include lib main dpkg-deb split \
			  md5sum scripts utils $(CPPSUBDIRS) doc

## Directory definitions

pkglocalstatedir	= $(sharedstatedir)/@PACKAGE@
pkglibdir		= $(libdir)/@PACKAGE@

docdir			= $(prefix)/doc
pkgdocdir		= $(docdir)/@PACKAGE@

## Various options

CFLAGS			= @CFLAGS@ @CWARNS@ -g $(XCFLAGS)
OPTCFLAGS		= @OPTCFLAGS@ @CWARNS@ -g $(XCFLAGS)
LDFLAGS			= @LDFLAGS@ $(XLDFLAGS)
LIBS			= @LIBS@ $(XLIBS)

export CFLAGS OPTCFLAGS LDFLAGS LIBS

## Automake variables

# Can set this to "build" (wrapper found in debmake)
DEBIAN_BUILD		= dpkg-buildpackage

# May want to add -a<arch>?
DEBIAN_FLAGS		=

BUILT_SOURCES		= version.h config.h
EXTRA_DIST		= archtable COPYING INSTALL 

CLEANFILES		= version.h.new
DISTCLEANFILES		= version.h config.h
MAINTAINERCLEANFILES	= libtool

DISTDEBFILES		= 50dpkg-dev.el changelog control copyright \
			  dev-README postinst preinst prerm rules \
			  shlibs shlibs.default.templates shlibs.local

MAINTCLEANFILES		= Makefile.in aclocal.m4 config.guess \
			  config.h.in config.sub configure install-sh \
			  ltconfig ltmain.sh mkinstalldirs ABOUT-NLS \
			  po/Makefile.in.in po/stamp-cat-id po/cat-id-tbl.c \
			  po/dpkg.pot stamp-h.in missing
## Rules

.PHONY: install-data-local uninstall-local dist-hook maintainer-clean-local

uninstall-local:
	-for d in $(pkglocalstatedir) $(pkglibdir) $(pkgdocdir); do \
		[ -e $$d ] && rmdir $$d; \
	done

dist-hook:
	$(mkinstalldirs) $(distdir)/debian
	set -e; for i in $(DISTDEBFILES); do \
		cp -p $(srcdir)/debian/$$i $(distdir)/debian/; \
	done
	$(mkinstalldirs) $(distdir)/automake
	cp -dp $(top_srcdir)/automake/[a-z]* $(distdir)/automake/

maintainer-clean-local:
	-cd $(srcdir) && rm -f $(MAINTCLEANFILES)
	-$(RM) -r $(srcdir)/intl

## End of file.
