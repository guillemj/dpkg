## Process this file with automake to produce Makefile.in

SUBDIRS = mk po

bin_SCRIPTS = \
	dpkg-architecture \
	dpkg-buildflags \
	dpkg-buildpackage \
	dpkg-checkbuilddeps \
	dpkg-distaddfile \
	dpkg-genchanges \
	dpkg-gencontrol \
	dpkg-gensymbols \
	dpkg-maintscript-helper \
	dpkg-mergechangelogs \
	dpkg-name \
	dpkg-parsechangelog \
	dpkg-scanpackages \
	dpkg-scansources \
	dpkg-shlibdeps \
	dpkg-source \
	dpkg-vendor

changelogdir = $(pkglibdir)/parsechangelog
changelog_SCRIPTS = \
	changelog/debian

EXTRA_DIST = \
	dpkg-architecture.pl \
	dpkg-buildflags.pl \
	dpkg-buildpackage.pl \
	dpkg-checkbuilddeps.pl \
	dpkg-distaddfile.pl \
	dpkg-genchanges.pl \
	dpkg-gencontrol.pl \
	dpkg-gensymbols.pl \
	dpkg-maintscript-helper.sh \
	dpkg-mergechangelogs.pl \
	dpkg-name.pl \
	dpkg-parsechangelog.pl \
	dpkg-scanpackages.pl \
	dpkg-scansources.pl \
	dpkg-shlibdeps.pl \
	dpkg-source.pl \
	dpkg-vendor.pl \
	changelog/debian.pl \
	$(test_scripts) \
	$(test_data)


CLEANFILES = \
	$(test_data_objects) \
	$(bin_SCRIPTS) $(changelog_SCRIPTS)

perllibdir = $(PERL_LIBDIR)
nobase_dist_perllib_DATA = \
	Dpkg/Arch.pm \
	Dpkg/BuildEnv.pm \
	Dpkg/BuildFlags.pm \
	Dpkg/BuildOptions.pm \
	Dpkg/BuildProfiles.pm \
	Dpkg/Changelog.pm \
	Dpkg/Changelog/Debian.pm \
	Dpkg/Changelog/Entry.pm \
	Dpkg/Changelog/Entry/Debian.pm \
	Dpkg/Changelog/Parse.pm \
	Dpkg/Checksums.pm \
	Dpkg/Compression.pm \
	Dpkg/Compression/FileHandle.pm \
	Dpkg/Compression/Process.pm \
	Dpkg/Conf.pm \
	Dpkg/Control.pm \
	Dpkg/Control/Changelog.pm \
	Dpkg/Control/FieldsCore.pm \
	Dpkg/Control/Fields.pm \
	Dpkg/Control/Info.pm \
	Dpkg/Control/HashCore.pm \
	Dpkg/Control/Hash.pm \
	Dpkg/Control/Types.pm \
	Dpkg/Deps.pm \
	Dpkg/Dist/Files.pm \
	Dpkg/ErrorHandling.pm \
	Dpkg/Exit.pm \
	Dpkg/File.pm \
	Dpkg/Gettext.pm \
	Dpkg/Index.pm \
	Dpkg/Interface/Storable.pm \
	Dpkg/IPC.pm \
	Dpkg/Package.pm \
	Dpkg/Path.pm \
	Dpkg/Shlibs.pm \
	Dpkg/Shlibs/Objdump.pm \
	Dpkg/Shlibs/Symbol.pm \
	Dpkg/Shlibs/SymbolFile.pm \
	Dpkg/Shlibs/Cppfilt.pm \
	Dpkg/Source/Archive.pm \
	Dpkg/Source/Functions.pm \
	Dpkg/Source/Package.pm \
	Dpkg/Source/Package/V1.pm \
	Dpkg/Source/Package/V2.pm \
	Dpkg/Source/Package/V3/Bzr.pm \
	Dpkg/Source/Package/V3/Custom.pm \
	Dpkg/Source/Package/V3/Native.pm \
	Dpkg/Source/Package/V3/Git.pm \
	Dpkg/Source/Package/V3/Quilt.pm \
	Dpkg/Source/Patch.pm \
	Dpkg/Source/Quilt.pm \
	Dpkg/Substvars.pm \
	Dpkg/Util.pm \
	Dpkg/Vars.pm \
	Dpkg/Vendor.pm \
	Dpkg/Vendor/Debian.pm \
	Dpkg/Vendor/Default.pm \
	Dpkg/Vendor/Ubuntu.pm \
	Dpkg/Version.pm \
	Dpkg.pm

