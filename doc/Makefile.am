## Process this file with automake to produce a Makefile.in

AUTOMAKE_OPTIONS	= 1.1 foreign

## Directory definitions

docdir			= $(prefix)/doc
pkgdocdir		= $(docdir)/@PACKAGE@

## Subdirectories with translations

SUBDIRS			= ja

## Automake variables

man_MANS		= deb.5 deb-old.5 deb-control.5
pkgdoc_DATA		= 
EXTRA_DIST		= database-structure.fig changelog \
			  manuals-version \
			  $(SGMLFILES) $(man_MANS) \
			  texinfo.dtd \
			  texinfo.texi_mapping texinfo.debian_mapping

HTMLDOCSTAMPS		= internals.html-stamp
HTMLDIRS		= internals.html 
SGMLFILES		= internals.sgml
HARDCOPY		= internals.ps internals.dvi

CLEANFILES		= $(srcdir)/manuals-version.new
DISTCLEANFILES		= 
INFOFILES		= internals.info

## Rules

SUFFIXES		= .html-stamp .sgml .ps .fig .monops

.PHONY: all install-data-local uninstall-local dist-hook clean-local

all: $(HTMLDOCSTAMPS) $(HARDCOPY) $(INFOFILES)

$(srcdir)/manuals-version: $(top_srcdir)/debian/changelog
	v=`dpkg-parsechangelog -l$< | sed -n 's/^Version: //p'` && \
	echo "<!entity manuals-version \"$$v\">" >$@.new
	echo "<!entity dpkg-version \"$(VERSION)\">" >>$@.new
	(cmp -s $@.new $@ || mv -f $@.new $@) && rm -f $@.new

internals.sgmls: internals.sgml texinfo.dtd manuals-version
	nsgmls $< > $@ || ($(RM) $@ && false)

internals.texi: internals.sgmls texinfo.texi_mapping
	sgmlsasp $(srcdir)/texinfo.texi_mapping < $< > $@ || ($(RM) $@ && false)
	perl -pi -e 's/printindex FN/printindex fn/' $@ || ($(RM) $@ && false)

internals.ps: internals.dvi
	dvips -t letter -o $@ $^

internals.dvi: internals.texi
	texi2dvi $^

internals.info: internals.texi
	# WTA: We force makeinfo and ignore errors, since we use a broken method
	# to generate the texi-file anyway. Since we are supposed to switch to the
	# dpkg-iwj branch soon anyway fixing this correctly is more trouble then
 	# it's worth
	-makeinfo --force $^

internals.html-stamp: internals.texi
	-$(RM) -r $*.html*
	mkdir $*.html
	(cd $*.html && texi2html -monolithic ../$<)
	ln -s internals.html $*.html/index.html
	touch $@

database-structure.ps: database-structure.fig
	fig2dev -L ps -c -l _ -P <$< >ps
	mv -f ps $@

database-structure.monops: database-structure.ps
	perl -pe 's:^/(col[0-7]) \{[01 ]*1[01 ]* setrgbcolor\}\
 bind def$$::/$$1 {} bind def:' $< >ps
	mv -f ps $@

install-data-local: $(HTMLDOCSTAMPS)
	$(mkinstalldirs) $(pkgdocdir)
	$(INSTALL_DATA) $(top_srcdir)/debian/changelog $(pkgdocdir)/changelog
	$(INSTALL_DATA) $(srcdir)/changelog $(pkgdocdir)/changelog.manuals
	set -e; for f in $^; do \
		g=`echo $$f | sed -e 's/-stamp$$//'`; \
		cp -r $$g $(pkgdocdir)/`basename $$g`; \
	done

uninstall-local:
	-$(RM) $(pkgdocdir)/changelog.manuals $(pkgdocdir)/changelog
	-cd $(pkgdocdir) && rm -rf $(HTMLDIRS)

dist-hook: $(HTMLDOCSTAMPS) $(HARDCOPY) internals.sgmls internals.texi internals.info
	cp -p $^ $(distdir)
	for f in `echo $^ | tr ' \t' '\n\n' | sed -ne 's:.html-stamp::gp'`; do set -e; \
		$(RM) -r $(distdir)/`basename $$f.html`; \
		mkdir $(distdir)/`basename $$f.html`; \
		cp -p $$f.html/* $(distdir)/`basename $$f.html`; \
	done
	$(RM) -r $(distdir)/obsolete
	cp -rp $(srcdir)/obsolete $(distdir)/
	cp -p $(HARDCOPY) $(distdir)/

maintainer-clean-local: doc-clean
	$(RM) manuals-version
	-$(RM) $(srcdir)/Makefile.in 

doc-clean:
	-$(RM) *.{aux,cp,dvi,fn,ky,log,pg,toc,tp,vr,bak}
	-$(RM) internals.{FN,fns,sgmls,texi,info*}
	-$(RM) -r {packaging,internals}.{texi,html-stamp,text,ps,lout}
	-$(RM) -r {packaging,internals}.html
	-$(RM) manuals-version*

## End of file.
