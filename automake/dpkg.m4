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

dnl DPKG_C_GCC_ATTRIBUTE(<short-label>,<cachevar>,<func-params>,<attribute>,<HAVE>,<desc>,[<true-cmds>],[<false-cmds>])
AC_DEFUN(DPKG_C_GCC_ATTRIBUTE,[
  DPKG_CACHED_TRY_COMPILE(__attribute__(($1)),dpkg_cv_c_attribute_$2,,
   [extern int testfunction($3) __attribute__(($4))],
   AC_MSG_RESULT(yes)
   AC_DEFINE(HAVE_GNUC25_$5,,$6)
   $7,
   AC_MSG_RESULT(no)
   $8)
])

dnl DPKG_C_GCC_TRY_WARNS(<warnings>,<cachevar>)
AC_DEFUN(DPKG_C_GCC_TRY_WARNS,[
 AC_MSG_CHECKING([GCC warning flag(s) $1])
 if test "${GCC-no}" = yes
 then
  AC_CACHE_VAL($2,[
    if $CC $1 -c /dev/null 2>/dev/null; then
      $2=yes
    else
      $2=
    fi
  ])
  if test "x$$2" = xyes; then
   CWARNS="${CWARNS} $1"
   AC_MSG_RESULT(ok)
  else
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

