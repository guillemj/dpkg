## Process this file with automake to produce Makefile.in

localedir = $(datadir)/locale
INCLUDES = \
	-DLOCALEDIR=\"$(localedir)\" -I$(top_srcdir)/intl \
	-I$(top_srcdir)/getopt \
	-I$(top_srcdir)/lib


bin_PROGRAMS = md5sum

md5sum_SOURCES = \
	md5sum.c

md5sum_LDADD = $(LIBINTL) ../getopt/libopt.a ../lib/libdpkg.a $(ZLIB_LIBS)


if WITH_START_STOP_DAEMON
  sbin_PROGRAMS = start-stop-daemon

  start_stop_daemon_SOURCES = \
	start-stop-daemon.c

  start_stop_daemon_LDADD = ../getopt/libopt.a $(SSD_LIBS)
endif


pkglib_PROGRAMS = enoent

enoent_SOURCES = \
	enoent.c
