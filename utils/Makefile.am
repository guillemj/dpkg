## Process this file with automake to produce Makefile.in

localedir = $(datadir)/locale
AM_CPPFLAGS = \
	-DADMINDIR=\"$(admindir)\" \
	-DLOCALEDIR=\"$(localedir)\" \
	-DLOGDIR=\"$(logdir)\" \
	-DSYSCONFDIR=\"$(sysconfdir)\" \
	-idirafter $(top_srcdir)/lib/compat \
	-I$(top_builddir) \
	-I$(top_srcdir)/lib

EXTRA_DIST = \
	README.alternatives \
	$(test_cases)

bin_PROGRAMS =

if BUILD_UPDATE_ALTERNATIVES
bin_PROGRAMS += update-alternatives
endif

update_alternatives_SOURCES = \
	update-alternatives.c

update_alternatives_LDADD = \
	../lib/compat/libcompat.a \
	$(LIBINTL) \
	$(UA_LIBS)

sbin_PROGRAMS =

if BUILD_START_STOP_DAEMON
sbin_PROGRAMS += start-stop-daemon

start_stop_daemon_SOURCES = \
	start-stop-daemon.c

start_stop_daemon_LDADD = \
	../lib/compat/libcompat.a \
	$(SSD_LIBS)
endif

install-data-local:
if BUILD_UPDATE_ALTERNATIVES
	$(MKDIR_P) $(DESTDIR)$(sysconfdir)/alternatives
	$(MKDIR_P) $(DESTDIR)$(admindir)/alternatives
	$(INSTALL_DATA) $(srcdir)/README.alternatives $(DESTDIR)$(sysconfdir)/alternatives/README
endif

uninstall-local:
	rm -f $(DESTDIR)$(sysconfdir)/alternatives/README

TEST_ENV_VARS = DPKG_DATADIR=$(top_srcdir)

test_tmpdir = t.tmp
test_cases = \
	t/update_alternatives.t

include $(top_srcdir)/check.am

clean-local: check-clean
