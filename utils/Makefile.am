## Process this file with automake to produce Makefile.in

localedir = $(datadir)/locale
INCLUDES = \
	-DLOCALEDIR=\"$(localedir)\" \
	-idirafter $(top_srcdir)/libcompat \
	-I$(top_srcdir)/lib


if WITH_START_STOP_DAEMON
  sbin_PROGRAMS = start-stop-daemon

  start_stop_daemon_SOURCES = \
	start-stop-daemon.c

  start_stop_daemon_LDADD = ../libcompat/libcompat.a $(SSD_LIBS)
endif

EXTRA_DIST = install-info.c
CLEANFILES = install-info install-info-stamp

# Automake has its own install-info rule, gah
all-local: install-info-stamp
install-info-stamp: $(srcdir)/install-info.c
	$(CC) $(CFLAGS) -o install-info $(srcdir)/install-info.c
	touch $@

install-exec-local: install-info-stamp
	$(mkdir_p) $(DESTDIR)$(sbindir)
	$(INSTALL_PROGRAM) install-info $(DESTDIR)$(sbindir)

