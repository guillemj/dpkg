## Process this file with automake to produce Makefile.in

bin_SCRIPTS = \
	822-date \
	dpkg-architecture \
	dpkg-buildpackage \
	dpkg-checkbuilddeps \
	dpkg-distaddfile \
	dpkg-genchanges \
	dpkg-gencontrol \
	dpkg-name \
	dpkg-parsechangelog \
	dpkg-scanpackages \
	dpkg-scansources \
	dpkg-shlibdeps \
	dpkg-source

sbin_SCRIPTS = \
	cleanup-info \
	dpkg-divert \
	dpkg-statoverride \
	update-alternatives

changelogdir = $(pkglibdir)/parsechangelog
changelog_SCRIPTS = \
	changelog/debian

EXTRA_DIST = \
	README.alternatives \
	822-date.pl \
	dpkg-architecture.pl \
	dpkg-buildpackage.sh \
	dpkg-checkbuilddeps.pl \
	dpkg-distaddfile.pl \
	dpkg-genchanges.pl \
	dpkg-gencontrol.pl \
	dpkg-name.sh \
	dpkg-parsechangelog.pl \
	dpkg-scanpackages.pl \
	dpkg-scansources.pl \
	dpkg-shlibdeps.pl \
	dpkg-source.pl \
	cleanup-info.pl \
	dpkg-divert.pl \
	dpkg-statoverride.pl \
	install-info.pl \
	update-alternatives.pl \
	changelog/debian.pl

CLEANFILES = \
	$(bin_SCRIPTS) $(sbin_SCRIPTS) $(changelog_SCRIPTS) \
	install-info install-info-stamp


dist_pkglib_SCRIPTS = \
	controllib.pl


do_perl_subst = sed -e "s:^\#![:space:]*/usr/bin/perl:\#!$(PERL):" \
		    -e "s:\$$dpkglibdir[[:space:]]*=[[:space:]]*['\"][^'\"]*['\"]:\$$dpkglibdir=\"$(pkglibdir)\":" \
		    -e "s:\$$pkgdatadir[[:space:]]*=[[:space:]]*['\"][^'\"]*['\"]:\$$pkgdatadir=\"$(pkgdatadir)\":" \
		    -e "s:\$$admindir[[:space:]]*=[[:space:]]*['\"][^'\"]*['\"]:\$$admindir=\"$(admindir)\":" \
		    -e "s:\$$version[[:space:]]*=[[:space:]]*['\"][^'\"]*[\"']:\$$version=\"$(PACKAGE_VERSION)\":"

do_shell_subst = sed -e "s:version=\"[^\"]*\":version=\"$(PACKAGE_VERSION)\":"


%: %.pl Makefile
	@test -d `dirname $@` || $(mkdir_p) `dirname $@`
	$(do_perl_subst) <$< >$@
	chmod +x $@

%.pl: %.pl.in Makefile
	@test -d `dirname $@` || $(mkdir_p) `dirname $@`
	$(do_perl_subst) <$< >$@
	chmod +x $@

%: %.sh Makefile
	@test -d `dirname $@` || $(mkdir_p) `dirname $@`
	$(do_shell_subst) <$< >$@
	chmod +x $@


# Automake has its own install-info rule, gah
all-local: install-info-stamp
install-info-stamp: $(srcdir)/install-info.pl
	$(do_perl_subst) <$< >install-info
	chmod +x install-info
	touch $@

install-exec-local: install-info-stamp
	$(mkdir_p) $(DESTDIR)$(sbindir)
	$(INSTALL_SCRIPT) install-info $(DESTDIR)$(sbindir)

install-data-local:
	$(mkdir_p) $(DESTDIR)$(sysconfdir)/alternatives
	$(INSTALL_DATA) $(srcdir)/README.alternatives $(DESTDIR)$(sysconfdir)/alternatives/README

uninstall-local:
	rm -f $(DESTDIR)$(sysconfdir)/alternatives/README
	rm -f $(DESTDIR)$(sbindir)/install-info
