## Process this file with automake to produce Makefile.in

if WITH_DSELECT
  MAYBE_DSELECT = dselect
endif

SUBDIRS = \
	libcompat \
	lib \
	src \
	$(MAYBE_DSELECT) \
	dpkg-deb \
	dpkg-split \
	utils \
	scripts \
	po \
	origins \
	man

ACLOCAL_AMFLAGS = -I m4


dist_pkgdata_DATA = cputable ostable triplettable

EXTRA_DIST = \
	README.api \
	README.feature-removal-schedule \
	README.translators \
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
	debian/dpkg.docs \
	debian/dpkg.install \
	debian/dpkg.postinst \
	debian/dpkg.postrm \
	debian/dpkg.preinst \
	debian/dpkg.logrotate \
	debian/dpkg.lintian-overrides \
	debian/dselect.cfg \
	debian/dselect.docs \
	debian/dselect.install \
	debian/dselect.preinst \
	debian/dselect.lintian-overrides \
	debian/source.lintian-overrides \
	debian/usertags \
	debian/rules \
	debian/shlibs.default \
	debian/shlibs.override

# If we create the dist tarball from the git repository, make sure
# that we're not forgetting some files...
dist-hook:
	if [ -e .git ]; then \
		for file in `git ls-files | grep -v .gitignore`; do \
			if [ ! -e "$(distdir)/$$file" ]; then \
				echo "$$file is missing in $(distdir)" >&2 ; \
				exit 1 ; \
			fi ; \
		done ; \
	fi

