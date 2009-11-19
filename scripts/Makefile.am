## Process this file with automake to produce Makefile.in

SUBDIRS = po

bin_SCRIPTS = \
	dpkg-architecture \
	dpkg-buildpackage \
	dpkg-checkbuilddeps \
	dpkg-distaddfile \
	dpkg-divert \
	dpkg-genchanges \
	dpkg-gencontrol \
	dpkg-gensymbols \
	dpkg-name \
	dpkg-parsechangelog \
	dpkg-scanpackages \
	dpkg-scansources \
	dpkg-shlibdeps \
	dpkg-source \
	dpkg-vendor \
	update-alternatives

changelogdir = $(pkglibdir)/parsechangelog
changelog_SCRIPTS = \
	changelog/debian

EXTRA_DIST = \
	README.alternatives \
	dpkg-architecture.pl \
	dpkg-buildpackage.pl \
	dpkg-checkbuilddeps.pl \
	dpkg-distaddfile.pl \
	dpkg-genchanges.pl \
	dpkg-gencontrol.pl \
	dpkg-gensymbols.pl \
	dpkg-name.pl \
	dpkg-parsechangelog.pl \
	dpkg-scanpackages.pl \
	dpkg-scansources.pl \
	dpkg-shlibdeps.pl \
	dpkg-source.pl \
	dpkg-divert.pl \
	dpkg-vendor.pl \
	update-alternatives.pl \
	changelog/debian.pl \
	t/000_pod.t \
	t/100_Dpkg_Version.t \
	t/200_Dpkg_Shlibs.t \
	t/200_Dpkg_Shlibs/symbols.fake-1 \
	t/200_Dpkg_Shlibs/symbols.fake-2 \
	t/200_Dpkg_Shlibs/symbols.fake-3 \
	t/200_Dpkg_Shlibs/symbols.include-1 \
	t/200_Dpkg_Shlibs/symbols.include-2 \
	t/200_Dpkg_Shlibs/symbols.include-3 \
	t/200_Dpkg_Shlibs/symbols.tags.in \
	t/200_Dpkg_Shlibs/symboltags.c \
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
	t/200_Dpkg_Shlibs/objdump.tags-amd64 \
	t/200_Dpkg_Shlibs/objdump.tags-i386 \
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
	t/750_Dpkg_Substvars.t \
	t/750_Dpkg_Substvars/substvars1 \
	t/800_Dpkg_IPC.t \
	t/900_update_alternatives.t

CLEANFILES = \
	$(bin_SCRIPTS) $(changelog_SCRIPTS)

perllibdir = $(PERL_LIBDIR)
nobase_dist_perllib_DATA = \
	Dpkg/Arch.pm \
	Dpkg/BuildOptions.pm \
	Dpkg/Changelog.pm \
	Dpkg/Changelog/Debian.pm \
	Dpkg/Changelog/Entry.pm \
	Dpkg/Changelog/Entry/Debian.pm \
	Dpkg/Changelog/Parse.pm \
	Dpkg/Checksums.pm \
	Dpkg/Compression.pm \
	Dpkg/Conf.pm \
	Dpkg/Control.pm \
	Dpkg/Control/Changelog.pm \
	Dpkg/Control/Fields.pm \
	Dpkg/Control/Info.pm \
	Dpkg/Control/Hash.pm \
	Dpkg/Control/Types.pm \
	Dpkg/Deps.pm \
	Dpkg/ErrorHandling.pm \
	Dpkg/Exit.pm \
	Dpkg/Gettext.pm \
	Dpkg/Index.pm \
	Dpkg/IPC.pm \
	Dpkg/Path.pm \
	Dpkg/Shlibs.pm \
	Dpkg/Shlibs/Objdump.pm \
	Dpkg/Shlibs/Symbol.pm \
	Dpkg/Shlibs/SymbolFile.pm \
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
	Dpkg/Substvars.pm \
	Dpkg/Vars.pm \
	Dpkg/Vendor.pm \
	Dpkg/Vendor/Debian.pm \
	Dpkg/Vendor/Default.pm \
	Dpkg/Vendor/Ubuntu.pm \
	Dpkg/Version.pm \
	Dpkg.pm

do_perl_subst = $(AM_V_GEN) \
		sed -e "s:^\#![:space:]*/usr/bin/perl:\#!$(PERL):" \
		    -e "s:\$$dpkglibdir[[:space:]]*=[[:space:]]*['\"][^'\"]*['\"]:\$$dpkglibdir=\"$(pkglibdir)\":" \
		    -e "s:\$$pkgdatadir[[:space:]]*=[[:space:]]*['\"][^'\"]*['\"]:\$$pkgdatadir=\"$(pkgdatadir)\":" \
		    -e "s:\$$admindir[[:space:]]*=[[:space:]]*['\"][^'\"]*['\"]:\$$admindir=\"$(admindir)\":" \
		    -e "s:\$$version[[:space:]]*=[[:space:]]*['\"][^'\"]*[\"']:\$$version=\"$(PACKAGE_VERSION)\":"


%: %.pl Makefile
	@test -d `dirname $@` || $(mkdir_p) `dirname $@`
	$(do_perl_subst) <$< >$@
	$(AM_V_at) chmod +x $@

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
	$(mkdir_p) t.tmp
# a bit hacky...
	cp -dRl $(srcdir)/t/200_Dpkg_Shlibs/ld.so.conf* t.tmp/
	PATH="$(top_builddir)/src:$(top_builddir)/scripts:$(PATH)" srcdir=$(srcdir) PERL5LIB=$(srcdir) DPKG_DATADIR=$(srcdir)/.. PERL_DL_NONLAZY=1 $(PERL) -I$(srcdir) "-MExtUtils::Command::MM" "-e" "test_harness($(TEST_VERBOSE), '.')" $(TEST_FILES)

objdump_lib_name = lib`basename $@`.so
$(srcdir)/t/200_Dpkg_Shlibs/objdump.tags-amd64 $(srcdir)/t/200_Dpkg_Shlibs/objdump.tags-i386: $(srcdir)/t/200_Dpkg_Shlibs/symboltags.c
	$(CC) $(CFLAGS) -shared -fPIC -Wl,-soname -Wl,libsymboltags.so.1 $< \
	  $(if $(findstring amd64,$@),-DAMD64,) -o $(objdump_lib_name)
	objdump -w -f -p -T -R $(objdump_lib_name) | \
	  sed "s/$(objdump_lib_name)/libsymboltags.so.1/g" > $@
	rm -f $(objdump_lib_name)

update-objdumps .PHONY: $(srcdir)/t/200_Dpkg_Shlibs/objdump.tags-amd64
update-objdumps .PHONY: $(srcdir)/t/200_Dpkg_Shlibs/objdump.tags-i386
