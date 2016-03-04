# Copyright © 2004 Scott James Remnant <scott@netsplit.com>
# Copyright © 2007 Nicolas François <nicolas.francois@centraliens.net>
# Copyright © 2006, 2009-2012, 2014-2015 Guillem Jover <guillem@debian.org>

# DPKG_LIB_MD
# -----------
# Check for the message digest library.
AC_DEFUN([DPKG_LIB_MD], [
  AC_ARG_VAR([MD_LIBS], [linker flags for md library])
  AC_CHECK_HEADERS([md5.h], [
    AC_CHECK_LIB([md], [MD5Init], [have_libmd=yes], [
      AC_MSG_FAILURE([md5 digest not found in libmd])
    ])
  ])
  AS_IF([test "x$have_libmd" = "xyes"], [MD_LIBS="-lmd"])
  AM_CONDITIONAL([HAVE_LIBMD_MD5], [test "x$ac_cv_lib_md_MD5Init" = "xyes"])
])# DPKG_LIB_MD

# DPKG_WITH_COMPRESS_LIB(NAME, HEADER, FUNC, LINK)
# -------------------------------------------------
# Check for availability of a compression library.
AC_DEFUN([DPKG_WITH_COMPRESS_LIB], [
  AC_ARG_VAR(AS_TR_CPP($1)[_LIBS], [linker flags for $1 library])
  AC_ARG_WITH($1,
    AS_HELP_STRING([--with-$1],
                   [use $1 library for compression and decompression]))
  if test "x$with_$1" != "xno"; then
    AC_CHECK_LIB([$4], [$3], [
      AC_DEFINE([WITH_]AS_TR_CPP($1), 1,
                [Define to 1 to use $1 rather than console tool])
      if test "x$with_$1" = "xstatic"; then
        dpkg_$1_libs="-Wl,-Bstatic -l$4 -Wl,-Bdynamic"
      else
        dpkg_$1_libs="-l$4"
      fi
      AS_TR_CPP($1)_LIBS="${AS_TR_CPP($1)_LIBS:+$AS_TR_CPP($1)_LIBS }$dpkg_$1_libs"
      with_$1="yes"
    ], [
      if test -n "$with_$1"; then
        AC_MSG_FAILURE([$1 library not found])
      fi
    ])

    AC_CHECK_HEADER([$2], [], [
      if test -n "$with_$1"; then
        AC_MSG_FAILURE([$1 header not found])
      fi
    ])
  fi
])# DPKG_WITH_COMPRESS_LIB

# DPKG_LIB_ZLIB
# -------------
# Check for zlib library.
AC_DEFUN([DPKG_LIB_ZLIB], [
  DPKG_WITH_COMPRESS_LIB([zlib], [zlib.h], [gzdopen], [z])
])# DPKG_LIB_ZLIB

# DPKG_LIB_LZMA
# -------------
# Check for lzma library.
AC_DEFUN([DPKG_LIB_LZMA], [
  DPKG_WITH_COMPRESS_LIB([liblzma], [lzma.h], [lzma_alone_decoder], [lzma])
  AC_CHECK_LIB([lzma], [lzma_stream_encoder_mt],
               [AC_DEFINE([HAVE_LZMA_MT], [1],
                          [xz multithreaded compression support])])
])# DPKG_LIB_LZMA

# DPKG_LIB_BZ2
# ------------
# Check for bz2 library.
AC_DEFUN([DPKG_LIB_BZ2], [
  DPKG_WITH_COMPRESS_LIB([bz2], [bzlib.h], [BZ2_bzdopen], [bz2])
])# DPKG_LIB_BZ2

