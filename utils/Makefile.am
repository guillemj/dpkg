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

