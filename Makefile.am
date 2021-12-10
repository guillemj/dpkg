## Process this file with automake to produce Makefile.in

if BUILD_DSELECT
  MAYBE_DSELECT = dselect
endif

SUBDIRS = \
	lib \
	src \
	utils \
	$(MAYBE_DSELECT) \
	scripts \
	po \
	man \
	# EOL

ACLOCAL_AMFLAGS = -I m4

aclocaldir = $(datadir)/aclocal

dist_aclocal_DATA = \
	m4/dpkg-arch.m4 \
	m4/dpkg-build.m4 \
	m4/dpkg-compiler.m4 \
	m4/dpkg-coverage.m4 \
	m4/dpkg-funcs.m4 \
	m4/dpkg-libs.m4 \
	m4/dpkg-linker.m4 \
	m4/dpkg-progs.m4 \
	m4/dpkg-types.m4 \
	m4/dpkg-unicode.m4 \
	# EOL

dist_pkgdata_DATA = \
	data/pie-compile.specs \
	data/pie-link.specs \
	data/no-pie-compile.specs \
	data/no-pie-link.specs \
	data/cputable \
	data/ostable \
	data/abitable \
	data/tupletable \
	# EOL

dist_doc_DATA = \
	doc/README.api \
	doc/README.feature-removal-schedule \
	doc/frontend.txt \
	doc/protected-field.txt \
	doc/rootless-builds.txt \
	doc/triggers.txt \
	# EOL

EXTRA_DIST = \
	.gitlab-ci.yml \
	.mailmap \
	ChangeLog.old \
	README.l10n \
	autogen \
	build-aux/gen-changelog \
	build-aux/get-version \
	build-aux/lcov-inject \
	build-aux/run-script \
	doc/coding-style.txt \
	debian/README.bug-usertags \
	debian/bug-script \
	debian/changelog \
	debian/control \
	debian/copyright \
	debian/dpkg-dev.docs \
	debian/dpkg-dev.install \
	debian/dpkg-dev.manpages \
	debian/dpkg.alternatives.logrotate \
	debian/dpkg.cfg \
	debian/dpkg.cron.daily \
	debian/dpkg.docs \
	debian/dpkg.dpkg-db-backup.service \
	debian/dpkg.dpkg-db-backup.timer \
	debian/dpkg.install \
	debian/dpkg.manpages \
	debian/dpkg.postinst \
	debian/dpkg.postrm \
	debian/dpkg.logrotate \
	debian/dpkg.lintian-overrides \
	debian/dpkg.lintian-profile \
	debian/dselect.cfg \
	debian/dselect.docs \
	debian/dselect.install \
	debian/dselect.manpages \
	debian/dselect.postrm \
	debian/libdpkg-dev.install \
	debian/libdpkg-perl.install \
	debian/source/format \
	debian/rules \
	debian/shlibs.default \
	debian/shlibs.override \
	debian/tests/control \
	debian/tests/test-func \
	debian/tests/test-func-root \
	debian/tests/test-not-root \
	debian/tests/test-root \
	po/its/polkit.its \
	po/its/polkit.loc \
	tests \
	$(test_scripts) \
	$(test_data) \
	# EOL

.PHONY: doc

doc: doc/Doxyfile
	$(DOXYGEN) doc/Doxyfile

doc-clean:
	rm -rf doc/html/

# Code coverage support

.PHONY: coverage coverage-clean

if COVERAGE_ENABLED
LCOV_OPTS = -q --rc geninfo_checksum=1 --rc lcov_branch_coverage=1
LCOV_CAPTURE_OPTS = $(LCOV_OPTS) --no-recursion \
	-d $(top_builddir)/lib/dpkg \
	-d $(top_builddir)/src \
	-d $(top_builddir)/utils \
	# EOL
LCOV_INJECT = $(PERL) -i $(top_srcdir)/build-aux/lcov-inject

