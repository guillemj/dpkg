## Process this file with automake to produce Makefile.in

INCLUDES = \
	-idirafter $(top_srcdir)/libcompat


noinst_LIBRARIES = libcompat.a

libcompat_a_SOURCES =

if !HAVE_GETOPT
libcompat_a_SOURCES += getopt.c getopt.h
endif

if !HAVE_GETOPT_LONG
libcompat_a_SOURCES += getopt1.c
endif

if !HAVE_OBSTACK_FREE
libcompat_a_SOURCES += obstack.c obstack.h
endif

if !HAVE_STRNLEN
libcompat_a_SOURCES += strnlen.c strnlen.h
endif

