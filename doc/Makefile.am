## Process this file with automake to produce a Makefile.in

AUTOMAKE_OPTIONS	= 1.1 foreign

## Directory definitions

docdir			= $(datadir)/doc
pkgdocdir		= $(docdir)/@PACKAGE@

## Subdirectories with translations

SUBDIRS			= ja

## Automake variables

man_MANS		= deb.5 deb-old.5 deb-control.5
pkgdoc_DATA		= 
EXTRA_DIST		= database-structure.fig ChangeLog \
			  $(SGMLFILES) $(man_MANS)

HTMLDIRS		= internals.html 
SGMLFILES		= internals.sgml
HARDCOPY		= internals.ps internals.html internals.info

CLEANFILES		= $(srcdir)/manuals-version.new
DISTCLEANFILES		= manuals-version
INFOFILES		= internals.info

## Rules

#SUFFIXES		= .html .sgml .ps .fig .monops

.PHONY: all install-data-local uninstall-local dist-hook clean-local

all:
	@echo Nothing built by default, use \`make internals\' to build docs

internals.sgml: $(srcdir)/manuals-version

internals: $(HARDCOPY)

$(srcdir)/manuals-version: $(top_srcdir)/debian/changelog
	v=`dpkg-parsechangelog -l$< | sed -n 's/^Version: //p'` && \
	echo "<!entity manuals-version \"$$v\">" >$@.new
	echo "<!entity dpkg-version \"$(VERSION)\">" >>$@.new
	(cmp -s $@.new $@ || mv -f $@.new $@) && rm -f $@.new

internals.texinfo: internals.sgml
	debiandoc2texinfo $<

internals.ps: internals.sgml
	debiandoc2ps -1 $<

internals.dvi: internals.sgml
	debiandoc2dvi $<

internals.info: internals.sgml
	debiandoc2info $<

internals.html: $(srcdir)/internals.sgml
	debiandoc2html $<

database-structure.ps: database-structure.fig
	fig2dev -L ps -c -l _ -P <$< >ps
	mv -f ps $@

database-structure.monops: database-structure.ps
	perl -pe 's:^/(col[0-7]) \{[01 ]*1[01 ]* setrgbcolor\}\
 bind def$$::/$$1 {} bind def:' $< >ps
	mv -f ps $@

install-data-local:
	$(mkinstalldirs) $(DESTDIR)$(pkgdocdir)
	$(INSTALL_DATA) $(top_srcdir)/debian/changelog $(DESTDIR)$(pkgdocdir)/changelog
	$(INSTALL_DATA) $(srcdir)/ChangeLog $(DESTDIR)$(pkgdocdir)/changelog.manuals

internals-install: $(HARDCOPY)
	$(mkinstalldirs) $(DESTDIR)$(pkgdocdir)
	set -e; for f in internals.ps internals.html; do \
		cp -r $$f $(DESTDIR)$(pkgdocdir)/`basename $$f`; \
	done
	$(mkinstalldirs) $(DESTDIR)$(infodir)
	$(INSTALL_DATA) internals.info $(DESTDIR)$(infodir)

doc-clean:
	-$(RM) *.{aux,cp,dvi,fn,ky,log,pg,toc,tp,vr,bak}
	-$(RM) internals.{FN,fns,sgmls,texi*,info*}
	-$(RM) manuals-version*

## End of file.
