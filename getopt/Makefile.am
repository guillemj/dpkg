## Process this file with automake to produce Makefile.in

localedir = $(datadir)/locale
INCLUDES = \
	-DLOCALEDIR=\"$(localedir)\" -I$(top_srcdir)/intl \
	-I$(top_srcdir)/lib


noinst_LIBRARIES = libopt.a

libopt_a_SOURCES = \
	closeout.c closeout.h \
	error.h \
	getopt.c getopt.h \
	getopt1.c \
	long-options.c long-options.h \
	obstack.c obstack.h
