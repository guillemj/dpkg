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
	$(test_cases) \
	$(test_data)


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
	Dpkg/Compression/Compressor.pm \
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
	Dpkg/Shlibs/Cppfilt.pm \
	Dpkg/Source/Archive.pm \
	Dpkg/Source/CompressedFile.pm \
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

TEST_VERBOSE= 0

test_tmpdir = t.tmp

test_cases = \
	t/000_pod.t \
	t/100_Dpkg_Version.t \
	t/190_Dpkg_Shlibs_Cppfilt.t \
	t/200_Dpkg_Shlibs.t \
	t/300_Dpkg_BuildOptions.t \
	t/400_Dpkg_Deps.t \
	t/500_Dpkg_Path.t \
	t/600_Dpkg_Changelog.t \
	t/700_Dpkg_Control.t \
	t/750_Dpkg_Substvars.t \
	t/800_Dpkg_IPC.t \
	t/900_update_alternatives.t

check_DATA = \
	$(test_tmpdir)/200_Dpkg_Shlibs/objdump.basictags-amd64 \
	$(test_tmpdir)/200_Dpkg_Shlibs/objdump.basictags-i386 \
	$(test_tmpdir)/200_Dpkg_Shlibs/objdump.patterns

test_data = \
	t/200_Dpkg_Shlibs/symbols.fake-1 \
	t/200_Dpkg_Shlibs/symbols.fake-2 \
	t/200_Dpkg_Shlibs/symbols.fake-3 \
	t/200_Dpkg_Shlibs/symbols.include-1 \
	t/200_Dpkg_Shlibs/symbols.include-2 \
	t/200_Dpkg_Shlibs/symbols.include-3 \
	t/200_Dpkg_Shlibs/basictags.symbols \
	t/200_Dpkg_Shlibs/basictags.c \
	t/200_Dpkg_Shlibs/patterns.symbols \
	t/200_Dpkg_Shlibs/patterns.cpp \
	t/200_Dpkg_Shlibs/patterns.map \
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
	t/600_Dpkg_Changelog/countme \
	t/600_Dpkg_Changelog/fields \
	t/600_Dpkg_Changelog/misplaced-tz \
	t/600_Dpkg_Changelog/regressions \
	t/600_Dpkg_Changelog/shadow \
	t/700_Dpkg_Control/control-1 \
	t/750_Dpkg_Substvars/substvars1

clean-local:
	rm -fr $(test_tmpdir)

check: $(test_data) $(test_cases)
	$(mkdir_p) $(test_tmpdir)
	PATH="$(top_builddir)/src:$(top_builddir)/scripts:$(PATH)" \
	  srcdir=$(srcdir) DPKG_DATADIR=$(srcdir)/.. \
	  PERL5LIB=$(srcdir) PERL_DL_NONLAZY=1 \
	  $(PERL) -I$(srcdir) -MExtUtils::Command::MM \
	          -e "test_harness($(TEST_VERBOSE), '.')" \
	          $(addprefix $(srcdir)/,$(test_cases))

objdump_lib_name = lib`basename $@`.so
$(test_tmpdir)/200_Dpkg_Shlibs/objdump.basictags-amd64 $(test_tmpdir)/200_Dpkg_Shlibs/objdump.basictags-i386: $(srcdir)/t/200_Dpkg_Shlibs/basictags.c
	$(mkdir_p) $(test_tmpdir)/200_Dpkg_Shlibs
	$(CC) $(CFLAGS) -shared -fPIC -Wl,-soname -Wl,libbasictags.so.1 $< \
	  $(if $(findstring amd64,$@),-DAMD64,) -o $(objdump_lib_name)
	objdump -w -f -p -T -R $(objdump_lib_name) | \
	  sed "s/$(objdump_lib_name)/libbasictags.so.1/g" > $@
	rm -f $(objdump_lib_name)

$(test_tmpdir)/200_Dpkg_Shlibs/objdump.patterns: $(srcdir)/t/200_Dpkg_Shlibs/patterns.cpp $(srcdir)/t/200_Dpkg_Shlibs/patterns.map
	$(mkdir_p) $(test_tmpdir)/200_Dpkg_Shlibs
	$(CXX) $(CXXFLAGS) -shared -fPIC -Wl,-soname -Wl,libpatterns.so.1 \
	    -Wl,--version-script=$(srcdir)/t/200_Dpkg_Shlibs/patterns.map $< \
	    -o $(objdump_lib_name)
	objdump -w -f -p -T -R $(objdump_lib_name) | \
	  sed "s/$(objdump_lib_name)/libpatterns.so.1/g" > $@
	rm -f $(objdump_lib_name)