# Keep it even if empty to have man3dir correctly set
man3_MANS =

do_perl_subst = $(AM_V_GEN) \
		sed -e "s:^\#![[:space:]]*/usr/bin/perl:\#!$(PERL):" \
		    -e "s:\$$CONFDIR[[:space:]]*=[[:space:]]*['\"][^'\"]*['\"]:\$$CONFDIR='$(pkgconfdir)':" \
		    -e "s:\$$ADMINDIR[[:space:]]*=[[:space:]]*['\"][^'\"]*['\"]:\$$ADMINDIR='$(admindir)':" \
		    -e "s:\$$LIBDIR[[:space:]]*=[[:space:]]*['\"][^'\"]*['\"]:\$$LIBDIR='$(pkglibdir)':" \
		    -e "s:\$$DATADIR[[:space:]]*=[[:space:]]*['\"][^'\"]*['\"]:\$$DATADIR='$(pkgdatadir)':" \
		    -e "s:\$$PROGVERSION[[:space:]]*=[[:space:]]*['\"][^'\"]*[\"']:\$$PROGVERSION='$(PACKAGE_VERSION)':"

do_shell_subst = $(AM_V_GEN) \
		 sed -e "s:^version[[:space:]]*=[[:space:]]*['\"][^'\"]*[\"']:version=\"$(PACKAGE_VERSION)\":"

%: %.pl Makefile
	@test -d `dirname $@` || $(MKDIR_P) `dirname $@`
	$(do_perl_subst) <$< >$@
	$(AM_V_at) chmod +x $@

%: %.sh Makefile
	@test -d `dirname $@` || $(MKDIR_P) `dirname $@`
	$(do_shell_subst) <$< >$@
	$(AM_V_at) chmod +x $@

install-data-local:
if BUILD_POD_DOC
# Install manual pages for perl modules manually as make can't deal
# properly with filenames containing colons
# Remove empty manual pages (perl modules not documented)
	$(MKDIR_P) $(DESTDIR)$(man3dir)
	for module in $(nobase_dist_perllib_DATA); do \
	    name=`echo $$module | sed -e 's|/|::|g' -e 's/\.pm$$//'`; \
	    $(POD2MAN) --utf8 --center=libdpkg-perl --release=$(VERSION) \
		--name="$$name"	--section=3 $(srcdir)/$$module \
		>$(DESTDIR)$(man3dir)/$$name.3; \
	    test -s $(DESTDIR)$(man3dir)/$$name.3 || \
		rm -f $(DESTDIR)$(man3dir)/$$name.3; \
	done
endif

# Ideally we'd use 'sed -i', but unfortunately that's not portable.
install-data-hook:
	cp -p $(DESTDIR)$(perllibdir)/Dpkg.pm \
	      $(DESTDIR)$(perllibdir)/Dpkg.pm.tmp
	$(do_perl_subst) <$(DESTDIR)$(perllibdir)/Dpkg.pm.tmp \
	                 >$(DESTDIR)$(perllibdir)/Dpkg.pm
	rm $(DESTDIR)$(perllibdir)/Dpkg.pm.tmp

uninstall-local:
if BUILD_POD_DOC
	for module in $(nobase_dist_perllib_DATA); do \
	    rm -f $(DESTDIR)$(man3dir)/`echo $$module | sed -e 's|/|::|g' -e 's/\.pm$$/.3/'`; \
	done
endif

coverage: check
	$(PERL_COVER) -silent \
	  -ignore_re '^t/.*\.t' \
	  -outputdir $(top_builddir)/doc/coverage/scripts
	: # Cleanup coverage report index
	$(PERL) -i -p -e "s:$(abs_top_builddir)::" \
	  $(top_builddir)/doc/coverage/scripts/coverage.html

