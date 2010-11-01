# Copyright © 2004 Scott James Remnant <scott@netsplit.com>
# Copyright © 2006, 2009 Guillem Jover <guillem@debian.org>

# DPKG_COMPILER_WARNINGS
# ---------------------
# Add configure option to disable additional compiler warnings.
AC_DEFUN([DPKG_COMPILER_WARNINGS],
[AC_ARG_ENABLE(compiler-warnings,
	AS_HELP_STRING([--disable-compiler-warnings],
	               [Disable additional compiler warnings]),
	[],
	[enable_compiler_warnings=yes])

WFLAGS="-Wall -Wextra -Wno-unused-parameter -Wno-missing-field-initializers \
	 -Wmissing-declarations -Wmissing-format-attribute \
	 -Wvla -Winit-self -Wwrite-strings -Wcast-align -Wshadow"
WCFLAGS="-Wdeclaration-after-statement -Wnested-externs -Wbad-function-cast \
	 -Wstrict-prototypes -Wmissing-prototypes -Wold-style-definition"
# Temporarily here until #542031 gets fixed in ncurses
WCXXFLAGS="-Wno-unused-value"
if test "x$enable_compiler_warnings" = "xyes"; then
	if test "x$GCC" = "xyes"; then
		CFLAGS="$WFLAGS $WCFLAGS $CFLAGS"
        fi
	if test "x$GXX" = "xyes"; then
		CXXFLAGS="$WFLAGS $WCXXFLAGS $CXXFLAGS"
	fi
fi
])

# DPKG_COMPILER_OPTIMISATIONS
# --------------------------
# Add configure option to disable optimisations.
AC_DEFUN([DPKG_COMPILER_OPTIMISATIONS],
[AC_ARG_ENABLE(compiler-optimisations,
	AS_HELP_STRING([--disable-compiler-optimisations],
		       [Disable compiler optimisations]),
	[],
	[enable_compiler_optimisations=yes])

  AS_IF([test "x$enable_compiler_optimisations" = "xno"], [
    CFLAGS=$(echo "$CFLAGS" | sed -e "s/ -O[[1-9]]*\b/ -O0/g")
  ])
])

# DPKG_TRY_C99([ACTION-IF-FOUND], [ACTION-IF-NOT-FOUND])
# ------------------------------------------------------
# Try compiling some C99 code to see whether it works
AC_DEFUN([DPKG_TRY_C99],
[AC_COMPILE_IFELSE([AC_LANG_PROGRAM([[
#include <inttypes.h>
#include <stdbool.h>
#include <stdio.h>

/* Variadic macro arguments. */
#define variadic_macro(foo, ...) printf(foo, __VA_ARGS__)
]],
[[
	/* Compound initializers. */
	struct { int a, b; } foo = { .a = 1, .b = 2 };

	/* Trailing comma in enum. */
	enum { first, second, } quux;

	/* Boolean type. */
	bool bar = false;

	/* Specific size type. */
	uint32_t baz = 0;

	/* Magic __func__ variable. */
	printf("%s", __func__);
]])], [$1], [$2])dnl
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
		 for arg in "-std=gnu99" "-std=c99" "-c99" "-AC99" \
		            "-xc99=all" "-qlanglvl=extc99"; do
		    CC="$dpkg_save_CC $arg"
		    DPKG_TRY_C99([dpkg_arg_worked=yes], [dpkg_arg_worked=no])
		    CC="$dpkg_save_CC"

		    AS_IF([test "x$dpkg_arg_worked" = "xyes"],
			  [dpkg_cv_c99_arg="$arg"; break])
		 done])
	 AS_IF([test "x$dpkg_cv_c99_arg" != "xnone"],
	       [CC="$CC $dpkg_cv_c99_arg"
		AC_DEFINE([HAVE_C99], 1)],
	       [AC_MSG_ERROR([unsupported required C99 extensions])])])[]dnl
])# DPKG_C_C99
