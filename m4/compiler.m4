# Copyright © 2004 Scott James Remnant <scott@netsplit.com>.

# SJR_COMPILER_WARNINGS
# ---------------------
# Add configure option to enable additional compiler warnings and treat
# them as errors.
AC_DEFUN([SJR_COMPILER_WARNINGS],
[AC_ARG_ENABLE(compiler-warnings,
	AS_HELP_STRING([--enable-compiler-warnings],
	               [Enable additional compiler warnings]),
[if test "x$enable_compiler_warnings" = "xyes"; then
	if test "x$GCC" = "xyes"; then
                CFLAGS="-Wall -Werror $CFLAGS"
        fi
	if test "x$GXX" = "xyes"; then
		CXXFLAGS="-Wall -Werror $CXXFLAGS"
	fi
fi])dnl
])

# SJR_COMPILER_OPTIMISATIONS
# --------------------------
# Add configure option to disable optimisations.
AC_DEFUN([SJR_COMPILER_OPTIMISATIONS],
[AC_ARG_ENABLE(compiler-optimisations,
	AS_HELP_STRING([--disable-compiler-optimisations],
		       [Disable compiler optimisations]),
[if test "x$enable_compiler_optimisations" = "xno"; then
	[CFLAGS=`echo "$CFLAGS" | sed -e "s/ -O[1-9]*\b/ -O0/g"`]
fi])dnl
])

# DPKG_C_ATTRIBUTE
# ----------------
# Check whether the C compiler supports __attribute__, defines HAVE_C_ATTRIBUTE
AC_DEFUN([DPKG_C_ATTRIBUTE],
[AC_CACHE_CHECK([whether compiler supports __attribute__], [dpkg_cv_attribute],
[AC_TRY_COMPILE([],
[extern int testfunction(int x) __attribute__((unused))
],
	[dpkg_cv_attribute=yes],
	[dpkg_cv_attribute=no])])
AS_IF([test "x$dpkg_cv_attribute" = "xyes"],
	[AC_DEFINE([HAVE_C_ATTRIBUTE], 1,
		[Define to 1 if compiler supports `__attribute__', 0 otherwise.])],
	[AC_DEFINE([HAVE_C_ATTRIBUTE], 0)])dnl
])# DPKG_C_ATTRIBUTE

# DPKG_TRY_C99([ACTION-IF-FOUND], [ACTION-IF-NOT-FOUND])
# ------------------------------------------------------
# Try compiling some C99 code to see whether it works
AC_DEFUN([DPKG_TRY_C99],
[AC_TRY_COMPILE([
#include <stdio.h>
#include <stdbool.h>
#include <inttypes.h>


/* Variadic macro arguments */
#define variadic_macro(foo, ...) printf(foo, __VA_ARGS__)
],
[
	/* Compound initialisers */
	struct { int a, b; } foo = { .a = 1, .b = 2 };

	/* Boolean type */
	bool bar = false;

	/* Specific size type */
	uint32_t baz = 0;

	/* C99-style for-loop declarations */
	for (int i = 0; i < 10; i++)
		continue;

	/* Magic __func__ variable */
	printf("%s", __func__);
], [$1], [$2])dnl
])# DPKG_TRY_C99

# DPKG_C_C99
# ----------
# Check whether the compiler can do C99
AC_DEFUN([DPKG_C_C99],
[AC_CACHE_CHECK([whether compiler supports C99 features], [dpkg_cv_c99],
	[DPKG_TRY_C99([dpkg_cv_c99=yes], [dpkg_cv_c99=no])])
AS_IF([test "x$dpkg_cv_c99" = "xyes"],
	[AC_DEFINE([HAVE_C99], 1, [Define to 1 if the compiler supports C99.])],
	[AC_CACHE_CHECK([what argument makes compiler support C99 features],
		[dpkg_cv_c99_arg],
		[dpkg_cv_c99_arg=none
		 dpkg_save_CC="$CC"
		 for arg in "-std=gnu99" "-std=c99" "-c99"; do
		    CC="$dpkg_save_CC $arg"
		    DPKG_TRY_C99([dpkg_arg_worked=yes], [dpkg_arg_worked=no])
		    CC="$dpkg_save_CC"

		    AS_IF([test "x$dpkg_arg_worked" = "xyes"],
			  [dpkg_cv_c99_arg="$arg"; break])
		 done])
	 AS_IF([test "x$dpkg_cv_c99_arg" != "xnone"],
	       [CC="$CC $dpkg_cv_c99_arg"
		AC_DEFINE([HAVE_C99], 1)])])[]dnl
])# DPKG_C_C99