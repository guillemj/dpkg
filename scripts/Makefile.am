## Process this file with automake to produce a Makefile.in

AUTOMAKE_OPTIONS	= 1.1 foreign

## Directory definitions

pkglibdir		= $(libdir)/@PACKAGE@
pkglocalstatedir	= $(sharedstatedir)/@PACKAGE@

parsechangelogdir	= $(pkglibdir)/parsechangelog
altssysconfdir		= $(pkgsysconfdir)/alternatives
altslocalstatedir	= $(pkglocalstatedir)/alternatives

# This should be $(pkgsysconfdir), but uses $(sysconfdir) for backwards compatibility.
altssysconfdir		= $(sysconfdir)/alternatives


## Automake variables

bin_SCRIPTS		= dpkg-name dpkg-source dpkg-genchanges dpkg-gencontrol \
			  dpkg-shlibdeps dpkg-buildpackage dpkg-parsechangelog \
			  dpkg-distaddfile 822-date dpkg-scanpackages \
			  dpkg-scansources dpkg-architecture

sbin_SCRIPTS		= update-rc.d update-alternatives \
			  install-info dpkg-divert cleanup-info

pkglib_SCRIPTS		= controllib.pl

lisp_LISP		= debian-changelog-mode.el
ELCFILES		= debian-changelog-mode.elc

man_MANS		= dpkg-name.1 dpkg-source.1 822-date.1 update-rc.d.8 \
			  update-alternatives.8 \
			  install-info.8 dpkg-scanpackages.8 \
			  dpkg-scansources.8 dpkg-architecture.1

EXTRA_DIST		= update-rc.d.pl \
			  dpkg-name.sh dpkg-source.pl dpkg-genchanges.pl \
			  dpkg-gencontrol.pl dpkg-shlibdeps.pl \
			  dpkg-buildpackage.sh dpkg-parsechangelog.pl \
			  dpkg-distaddfile.pl 822-date.pl dpkg-scanpackages.pl \
			  update-alternatives.pl install-info.pl dpkg-divert.pl \
			  cleanup-info.pl controllib.pl debian-changelog-mode.el \
			  cl-debian.pl dpkg-architecture.pl dpkg-scansources.pl \
			  $(man_MANS) README.alternatives

noinst_DATA		= cl-debian

LSMANL			= dpkg-gencontrol dpkg-genchanges dpkg-buildpackage \
			  dpkg-distaddfile dpkg-parsechangelog dpkg-shlibdeps

CLEANFILES		= $(bin_SCRIPTS) $(sbin_SCRIPTS) $(noinst_DATA) $(ELCFILES)
MAINTAINERCLEANFILES	= $(srcdir)/Makefile.in $(srcdir)/elisp-comp

## Rules

.PHONY: install-data-local uninstall-local

SUFFIXES		= .pl .sh

dpkg-scansources.8: dpkg-scansources.pl
	pod2man --section=8 $^ > $@

%: %.pl
	sed -e "s:^#![:space:]*/usr/bin/perl:#! $(perlpath):; \
		s:\$$dpkglibdir[[:space:]]*=[[:space:]]*['\"][^'\"]*['\"]:\$$dpkglibdir=\"$(pkglibdir)\":; \
		s:\$$version[[:space:]]*=[[:space:]]*['\"][^'\"]*[\"']:\$$version=\"$(VERSION)\":" \
		< $< > $@.new
	chmod 755 $@.new
	mv $@.new $@

%: %.sh 
	sed -e "s:version=\"[^\"]*\":version=\"$(VERSION)\":" \
		< $< > $@.new
	chmod 755 $@.new
	mv $@.new $@

install-data-local: cl-debian
	$(mkinstalldirs) $(DESTDIR)$(altslocalstatedir) $(DESTDIR)$(altssysconfdir)
	$(INSTALL_DATA) $(srcdir)/README.alternatives $(DESTDIR)$(altssysconfdir)/README
	set -e; for f in $(LSMANL); do ln -sf $(mandir)/man1/dpkg-source.1 $(DESTDIR)$(mandir)/man1/$$f.1; done
	$(mkinstalldirs) $(DESTDIR)$(parsechangelogdir)
	$(INSTALL_PROGRAM) cl-debian $(DESTDIR)$(parsechangelogdir)/debian

uninstall-local:
	$(RM) $(DESTDIR)$(parsechangelogdir)/debian
	-[ -e $(DESTDIR)$(parsechangelogdir) ] && rmdir $(DESTDIR)$(parsechangelogdir)
	set -e; for f in $(LSMANL); do $(RM) $(DESTDIR)$(mandir)/man1/$$f.1; done
	-[ -e $(DESTDIR)$(altssysconfdir) ] && rmdir $(DESTDIR)$(altssysconfdir)
	-[ -e $(DESTDIR)$(altslocalstatedir) ] && rmdir $(DESTDIR)$(altslocalstatedir)

## End of file.
