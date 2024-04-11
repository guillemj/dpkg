## Process this file with automake to produce Makefile.in

dist_pkgdata_DATA = \
	architecture.mk \
	buildapi.mk \
	buildflags.mk \
	buildopts.mk \
	buildtools.mk \
	default.mk \
	pkg-info.mk \
	vendor.mk \
	# EOL

SUFFIXES =

include $(top_srcdir)/build-aux/subst.am

install-data-hook:
	$(subst_make_file) $(DESTDIR)$(pkgdatadir)/default.mk
	$(subst_make_file) $(DESTDIR)$(pkgdatadir)/buildtools.mk
	$(subst_make_file) $(DESTDIR)$(pkgdatadir)/pkg-info.mk
	$(subst_make_file) $(DESTDIR)$(pkgdatadir)/vendor.mk
