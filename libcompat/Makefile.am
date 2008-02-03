## Process this file with automake to produce Makefile.in

localedir = $(datadir)/locale
INCLUDES = \
	-DLOCALEDIR=\"$(localedir)\" \
	-I$(top_srcdir)/lib


noinst_LIBRARIES = libcompat.a

libcompat_a_SOURCES = \
	getopt.c getopt.h \
	getopt1.c \
	obstack.c obstack.h
