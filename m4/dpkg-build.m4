# Copyright © 2010-2014 Guillem Jover <guillem@debian.org>

# DPKG_BUILD_SHARED_LIBS()
# ----------------------
AC_DEFUN([DPKG_BUILD_SHARED_LIBS], [
  m4_pattern_allow([DPKG_DEVEL_MODE])
  AS_IF([test "$enable_shared" = "yes" && test -z "$DPKG_DEVEL_MODE"],
        [AC_MSG_ERROR([building libdpkg as a shared library is not supported])])
  AM_CONDITIONAL([BUILD_SHARED], [test "$enable_shared" = "yes"])
])# DPKG_BUILD_SHARED_LIBS

# DPKG_BUILD_PROG(PROG)
# ---------------
# Allow disabling compilation and usage of specific programs.
AC_DEFUN([DPKG_BUILD_PROG], [
  AC_MSG_CHECKING([whether to build $1])
  AC_ARG_ENABLE([$1],
    AS_HELP_STRING([--disable-$1], [do not build or use $1]),
    [build_]AS_TR_SH([$1])[=$enable_]AS_TR_SH([$1]),
    [build_]AS_TR_SH([$1])[=yes]
  )
  AM_CONDITIONAL([BUILD_]AS_TR_CPP([$1]),
                 [test "x$build_]AS_TR_SH([$1])[" = "xyes"])
  AS_IF([test "x$build_]AS_TR_SH([$1])[" = "xyes"], [
    AC_DEFINE([BUILD_]AS_TR_CPP([$1]), 1, [Define to 1 if $1 is compiled.])
  ], [
    AC_DEFINE([BUILD_]AS_TR_CPP([$1]), 0)
  ])
  AC_MSG_RESULT([$build_]AS_TR_SH([$1]))
])# DPKG_BUILD_PROG

# DPKG_BUILD_DEVEL_DOCS()
# ---------------------
# Select what type of documentation to build. Either for development including
# all symbol references, and extracting everything, or production documentation.
AC_DEFUN([DPKG_BUILD_DEVEL_DOCS], [
  AC_ARG_ENABLE([devel-docs],
    AS_HELP_STRING([--disable-devel-docs], [build release docs]),
    [build_devel_docs=$enable_devel_docs],
    [build_devel_docs=yes]
  )
  AS_IF([test "x$build_devel_docs" = "xyes"], [
    AC_SUBST([BUILD_DEVEL_DOCS], [YES])
  ], [
    AC_SUBST([BUILD_DEVEL_DOCS], [NO])
  ])
])# DPKG_BUILD_DOCS_MODE

# DPKG_WITH_DIR(DIR, DEFAULT, DESCRIPTION)
# -------------
# Allow specifying alternate directories.
AC_DEFUN([DPKG_WITH_DIR], [
  $1="$2"
  AC_ARG_WITH([$1],
    AS_HELP_STRING([--with-$1=DIR], [$3]),
    AS_CASE([$with_$1],
            [""], [AC_MSG_ERROR([invalid $1 specified])],
            [$1="$with_$1"])
  )
  AC_SUBST([$1])
])# DPKG_WITH_DIR

# DPKG_DEB_COMPRESSOR(COMP)
# -------------------
# Change default «dpkg-deb --build» compressor.
AC_DEFUN([DPKG_DEB_COMPRESSOR], [
  AC_ARG_WITH([dpkg-deb-compressor],
    [AS_HELP_STRING([--with-dpkg-deb-compressor=COMP],
                    [change default dpkg-deb build compressor])],
    [with_dpkg_deb_compressor=$withval], [with_dpkg_deb_compressor=$1])
  AS_CASE([$with_dpkg_deb_compressor],
    [gzip|xz|bzip2], [:],
    [AC_MSG_ERROR([unsupported default compressor $with_dpkg_deb_compressor])])
  AC_DEFINE_UNQUOTED([DPKG_DEB_DEFAULT_COMPRESSOR],
                     [COMPRESSOR_TYPE_]AS_TR_CPP(${with_dpkg_deb_compressor}),
                     [default dpkg-deb build compressor])
]) # DPKG_DEB_COMPRESSOR

# DPKG_DIST_CHECK(COND, ERROR)
# ---------------
# Check if the condition is fulfilled when preparing a distribution tarball.
AC_DEFUN([DPKG_DIST_CHECK], [
  AS_IF([test ! -f $srcdir/.dist-version && $1], [
    AC_MSG_ERROR([not building from distributed tarball, $2])
  ])
])# DPKG_DIST_CHECK