coverage: all
	: # Remove coverage data from any previous run
	rm -f *.lcov
	find -name '*.gcda' -o -name '*.gcov' | xargs rm -f

	: # Initialize data
	$(LCOV) $(LCOV_CAPTURE_OPTS) -c -o dpkg_base.lcov -i
	: # Run test cases
	$(MAKE) -C lib/dpkg check
	$(MAKE) -C src check
	$(MAKE) -C utils check
	: # Merge test coverage data
	$(LCOV) $(LCOV_CAPTURE_OPTS) -c -o dpkg_test.lcov
	$(LCOV) $(LCOV_OPTS) -a dpkg_base.lcov -a dpkg_test.lcov \
	  -o dpkg_merge.lcov
	$(LCOV) $(LCOV_OPTS) -r dpkg_merge.lcov '/usr/include/*' -o dpkg.lcov
	: # Generate reports
	$(LCOV) $(LCOV_OPTS) -l dpkg.lcov
	$(LCOV_GENHTML) $(LCOV_OPTS) \
	  --legend --title "dpkg $(VERSION) C code coverage" \
	  -o doc/coverage dpkg.lcov

	$(MAKE) -C scripts $@

	: # XXX: Inject perl coverage into lcov index files. This is a fragile
	: # hack which might break depending on the html output generated.
	$(LCOV_INJECT) doc/coverage/index-sort-b.html
	$(LCOV_INJECT) doc/coverage/index-sort-f.html
	$(LCOV_INJECT) doc/coverage/index-sort-l.html
	$(LCOV_INJECT) doc/coverage/index.html

coverage-clean:
	rm -rf doc/coverage/
	find -name '*.gcno' -o -name '*.gcda' -o \
	     -name '*.gcov' -o -name '*.lcov' | xargs rm -f
	$(MAKE) -C scripts $@
else
coverage:
	@echo "Need to reconfigure with --enable-coverage"

coverage-clean:
endif

test_scripts = \
	t/po.t \
	t/pod.t \
	t/pod-spell.t \
	t/pod-coverage.t \
	t/synopsis.t \
	t/minimum-version.t \
	t/module-version.t \
	t/syntax.t \
	t/strict.t \
	t/critic.t \
	t/codespell.t \
	t/shellcheck.t \
	t/cppcheck.t \
	# EOL

test_data = \
	t/critic/perlcriticrc \
	t/codespell/stopwords \
	t/cppcheck/cppcheck.supp \
	# EOL

# We need to use absolute paths here due to strict.t invoking a sub-perl,
# while changing dir to source dir on out-of-tree builds.
TEST_ENV_VARS = \
	DPKG_DATADIR=$(abs_top_srcdir)/data \
	# EOL

include $(top_srcdir)/build-aux/tap.am

check-local: tap-check

.PHONY: update-po

update-po:
	$(MAKE) -C po update-po
	$(MAKE) -C scripts/po update-po
	$(MAKE) -C dselect/po update-po
	$(MAKE) -C man update-po

include $(top_srcdir)/build-aux/cpan.am

# If we create the dist tarball from the git repository, make sure
# that we're not forgetting some files, and we are not storing any symlink
# in the repository (except for the origins/default one) as those degrade
# to regular files due to automake telling tar to dereference them.
dist-hook: dist-cpan
	echo $(VERSION) >$(distdir)/.dist-version
	if [ -e .git ]; then \
	  for file in `git ls-tree -r HEAD | grep ^12 | grep -v t/origins/default`; do \
	    echo "$$file is a symlink packed as a file on the dist tar" >&2 ; \
	    exit 1 ; \
	  done ; \
	  for file in `git ls-files | grep -v .gitignore`; do \
	    if [ ! -e "$(distdir)/$$file" ]; then \
	      echo "$$file is missing in $(distdir)" >&2 ; \
	      exit 1 ; \
	    fi ; \
	  done ; \
	  XDG_CONFIG_HOME= HOME= \
	  git log -C --stat 1.15.0.. >$(distdir)/ChangeLog; \
	fi

clean-local: doc-clean coverage-clean tap-clean
