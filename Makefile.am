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


dist_pkgdata_DATA = cputable ostable

EXTRA_DIST = \
	debian/archtable \
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
	debian/dpkg.logrotate \
	debian/dselect.cfg \
	debian/dselect.install \
	debian/pseudo-tags \
	debian/rules \
	debian/shlibs.default \
	debian/shlibs.override
