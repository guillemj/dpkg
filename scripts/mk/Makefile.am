## Process this file with automake to produce Makefile.in

dist_pkgdata_DATA = \
	architecture.mk \
	buildflags.mk \
	buildopts.mk \
	buildtools.mk \
	default.mk \
	pkg-info.mk \
	vendor.mk

do_path_subst = $(AM_V_GEN) sed \
	-e "s:dpkg_datadir[[:space:]]*=[[:space:]]*[^[:space:]]*:dpkg_datadir = $(pkgdatadir):"

install-data-hook:
	mv $(DESTDIR)$(pkgdatadir)/default.mk \
	   $(DESTDIR)$(pkgdatadir)/default.mk.tmp
	$(do_path_subst) <$(DESTDIR)$(pkgdatadir)/default.mk.tmp \
	                 >$(DESTDIR)$(pkgdatadir)/default.mk
	rm -f $(DESTDIR)$(pkgdatadir)/default.mk.tmp

	mv $(DESTDIR)$(pkgdatadir)/buildtools.mk \
	   $(DESTDIR)$(pkgdatadir)/buildtools.mk.tmp
	$(do_path_subst) <$(DESTDIR)$(pkgdatadir)/buildtools.mk.tmp \
	                 >$(DESTDIR)$(pkgdatadir)/buildtools.mk
	rm -f $(DESTDIR)$(pkgdatadir)/buildtools.mk.tmp
