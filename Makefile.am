## Process this file with automake to produce Makefile.in

if WITH_DSELECT
  MAYBE_DSELECT = dselect
endif

SUBDIRS = \
	intl \
	getopt \
	lib \
	src \
	$(MAYBE_DSELECT) \
	dpkg-deb \
	dpkg-split \
	utils \
	scripts \
	po \
	methods \
	origins \
	man

ACLOCAL_AMFLAGS = -I m4


dist_pkgdata_DATA = archtable

EXTRA_DIST = \
	debian/changelog \
	debian/compat \
	debian/control \
	debian/copyright \
	debian/dpkg-dev.install \
	debian/dpkg.cfg \
	debian/dpkg.docs \
	debian/dpkg.install \
	debian/dpkg.postinst \
	debian/dpkg.postrm \
	debian/dpkg.preinst \
	debian/dpkg.prerm \
	debian/dselect.cfg \
	debian/dselect.install \
	debian/pseudo-tags \
	debian/rules \
	debian/shlibs.default \
	debian/shlibs.override


GAIN_ROOT_COMMAND=fakeroot
TARGET_ARGS=
DPKG_BUILDPACKAGE_ARGS=
LINTIAN_ARGS=

package: distdir
	cd $(distdir) && dpkg-buildpackage \
		-r$(GAIN_ROOT_COMMAND) \
		$(TARGET_ARGS) $(DPKG_BUILDPACKAGE_ARGS)
	$(am__remove_distdir)
	@set -e; \
	if test "x$(TARGET_ARGS)" = "x-S"; then \
	  arch=source; \
	else \
	  arch=`dpkg-architecture $(TARGET_ARGS) -qDEB_HOST_ARCH`; \
	fi; \
	changes=$(PACKAGE)_$(VERSION)_$$arch.changes; \
	test -f $$changes || { echo $$changes missing; exit 1;}; \
	if which lintian >/dev/null; then \
	  echo lintian $(LINTIAN_ARGS) $$changes; \
	  lintian $(LINTIAN_ARGS) $$changes || true; \
	fi; \
	(echo "$(distdir) package files ready for upload: "; \
	  echo $$changes; \
	  sed -e '1,/^Files:/d;/^$$/,$$d;s/.* //g' $$changes) | \
	  sed -e '1{h;s/./=/g;p;x;}' -e '$${p;x;}'
