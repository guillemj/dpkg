## Process this file with automake to produce Makefile.in

dist_pkgdata_DATA = \
	architecture.mk \
	buildflags.mk \
	buildopts.mk \
	buildtools.mk \
	default.mk \
	pkg-info.mk \
	vendor.mk \
	# EOL

SUFFIXES =

include $(top_srcdir)/build-aux/subst.am

# Ideally we'd use '$(SED) -i', but unfortunately that's not portable.
install-data-hook:
	$(do_make_subst) <$(DESTDIR)$(pkgdatadir)/default.mk \
	                 >$(DESTDIR)$(pkgdatadir)/default.mk.new
	mv $(DESTDIR)$(pkgdatadir)/default.mk.new \
	   $(DESTDIR)$(pkgdatadir)/default.mk

	$(do_make_subst) <$(DESTDIR)$(pkgdatadir)/buildtools.mk \
	                 >$(DESTDIR)$(pkgdatadir)/buildtools.mk.new
	mv $(DESTDIR)$(pkgdatadir)/buildtools.mk.new \
	   $(DESTDIR)$(pkgdatadir)/buildtools.mk