coverage-clean:
	rm -rf cover_db

TEST_ENV_VARS = \
	DPKG_DATADIR=$(srcdir)/.. \
	DPKG_ORIGINS_DIR=$(srcdir)/t/origins
TEST_COVERAGE = $(PERL_COVERAGE)

test_tmpdir = t.tmp

test_scripts = \
	t/Dpkg_Version.t \
	t/Dpkg_Arch.t \
	t/Dpkg_Package.t \
	t/Dpkg_Shlibs_Cppfilt.t \
	t/Dpkg_Shlibs.t \
	t/Dpkg_BuildEnv.t \
	t/Dpkg_BuildFlags.t \
	t/Dpkg_BuildOptions.t \
	t/Dpkg_BuildProfiles.t \
	t/Dpkg_Checksums.t \
	t/Dpkg_ErrorHandling.t \
	t/Dpkg_Exit.t \
	t/Dpkg_File.t \
	t/Dpkg_Gettext.t \
	t/Dpkg_Conf.t \
	t/Dpkg_Deps.t \
	t/Dpkg_Path.t \
	t/Dpkg_Util.t \
	t/Dpkg_Vars.t \
	t/Dpkg_Interface_Storable.t \
	t/Dpkg_Vendor.t \
	t/Dpkg_Changelog.t \
	t/Dpkg_Changelog_Ubuntu.t \
	t/Dpkg_Control.t \
	t/Dpkg_Index.t \
	t/Dpkg_Substvars.t \
	t/Dpkg_IPC.t \
	t/Dpkg_Compression.t \
	t/Dpkg_Source_Functions.t \
	t/Dpkg_Source_Patch.t \
	t/Dpkg_Source_Quilt.t \
	t/Dpkg_Source_Archive.t \
	t/Dpkg_Source_Package.t \
	t/Dpkg_Dist_Files.t \
	t/merge_changelogs.t

test_data = \
	t/Dpkg_Shlibs/symbols.blacklisted \
	t/Dpkg_Shlibs/symbols.blacklist-groups \
	t/Dpkg_Shlibs/symbols.blacklist-filter \
	t/Dpkg_Shlibs/symbols.blacklist-ignore \
	t/Dpkg_Shlibs/symbols.fake-1 \
	t/Dpkg_Shlibs/symbols.fake-2 \
	t/Dpkg_Shlibs/symbols.fake-3 \
	t/Dpkg_Shlibs/symbols.include-1 \
	t/Dpkg_Shlibs/symbols.include-2 \
	t/Dpkg_Shlibs/symbols.include-3 \
	t/Dpkg_Shlibs/basictags.symbols \
	t/Dpkg_Shlibs/basictags.c \
	t/Dpkg_Shlibs/patterns.symbols \
	t/Dpkg_Shlibs/patterns.cpp \
	t/Dpkg_Shlibs/patterns.map \
	t/Dpkg_Shlibs/ld.so.conf \
	t/Dpkg_Shlibs/ld.so.conf_2 \
	t/Dpkg_Shlibs/ld.so.conf.d/normal.conf \
	t/Dpkg_Shlibs/ld.so.conf.d/inf_recurse.conf \
	t/Dpkg_Shlibs/ld.so.conf.d/recursive.conf \
	t/Dpkg_Shlibs/objdump.space \
	t/Dpkg_Shlibs/objdump.basictags-amd64 \
	t/Dpkg_Shlibs/objdump.basictags-i386 \
	t/Dpkg_Shlibs/objdump.blacklisted \
	t/Dpkg_Shlibs/objdump.patterns \
	t/Dpkg_Shlibs/objdump.glib-ia64 \
	t/Dpkg_Shlibs/objdump.libc6-2.3 \
	t/Dpkg_Shlibs/objdump.libc6-2.6 \
	t/Dpkg_Shlibs/objdump.dbd-pg \
	t/Dpkg_Shlibs/objdump.ls \
	t/Dpkg_Source_Patch/c-style.patch \
	t/Dpkg_Source_Patch/ghost-hunk.patch \
	t/Dpkg_Source_Patch/index-+++.patch \
	t/Dpkg_Source_Patch/index-alone.patch \
	t/Dpkg_Source_Patch/index-inert.patch \
	t/Dpkg_Source_Patch/partial.patch \
	t/Dpkg_Changelog/countme \
	t/Dpkg_Changelog/fields \
	t/Dpkg_Changelog/misplaced-tz \
	t/Dpkg_Changelog/regressions \
	t/Dpkg_Changelog/shadow \
	t/Dpkg_Control/control-1 \
	t/Dpkg_Control/bogus-unsigned.dsc \
	t/Dpkg_Control/bogus-armor-double.dsc \
	t/Dpkg_Control/bogus-armor-no-sig.dsc \
	t/Dpkg_Control/bogus-armor-trail.dsc \
	t/Dpkg_Control/bogus-armor-inline.dsc \
	t/Dpkg_Control/bogus-armor-nested.dsc \
	t/Dpkg_Control/bogus-armor-spaces.dsc \
	t/Dpkg_Source_Quilt/parse/debian/patches/series \
	t/Dpkg_Substvars/substvars1 \
	t/Dpkg_Dist_Files/files-byhand \
	t/merge_changelogs/ch-old \
	t/merge_changelogs/ch-a \
	t/merge_changelogs/ch-b \
	t/merge_changelogs/ch-badver-a \
	t/merge_changelogs/ch-badver-b \
	t/merge_changelogs/ch-badver-merged \
	t/merge_changelogs/ch-badver-old \
	t/merge_changelogs/ch-merged \
	t/merge_changelogs/ch-merged-basic \
	t/merge_changelogs/ch-merged-pr \
	t/merge_changelogs/ch-merged-pr-basic \
	t/origins/debian \
	t/origins/default \
	t/origins/gnewsense \
	t/origins/ubuntu

