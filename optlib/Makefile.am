## Process this file with automake to produce Makefile.in
noinst_LIBRARIES = liboptlib.a

EXTRA_DIST = getdate.c

INCLUDES = -I.. -I$(srcdir) 

liboptlib_a_SOURCES = getopt.c getopt1.c long-options.c closeout.c

#liboptlib_a_LIBADD = @LIBOBJS@ @ALLOCA@
liboptlib_a_DEPENDENCIES = $(liboptlib_a_LIBADD)

noinst_HEADERS = getopt.h long-options.h closeout.h error.h

BUILT_SOURCES = 

# Remove these files here... they are created locally
DISTCLEANFILES = $(BUILT_SOURCES) .deps/* *~

