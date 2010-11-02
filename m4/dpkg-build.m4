# Copyright © 2010 Guillem Jover <guillem@debian.org>

# DPKG_WITH_PROG(PROG)
# --------------
# Allow disabling compilation and usage of specific programs.
AC_DEFUN([DPKG_WITH_PROG], [
  AC_ARG_WITH([$1],
    AS_HELP_STRING([--without-$1], [do not build or use $1]),
    [build_]AS_TR_SH([$1])[=$with_]AS_TR_SH([$1]),
    [build_]AS_TR_SH([$1])[=yes]
  )
  AM_CONDITIONAL([WITH_]AS_TR_CPP([$1]),
                 [test "x$build_]AS_TR_SH([$1])[" = "xyes"])
  AS_IF([test "x$build_]AS_TR_SH([$1])[" = "xyes"], [
    AC_DEFINE([WITH_]AS_TR_CPP([$1]), 1, [Define to 1 if $1 is compiled.])
  ], [
    AC_DEFINE([WITH_]AS_TR_CPP([$1]), 0)
  ])
])# DPKG_WITH_PROG

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
