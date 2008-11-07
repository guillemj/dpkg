## Process this file with automake to produce Makefile.in

SUBDIRS = po

bin_SCRIPTS = \
	822-date \
	dpkg-architecture \
	dpkg-buildpackage \
	dpkg-checkbuilddeps \
	dpkg-distaddfile \
	dpkg-genchanges \
	dpkg-gencontrol \
	dpkg-gensymbols \
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
	dpkg-buildpackage.pl \
	dpkg-checkbuilddeps.pl \
	dpkg-distaddfile.pl \
	dpkg-genchanges.pl \
	dpkg-gencontrol.pl \
	dpkg-gensymbols.pl \
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
	changelog/debian.pl \
	t/000_pod.t \
	t/100_Dpkg_Version.t \
	t/200_Dpkg_Shlibs.t \
	t/200_Dpkg_Shlibs/symbols.fake-1 \
	t/200_Dpkg_Shlibs/symbols.fake-2 \
	t/200_Dpkg_Shlibs/symbols.include-1 \
	t/200_Dpkg_Shlibs/symbols.include-2 \
	t/200_Dpkg_Shlibs/ld.so.conf \
	t/200_Dpkg_Shlibs/ld.so.conf_2 \
	t/200_Dpkg_Shlibs/ld.so.conf.d/normal.conf \
	t/200_Dpkg_Shlibs/ld.so.conf.d/inf_recurse.conf \
	t/200_Dpkg_Shlibs/ld.so.conf.d/recursive.conf \
	t/200_Dpkg_Shlibs/objdump.glib-ia64 \
	t/200_Dpkg_Shlibs/objdump.libc6-2.3 \
	t/200_Dpkg_Shlibs/objdump.libc6-2.6 \
	t/200_Dpkg_Shlibs/objdump.dbd-pg \
	t/200_Dpkg_Shlibs/objdump.ls \
	t/300_Dpkg_BuildOptions.t \
	t/400_Dpkg_Deps.t \
	t/500_Dpkg_Path.t \
	t/600_Dpkg_Changelog.t \
	t/600_Dpkg_Changelog/countme \
	t/600_Dpkg_Changelog/fields \
	t/600_Dpkg_Changelog/misplaced-tz \
	t/600_Dpkg_Changelog/regressions \
	t/600_Dpkg_Changelog/shadow \
	t/700_Dpkg_Control.t \
	t/700_Dpkg_Control/control-1 \
	t/800_Dpkg_IPC.t \
	t/900_Dpkg_Version.t

CLEANFILES = \
	$(bin_SCRIPTS) $(sbin_SCRIPTS) $(changelog_SCRIPTS) \
	install-info install-info-stamp

perllibdir = $(PERL_LIBDIR)
nobase_dist_perllib_DATA = \
	Dpkg/Arch.pm \
	Dpkg/BuildOptions.pm \
	Dpkg/Cdata.pm \
	Dpkg/Changelog.pm \
	Dpkg/Changelog/Debian.pm \
	Dpkg/Checksums.pm \
	Dpkg/Compression.pm \
	Dpkg/Control.pm \
	Dpkg/Deps.pm \
	Dpkg/ErrorHandling.pm \
	Dpkg/Exit.pm \
	Dpkg/Fields.pm \
	Dpkg/Gettext.pm \
	Dpkg/IPC.pm \
	Dpkg/Path.pm \
	Dpkg/Shlibs.pm \
	Dpkg/Shlibs/Objdump.pm \
	Dpkg/Shlibs/SymbolFile.pm \
	Dpkg/Substvars.pm \
	Dpkg/Vars.pm \
	Dpkg/Version.pm \
	Dpkg/Source/Archive.pm \
	Dpkg/Source/CompressedFile.pm \
	Dpkg/Source/Compressor.pm \
	Dpkg/Source/Functions.pm \
	Dpkg/Source/Package.pm \
	Dpkg/Source/Package/V1.pm \
	Dpkg/Source/Package/V2.pm \
	Dpkg/Source/Package/V3/bzr.pm \
	Dpkg/Source/Package/V3/custom.pm \
	Dpkg/Source/Package/V3/native.pm \
	Dpkg/Source/Package/V3/git.pm \
	Dpkg/Source/Package/V3/quilt.pm \
	Dpkg/Source/Patch.pm \
	Dpkg.pm

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

# Ideally we'd use 'sed -i', but unfortunately that's not portable.
install-data-hook:
	cp -p $(DESTDIR)$(perllibdir)/Dpkg.pm \
	      $(DESTDIR)$(perllibdir)/Dpkg.pm.tmp
	$(do_perl_subst) <$(DESTDIR)$(perllibdir)/Dpkg.pm.tmp \
	                 >$(DESTDIR)$(perllibdir)/Dpkg.pm
	rm $(DESTDIR)$(perllibdir)/Dpkg.pm.tmp

uninstall-local:
	rm -f $(DESTDIR)$(sysconfdir)/alternatives/README
	rm -f $(DESTDIR)$(sbindir)/install-info

TEST_FILES= $(srcdir)/t/*.t
TEST_VERBOSE= 0

clean-local:
	[ ! -d t.tmp ] || chmod -R +w t.tmp
	rm -fr t.tmp

check: $(TEST_FILES) $(wildcard $(srcdir)/t/200_Dpkg_Shlibs/ld.so.conf*)
# a bit hacky...
	$(mkdir_p) t.tmp
	cp -dRl $(srcdir)/t/200_Dpkg_Shlibs/ld.so.conf* t.tmp/
	PATH="$(top_builddir)/src:$(top_builddir)/scripts:$(PATH)" srcdir=$(srcdir) PERL5LIB=$(srcdir) DPKG_DATADIR=$(srcdir)/.. PERL_DL_NONLAZY=1 $(PERL) -I$(srcdir) "-MExtUtils::Command::MM" "-e" "test_harness($(TEST_VERBOSE), '.')" $(TEST_FILES)
