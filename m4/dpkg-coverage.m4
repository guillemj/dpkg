# Copyright © 2010 Guillem Jover <guillem@debian.org>

# DPKG_CODE_COVERAGE
# ------------------
# Add configuration option to enable code coverage support.
AC_DEFUN([DPKG_CODE_COVERAGE],
[
AC_ARG_ENABLE(coverage,
	AS_HELP_STRING([--enable-coverage],
	               [whether to enable code coverage]),
	[],
	[enable_coverage=no])
AM_CONDITIONAL(COVERAGE_ENABLED, [test x$enable_coverage = xyes])

if test "x$enable_coverage" = "xyes"; then
   if test "x$GCC" = "xno"; then
     AC_MSG_ERROR([not compiling with gcc, which is required for C coverage support])
   fi

   AC_CHECK_PROGS([GCOV], [gcov])
   if test -z "$GCOV"; then
     AC_MSG_ERROR([missing gcov, which is required for C coverage support])
   fi

   AC_CHECK_PROGS([LCOV], [lcov])
   if test -z "$LCOV"; then
      AC_MSG_ERROR([missing lcov, which is required for C coverage support])
   fi

   AC_CHECK_PROGS([LCOV_GENHTML], [genhtml])
   if test -z "$LCOV_GENHTML"; then
      AC_MSG_ERROR([missing genhtml, which is required for C coverage support])
   fi

   CFLAGS="$CFLAGS -fprofile-arcs -ftest-coverage"
   LDFLAGS="$LDFLAGS -fprofile-arcs -ftest-coverage"

   AC_MSG_CHECKING([for Devel::Cover perl module])
   if $($PERL -e "require Devel::Cover;" 2>/dev/null); then
      PERL_COVERAGE="-MDevel::Cover"
      AC_SUBST(PERL_COVERAGE)
      AC_MSG_RESULT([ok])
   else
      AC_MSG_ERROR([Devel::Cover perl module is required for coverage support])
   fi
   AC_CHECK_PROGS([PERL_COVER], [cover])
   if test -z "$PERL_COVER"; then
      AC_MSG_ERROR([missing cover, which is required for perl coverage support])
   fi
fi
])
