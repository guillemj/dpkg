## Process this file with automake to produce Makefile.in

if WITH_DSELECT
  MAYBE_DSELECT = dselect
endif

SUBDIRS = \
	lib \
	dpkg-deb \
	dpkg-split \
	src \
	utils \
	$(MAYBE_DSELECT) \
	scripts \
	po \
	man

ACLOCAL_AMFLAGS = -I m4


dist_pkgdata_DATA = cputable ostable triplettable

EXTRA_DIST = \
	.mailmap \
	ChangeLog.old \
	README.translators \
	get-version \
	doc/README.api \
	doc/README.feature-removal-schedule \
	doc/coding-style.txt \
	doc/triggers.txt \
	debian/archtable \
	debian/changelog \
	debian/compat \
	debian/control \
	debian/copyright \
	debian/dpkg-dev.docs \
	debian/dpkg-dev.install \
	debian/dpkg-dev.preinst \
	debian/dpkg-dev.lintian-overrides \
	debian/dpkg.cfg \
	debian/dpkg.cron.daily \
	debian/dpkg.docs \
	debian/dpkg.install \
	debian/dpkg.postinst \
	debian/dpkg.postrm \
	debian/dpkg.preinst \
	debian/dpkg.logrotate \
	debian/dpkg.links \
	debian/dpkg.lintian-overrides \
	debian/dselect.cfg \
	debian/dselect.docs \
	debian/dselect.install \
	debian/dselect.preinst \
	debian/dselect.lintian-overrides \
	debian/source.lintian-overrides \
	debian/source/format \
	debian/source/options \
	debian/usertags \
	debian/rules \
	debian/shlibs.default \
	debian/shlibs.override

.PHONY: doc

doc:
	$(DOXYGEN) doc/Doxyfile

clean-local:
	rm -rf doc/html/

.PHONY: ChangeLog
DISTCLEANFILES = ChangeLog

ChangeLog:
	git log -C --stat 1.15.0.. >$@

# If we create the dist tarball from the git repository, make sure
# that we're not forgetting some files...
dist-hook:
	echo $(VERSION) >$(distdir)/.dist-version
	if [ -e .git ]; then \
		for file in `git ls-files | grep -v .gitignore`; do \
			if [ ! -e "$(distdir)/$$file" ]; then \
				echo "$$file is missing in $(distdir)" >&2 ; \
				exit 1 ; \
			fi ; \
		done ; \
	fi