test_data_objects = \
	t/Dpkg_Shlibs/libobjdump.basictags-amd64.so \
	t/Dpkg_Shlibs/libobjdump.basictags-i386.so \
	t/Dpkg_Shlibs/libobjdump.patterns.so

$(srcdir)/t/Dpkg_Shlibs/libobjdump.basictags-amd64.so: $(srcdir)/t/Dpkg_Shlibs/basictags.c
	$(CC) $(CFLAGS) -shared -fPIC -Wl,-soname -Wl,libbasictags.so.1 $< \
	  -DAMD64 -o $@

$(srcdir)/t/Dpkg_Shlibs/libobjdump.basictags-i386.so: $(srcdir)/t/Dpkg_Shlibs/basictags.c
	$(CC) $(CFLAGS) -shared -fPIC -Wl,-soname -Wl,libbasictags.so.1 $< \
	  -o $@

$(srcdir)/t/Dpkg_Shlibs/libobjdump.patterns.so: $(srcdir)/t/Dpkg_Shlibs/patterns.cpp $(srcdir)/t/Dpkg_Shlibs/patterns.map
	$(CXX) $(CXXFLAGS) -shared -fPIC -Wl,-soname -Wl,libpatterns.so.1 \
	    -Wl,--version-script=$(srcdir)/t/Dpkg_Shlibs/patterns.map $< \
	    -o $@

.PHONY: refresh-test-data

OBJDUMP = objdump -w -f -p -T -R

refresh-test-data: $(test_data_objects)
	$(OBJDUMP) $(srcdir)/t/Dpkg_Shlibs/libobjdump.basictags-amd64.so \
	  >$(srcdir)/t/Dpkg_Shlibs/objdump.basictags-amd64
	$(OBJDUMP) $(srcdir)/t/Dpkg_Shlibs/libobjdump.basictags-i386.so \
	  >$(srcdir)/t/Dpkg_Shlibs/objdump.basictags-i386
	$(OBJDUMP) $(srcdir)/t/Dpkg_Shlibs/libobjdump.patterns.so \
	  >$(srcdir)/t/Dpkg_Shlibs/objdump.patterns
	$(OBJDUMP) `which ls` >$(srcdir)/t/Dpkg_Shlibs/objdump.ls

include $(top_srcdir)/check.am

clean-local: check-clean coverage-clean
	rm -fr man