# DPKG_LIB_SELINUX
# ----------------
# Check for selinux library.
AC_DEFUN([DPKG_LIB_SELINUX], [
AC_REQUIRE([PKG_PROG_PKG_CONFIG])
m4_ifndef([PKG_PROG_PKG_CONFIG], [m4_fatal([missing pkg-config macros])])
AC_ARG_VAR([SELINUX_LIBS], [linker flags for selinux library])dnl
AC_ARG_WITH(selinux,
	AS_HELP_STRING([--with-selinux],
		       [use selinux library to set security contexts]))
if test "x$with_selinux" != "xno"; then
	AC_CHECK_LIB([selinux], [is_selinux_enabled],
		[AC_DEFINE(WITH_SELINUX, 1,
			[Define to 1 to compile in SELinux support])
		PKG_CHECK_EXISTS([libselinux], [
			if test "x$with_selinux" = "xstatic"; then
				dpkg_selinux_libs="-Wl,-Bstatic "$($PKG_CONFIG --static --libs libselinux)" -Wl,-Bdynamic"
			else
				dpkg_selinux_libs=$($PKG_CONFIG --libs libselinux)
			fi
		], [
			if test "x$with_selinux" = "xstatic"; then
				dpkg_selinux_libs="-Wl,-Bstatic -lselinux -lsepol -Wl,-Bdynamic"
			else
				dpkg_selinux_libs="-lselinux"
			fi
		])
		 SELINUX_LIBS="${SELINUX_LIBS:+$SELINUX_LIBS }$dpkg_selinux_libs"
		 with_selinux="yes"],
		[if test -n "$with_selinux"; then
			AC_MSG_FAILURE([selinux library not found])
		 fi])
	AC_CHECK_LIB([selinux], [setexecfilecon],
		[AC_DEFINE([HAVE_SETEXECFILECON], [1],
		           [Define to 1 if SELinux setexecfilecon is present])
	])

	AC_CHECK_HEADER([selinux/selinux.h],,
		[if test -n "$with_selinux"; then
			AC_MSG_FAILURE([selinux header not found])
		 fi])
fi
AM_CONDITIONAL(WITH_SELINUX, [test "x$with_selinux" = "xyes"])
AM_CONDITIONAL(HAVE_SETEXECFILECON,
               [test "x$ac_cv_lib_selinux_setexecfilecon" = "xyes"])
])# DPKG_LIB_SELINUX

# _DPKG_CHECK_LIB_CURSES_NARROW
# -----------------------------
# Check for narrow curses library.
AC_DEFUN([_DPKG_CHECK_LIB_CURSES_NARROW], [
AC_CHECK_LIB([ncurses], [initscr],
  [CURSES_LIBS="${CURSES_LIBS:+$CURSES_LIBS }-lncurses"],
  [AC_CHECK_LIB([curses], [initscr],
     [CURSES_LIBS="${CURSES_LIBS:+$CURSES_LIBS }-lcurses"],
     [AC_MSG_ERROR([no curses library found])])])])
])# DPKG_CHECK_LIB_CURSES_NARROW

# DPKG_LIB_CURSES
# ---------------
# Check for curses library.
AC_DEFUN([DPKG_LIB_CURSES], [
AC_REQUIRE([DPKG_UNICODE])
AC_ARG_VAR([CURSES_LIBS], [linker flags for curses library])dnl
AC_CHECK_HEADERS([ncurses/ncurses.h ncurses.h curses.h ncurses/term.h term.h],
                 [have_curses_header=yes])
if test "x$USE_UNICODE" = "xyes"; then
  AC_CHECK_HEADERS([ncursesw/ncurses.h ncursesw/term.h],
                   [have_curses_header=yes])
  AC_CHECK_LIB([ncursesw], [initscr],
    [CURSES_LIBS="${CURSES_LIBS:+$CURSES_LIBS }-lncursesw"],
    [_DPKG_CHECK_LIB_CURSES_NARROW()])
else
  _DPKG_CHECK_LIB_CURSES_NARROW()
fi
if test "x$have_curses_header" != "xyes"; then
  AC_MSG_FAILURE([curses header not found])
fi
])# DPKG_LIB_CURSES

# DPKG_LIB_PS
# -----------
# Check for GNU/Hurd ps library
AC_DEFUN([DPKG_LIB_PS], [
  AC_ARG_VAR([PS_LIBS], [linker flags for ps library])dnl
  AC_CHECK_LIB([ps], [proc_stat_list_create], [
    PS_LIBS="-lps"
  ])
])# DPKG_LIB_PS

# DPKG_LIB_KVM
# ------------
# Check for BSD kvm library
AC_DEFUN([DPKG_LIB_KVM], [
  AC_ARG_VAR([KVM_LIBS], [linker flags for kvm library])dnl
  AC_CHECK_LIB([kvm], [kvm_openfiles], [
    KVM_LIBS="-lkvm"
  ])
])# DPKG_LIB_KVM
