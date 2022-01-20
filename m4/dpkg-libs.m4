# serial 1
# Copyright © 2004 Scott James Remnant <scott@netsplit.com>
# Copyright © 2007 Nicolas François <nicolas.francois@centraliens.net>
# Copyright © 2006, 2009-2012, 2014-2015 Guillem Jover <guillem@debian.org>

# DPKG_LIB_MD
# -----------
# Check for the message digest library.
AC_DEFUN([DPKG_LIB_MD], [
  AC_ARG_VAR([MD_LIBS], [linker flags for md library])
  AC_ARG_WITH([libmd],
    [AS_HELP_STRING([--with-libmd],
      [use libmd library for message digest functions])],
    [], [with_libmd=check])
  have_libmd="no"
  AS_IF([test "x$with_libmd" != "xno"], [
    AC_CHECK_HEADERS([md5.h], [
      dpkg_save_libmd_LIBS=$LIBS
      AC_SEARCH_LIBS([MD5Init], [md])
      LIBS=$dpkg_save_libmd_LIBS
      AS_IF([test "x$ac_cv_search_MD5Init" = "xnone required"], [
        have_libmd="builtin"
      ], [test "x$ac_cv_search_MD5Init" != "xno"], [
        have_libmd="yes"
        MD_LIBS="$ac_cv_search_MD5Init"
      ])
    ])
    AS_IF([test "x$with_libmd" = "xyes" && test "x$have_libmd" = "xno"], [
      AC_MSG_FAILURE([md5 digest functions not found])
    ])
  ])
  AM_CONDITIONAL([HAVE_LIBMD_MD5], [test "x$have_libmd" != "xno"])
])# DPKG_LIB_MD

# DPKG_WITH_COMPRESS_LIB(NAME, HEADER, FUNC)
# -------------------------------------------------
# Check for availability of a compression library.
AC_DEFUN([DPKG_WITH_COMPRESS_LIB], [
  AC_ARG_VAR(AS_TR_CPP([$1_LIBS]), [linker flags for $1 library])
  AC_ARG_WITH([lib$1],
    [AS_HELP_STRING([--with-lib$1],
      [use $1 library for compression and decompression])],
    [], [AS_TR_SH([with_lib$1])=check])
  AS_TR_SH([have_lib$1])="no"
  AS_IF([test "x$AS_TR_SH([with_lib$1])" != "xno"], [
    AC_CHECK_LIB([$1], [$3], [
      AC_CHECK_HEADER([$2], [
        AS_TR_SH([have_lib$1])="yes"
      ])
    ])

    AS_IF([test "x$AS_TR_SH([with_lib$1])" != "xno"], [
      AS_IF([test "x$AS_TR_SH([have_lib$1])" = "xyes"], [
        AC_DEFINE(AS_TR_CPP([WITH_LIB$1]), 1,
          [Define to 1 to use $1 library rather than console tool])
        AS_IF([test "x$AS_TR_SH([with_lib$1])" = "xstatic"], [
          AS_TR_SH([dpkg_$1_libs])="-Wl,-Bstatic -l$1 -Wl,-Bdynamic"
        ], [
          AS_TR_SH([dpkg_$1_libs])="-l$1"
        ])
        AS_TR_CPP([$1_LIBS])="${AS_TR_CPP([$1_LIBS]):+$AS_TR_CPP([$1_LIBS]) }$AS_TR_SH([dpkg_$1_libs])"
      ], [
        AS_IF([test "x$AS_TR_SH([with_lib$1])" != "xcheck"], [
          AC_MSG_FAILURE([lib$1 library or header not found])
        ])
      ])
    ])
  ])
])# DPKG_WITH_COMPRESS_LIB

# DPKG_LIB_Z
# ----------
# Check for z-ng and z libraries.
AC_DEFUN([DPKG_LIB_Z], [
  DPKG_WITH_COMPRESS_LIB([z], [zlib.h], [gzdopen])
  DPKG_WITH_COMPRESS_LIB([z-ng], [zlib-ng.h], [zng_gzdopen])

  AC_DEFINE([USE_LIBZ_IMPL_NONE], [0],
            [Define none as 0 for the zlib implementation enum])
  AC_DEFINE([USE_LIBZ_IMPL_ZLIB], [1],
            [Define zlib as 1 for the zlib implementation enum])
  AC_DEFINE([USE_LIBZ_IMPL_ZLIB_NG], [2],
            [Define zlib-ng as 2 for the zlib implementation enum])

  # If we have been requested the stock zlib, override the auto-detection.
  AS_IF([test "x$with_libz" != "xyes" && test "x$have_libz_ng" = "xyes"], [
    AC_DEFINE([WITH_GZFILEOP], [yes],
      [Define to yes to use zlib-ng gzFile IO support])
    Z_LIBS=$Z_NG_LIBS
    use_libz_impl="USE_LIBZ_IMPL_ZLIB_NG"
    have_libz_impl="yes (zlib-ng)"
  ], [test "x$have_libz" = "xyes"], [
    use_libz_impl="USE_LIBZ_IMPL_ZLIB"
    have_libz_impl="yes (zlib)"
  ], [
    use_libz_impl="USE_LIBZ_IMPL_NONE"
    have_libz_impl="no"
  ])
  AC_DEFINE_UNQUOTED([USE_LIBZ_IMPL], [$use_libz_impl],
                     [Define to the zlib implementation to use])
])# DPKG_LIB_Z

# DPKG_LIB_LZMA
# -------------
# Check for lzma library.
AC_DEFUN([DPKG_LIB_LZMA], [
  DPKG_WITH_COMPRESS_LIB([lzma], [lzma.h], [lzma_alone_decoder])
  AC_CHECK_LIB([lzma], [lzma_stream_encoder_mt], [
    AC_DEFINE([HAVE_LZMA_MT_ENCODER], [1],
              [xz multithreaded compression support])
  ])
])# DPKG_LIB_LZMA

