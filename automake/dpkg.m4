dnl DPKG_CACHED_TRY_COMPILE(<description>,<cachevar>,<include>,<program>,<ifyes>,<ifno>)
AC_DEFUN(DPKG_CACHED_TRY_COMPILE,[
 AC_MSG_CHECKING($1)
 AC_CACHE_VAL($2,[
  AC_TRY_COMPILE([$3],[$4],[$2=yes],[$2=no])
 ])
 if test "x$$2" = xyes; then
  true
  $5
 else
  true
  $6
 fi
])

dnl DPKG_C_GCC_TRY_WARNS(<warnings>,<cachevar>)
AC_DEFUN(DPKG_C_GCC_TRY_WARNS,[
 AC_MSG_CHECKING([GCC warning flag(s) $1])
 if test "${GCC-no}" = yes
 then
  AC_CACHE_VAL($2,[
   oldcflags="${CFLAGS-}"
   CFLAGS="${CFLAGS-} ${CWARNS} $1 -Werror"
   AC_TRY_COMPILE([
#include <string.h>
#include <stdio.h>
],[
    strcmp("a","b"); fprintf(stdout,"test ok\n");
], [$2=yes], [$2=no])
   CFLAGS="${oldcflags}"])
  if test "x$$2" = xyes; then
   CWARNS="${CWARNS} $1"
   AC_MSG_RESULT(ok)
  else
   $2=''
   AC_MSG_RESULT(no)
  fi
 else
  AC_MSG_RESULT(no, not using GCC)
 fi
])
dnl DPKG_CACHED_TRY_COMPILE(<description>,<cachevar>,<include>,<program>,<ifyes>,<ifno>)


dnl Check if a #define is present in an include file
AC_DEFUN(DPKG_CHECK_DEFINE,
  [AC_CACHE_CHECK(if $1 is defined in $2,
     ac_cv_define_$1,
     [AC_TRY_COMPILE([
#include <$2>
        ],[
int i = $1;
        ],
        ac_cv_define_$1=yes,
        ac_cv_define_$1=no)
     ])
   if test "$ac_cv_define_$1" = yes ; then
    AC_DEFINE(HAVE_$1,,[define if $1 is defined])
  fi
])