# DPKG_LIB_BZ2
# ------------
# Check for bz2 library.
AC_DEFUN([DPKG_LIB_BZ2], [
  DPKG_WITH_COMPRESS_LIB([bz2], [bzlib.h], [BZ2_bzdopen])
])# DPKG_LIB_BZ2

# DPKG_LIB_SELINUX
# ----------------
# Check for selinux library.
AC_DEFUN([DPKG_LIB_SELINUX], [
  AC_REQUIRE([PKG_PROG_PKG_CONFIG])
  m4_ifndef([PKG_PROG_PKG_CONFIG], [m4_fatal([missing pkg-config macros])])
  AC_ARG_VAR([SELINUX_LIBS], [linker flags for selinux library])dnl
  AC_ARG_WITH([libselinux],
    [AS_HELP_STRING([--with-libselinux],
      [use selinux library to set security contexts])],
    [], [with_libselinux=check])
  SELINUX_MIN_VERSION=2.3
  have_libselinux="no"
  AS_IF([test "x$with_libselinux" != "xno"], [
    PKG_CHECK_MODULES([SELINUX], [libselinux >= $SELINUX_MIN_VERSION], [
      AC_CHECK_HEADER([selinux/selinux.h], [
        AC_DEFINE([WITH_LIBSELINUX], [1],
          [Define to 1 to compile in SELinux support])
        have_libselinux="yes"
      ], [
        AS_IF([test "x$with_libselinux" != "xcheck"], [
          AC_MSG_FAILURE([libselinux header not found])
        ])
      ])
      AC_CHECK_LIB([selinux], [setexecfilecon], [], [
        AC_MSG_FAILURE([libselinux does not support setexecfilecon()])
      ])
    ], [
      AS_IF([test "x$with_libselinux" != "xcheck"], [
        AC_MSG_FAILURE([libselinux at least $SELINUX_MIN_VERSION not found])
      ])
    ])
  ])
  AM_CONDITIONAL([WITH_LIBSELINUX], [test "x$have_libselinux" = "xyes"])
])# DPKG_LIB_SELINUX

# _DPKG_CHECK_LIB_CURSES_NARROW
# -----------------------------
# Check for narrow curses library.
AC_DEFUN([_DPKG_CHECK_LIB_CURSES_NARROW], [
  AC_CHECK_LIB([ncurses], [initscr], [
    CURSES_LIBS="${CURSES_LIBS:+$CURSES_LIBS }-lncurses"
  ], [
    AC_CHECK_LIB([curses], [initscr], [
      CURSES_LIBS="${CURSES_LIBS:+$CURSES_LIBS }-lcurses"
    ], [
      AC_MSG_ERROR([no curses library found])
    ])
  ])
])# DPKG_CHECK_LIB_CURSES_NARROW

# DPKG_LIB_CURSES
# ---------------
# Check for curses library.
AC_DEFUN([DPKG_LIB_CURSES], [
  AC_REQUIRE([DPKG_UNICODE])
  AC_ARG_VAR([CURSES_LIBS], [linker flags for curses library])dnl
  AC_CHECK_HEADERS([ncurses/ncurses.h ncurses.h curses.h ncurses/term.h term.h],
                   [have_curses_header=yes])
  AS_IF([test "x$USE_UNICODE" = "xyes"], [
    AC_CHECK_HEADERS([ncursesw/ncurses.h ncursesw/term.h],
                     [have_curses_header=yes])
    AC_CHECK_LIB([ncursesw], [initscr], [
      CURSES_LIBS="${CURSES_LIBS:+$CURSES_LIBS }-lncursesw"
    ], [
      _DPKG_CHECK_LIB_CURSES_NARROW()
    ])
  ], [
    _DPKG_CHECK_LIB_CURSES_NARROW()
  ])
  AS_IF([test "x$have_curses_header" != "xyes"], [
    AC_MSG_FAILURE([curses header not found])
  ])
  have_libcurses=yes
])# DPKG_LIB_CURSES

# DPKG_LIB_SOCKET
# ---------------
# Check for socket library
AC_DEFUN([DPKG_LIB_SOCKET], [
  AC_ARG_VAR([SOCKET_LIBS], [linker flags for socket library])dnl
  have_libsocket="no"
  dpkg_save_libsocket_LIBS=$LIBS
  AC_SEARCH_LIBS([bind], [socket])
  LIBS=$dpkg_save_libsocket_LIBS
  AS_IF([test "x$ac_cv_search_bind" = "xnone required"], [
    have_libsocket="builtin"
  ], [test "x$ac_cv_search_bind" != "xno"], [
    have_libsocket="yes"
    SOCKET_LIBS="$ac_cv_search_bind"
  ])
])# DPKG_LIB_SOCKET

# DPKG_LIB_PS
# -----------
# Check for GNU/Hurd ps library
AC_DEFUN([DPKG_LIB_PS], [
  AC_ARG_VAR([PS_LIBS], [linker flags for ps library])dnl
  AC_CHECK_LIB([ps], [proc_stat_list_create], [
    PS_LIBS="-lps"
    have_libps=yes
  ])
])# DPKG_LIB_PS

# DPKG_LIB_KVM
# ------------
# Check for BSD kvm library
AC_DEFUN([DPKG_LIB_KVM], [
  AC_ARG_VAR([KVM_LIBS], [linker flags for kvm library])dnl
  AC_CHECK_LIB([kvm], [kvm_openfiles], [
    KVM_LIBS="-lkvm"
    have_libkvm=yes
  ])
])# DPKG_LIB_KVM
