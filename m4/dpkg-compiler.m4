# serial 1
# Copyright © 2004 Scott James Remnant <scott@netsplit.com>
# Copyright © 2006, 2009-2011, 2013-2016 Guillem Jover <guillem@debian.org>

# DPKG_CHECK_COMPILER_FLAG
# ------------------------
AC_DEFUN([DPKG_CHECK_COMPILER_FLAG], [
  m4_define([dpkg_check_flag], m4_bpatsubst([$1], [^-Wno-], [-W]))

  AC_LANG_CASE(
  [C], [
    m4_define([dpkg_compiler], [$CC])
    m4_define([dpkg_varname], [CFLAGS])
    m4_define([dpkg_varname_save], [dpkg_save_CFLAGS])
    m4_define([dpkg_varname_export], [DPKG_COMPILER_CFLAGS])
    m4_pattern_allow([DPKG_COMPILER_CFLAGS])
    AS_VAR_PUSHDEF([dpkg_varname_cache], [dpkg_cv_cflags_$1])
  ],
  [C++], [
    m4_define([dpkg_compiler], [$CXX])
    m4_define([dpkg_varname], [CXXFLAGS])
    m4_define([dpkg_varname_save], [dpkg_save_CXXFLAGS])
    m4_define([dpkg_varname_export], [DPKG_COMPILER_CXXFLAGS])
    m4_pattern_allow([DPKG_COMPILER_CXXFLAGS])
    AS_VAR_PUSHDEF([dpkg_varname_cache], [dpkg_cv_cxxflags_$1])
  ])
  AC_CACHE_CHECK([whether ]dpkg_compiler[ accepts $1], [dpkg_varname_cache], [
    AS_VAR_COPY([dpkg_varname_save], [dpkg_varname])
    AS_VAR_SET([dpkg_varname], ["-Werror dpkg_check_flag"])
    AC_COMPILE_IFELSE([
      AC_LANG_SOURCE([[]])
    ], [
      AS_VAR_SET([dpkg_varname_cache], [yes])
    ], [
      AS_VAR_SET([dpkg_varname_cache], [no])
    ])
    AS_VAR_COPY([dpkg_varname], [dpkg_varname_save])
  ])
  AS_VAR_IF([dpkg_varname_cache], [yes], [
    AS_VAR_APPEND([dpkg_varname_export], [" $1"])
  ])
  AS_VAR_POPDEF([dpkg_varname_cache])
])

# DPKG_CHECK_COMPILER_WARNINGS
# ----------------------------
# Add configure option to disable additional compiler warnings.
AC_DEFUN([DPKG_CHECK_COMPILER_WARNINGS], [
  DPKG_CHECK_COMPILER_FLAG([-Wall])
  DPKG_CHECK_COMPILER_FLAG([-Wextra])

  DPKG_CHECK_COMPILER_FLAG([-Walloca])
  DPKG_CHECK_COMPILER_FLAG([-Walloc-zero])
  DPKG_CHECK_COMPILER_FLAG([-Warray-bounds-pointer-arithmetic])
  DPKG_CHECK_COMPILER_FLAG([-Wassign-enum])
  DPKG_CHECK_COMPILER_FLAG([-Wbitfield-enum-conversion])
  DPKG_CHECK_COMPILER_FLAG([-Wcast-align])
  DPKG_CHECK_COMPILER_FLAG([-Wconditional-uninitialized])
  DPKG_CHECK_COMPILER_FLAG([-Wdate-time])
  DPKG_CHECK_COMPILER_FLAG([-Wdocumentation])
  DPKG_CHECK_COMPILER_FLAG([-Wduplicate-enum])
  DPKG_CHECK_COMPILER_FLAG([-Wduplicated-branches])
  DPKG_CHECK_COMPILER_FLAG([-Wduplicated-cond])
  DPKG_CHECK_COMPILER_FLAG([-Wextra-semi])
  DPKG_CHECK_COMPILER_FLAG([-Wflexible-array-extensions])
  DPKG_CHECK_COMPILER_FLAG([-Wfloat-conversion])
  DPKG_CHECK_COMPILER_FLAG([-Wfloat-equal])
  DPKG_CHECK_COMPILER_FLAG([-Wformat -Wformat-security])
  DPKG_CHECK_COMPILER_FLAG([-Wformat=2])
  DPKG_CHECK_COMPILER_FLAG([-Winit-self])
  DPKG_CHECK_COMPILER_FLAG([-Wlogical-not-parentheses])
  DPKG_CHECK_COMPILER_FLAG([-Wlogical-op])
  DPKG_CHECK_COMPILER_FLAG([-Wmissing-declarations])
  DPKG_CHECK_COMPILER_FLAG([-Wmissing-format-attribute])
  DPKG_CHECK_COMPILER_FLAG([-Wmissing-variable-declarations])
  DPKG_CHECK_COMPILER_FLAG([-Wnewline-eof])
  DPKG_CHECK_COMPILER_FLAG([-Wno-missing-field-initializers])
  DPKG_CHECK_COMPILER_FLAG([-Wno-nonnull-compare])
  DPKG_CHECK_COMPILER_FLAG([-Wno-tautological-constant-out-of-range-compare])
  DPKG_CHECK_COMPILER_FLAG([-Wno-unused-parameter])
  DPKG_CHECK_COMPILER_FLAG([-Wnull-dereference])
  DPKG_CHECK_COMPILER_FLAG([-Wpointer-arith])
  DPKG_CHECK_COMPILER_FLAG([-Wredundant-decls])
  DPKG_CHECK_COMPILER_FLAG([-Wregister])
  DPKG_CHECK_COMPILER_FLAG([-Wrestrict])
  DPKG_CHECK_COMPILER_FLAG([-Wshadow])
  DPKG_CHECK_COMPILER_FLAG([-Wshift-negative-value])
  DPKG_CHECK_COMPILER_FLAG([-Wshift-overflow=2])
  DPKG_CHECK_COMPILER_FLAG([-Wshift-sign-overflow])
  DPKG_CHECK_COMPILER_FLAG([-Wsizeof-array-argument])
  DPKG_CHECK_COMPILER_FLAG([-Wstrict-overflow=2])
  DPKG_CHECK_COMPILER_FLAG([-Wswitch-bool])
  DPKG_CHECK_COMPILER_FLAG([-Wvla])
  DPKG_CHECK_COMPILER_FLAG([-Wwrite-strings])
  DPKG_CHECK_COMPILER_FLAG([-Wxor-used-as-pow])

  AC_LANG_CASE(
  [C], [
    DPKG_CHECK_COMPILER_FLAG([-Wbad-function-cast])
    DPKG_CHECK_COMPILER_FLAG([-Wc99-c11-compat])
    DPKG_CHECK_COMPILER_FLAG([-Wc99-compat])
    DPKG_CHECK_COMPILER_FLAG([-Wc11-extensions])
    DPKG_CHECK_COMPILER_FLAG([-Wc2x-compat])
    DPKG_CHECK_COMPILER_FLAG([-Wc2x-extensions])
    DPKG_CHECK_COMPILER_FLAG([-Wpre-c2x-compat])
    DPKG_CHECK_COMPILER_FLAG([-Wdeclaration-after-statement])
    DPKG_CHECK_COMPILER_FLAG([-Wenum-int-mismatch])
    DPKG_CHECK_COMPILER_FLAG([-Wmissing-prototypes])
    DPKG_CHECK_COMPILER_FLAG([-Wnested-externs])
    DPKG_CHECK_COMPILER_FLAG([-Wold-style-definition])
    DPKG_CHECK_COMPILER_FLAG([-Wstrict-prototypes])
  ],
  [C++], [
    DPKG_CHECK_COMPILER_FLAG([-Wc++11-compat])
    DPKG_CHECK_COMPILER_FLAG([-Wc++11-compat-pedantic])
    DPKG_CHECK_COMPILER_FLAG([-Wc++11-extensions])
    DPKG_CHECK_COMPILER_FLAG([-Wcast-qual])
    DPKG_CHECK_COMPILER_FLAG([-Wold-style-cast])
    AS_IF([test "x$dpkg_cv_cxx11" = "xyes"], [
      DPKG_CHECK_COMPILER_FLAG([-Wzero-as-null-pointer-constant])
    ])
  ])
])

# DPKG_COMPILER_WARNINGS
# ----------------------
# Add configure option to disable additional compiler warnings.
AC_DEFUN([DPKG_COMPILER_WARNINGS], [
  AC_ARG_ENABLE([compiler-warnings],
    [AS_HELP_STRING([--disable-compiler-warnings],
      [Disable (detected) additional compiler warnings])],
    [], [enable_compiler_warnings=yes])

  AS_IF([test "x$enable_compiler_warnings" = "xyes"], [
    DPKG_CHECK_COMPILER_WARNINGS
    AC_LANG_PUSH([C++])
    DPKG_CHECK_COMPILER_WARNINGS
    AC_LANG_POP([C++])

    CFLAGS="$DPKG_COMPILER_CFLAGS $CFLAGS"
    CXXFLAGS="$DPKG_COMPILER_CXXFLAGS $CXXFLAGS"
  ])
])

# DPKG_CHECK_COMPILER_SANITIZER
# -----------------------------
# Check whether the compiler sanitizer options are supported.
AC_DEFUN([DPKG_CHECK_COMPILER_SANITIZER], [
  DPKG_CHECK_COMPILER_FLAG([-fno-omit-frame-pointer])
  DPKG_CHECK_COMPILER_FLAG([-fsanitize=address])
  DPKG_CHECK_COMPILER_FLAG([-fsanitize=undefined])
])

# DPKG_COMPILER_SANITIZER
# -----------------------
# Add configure option to enable compiler sanitizer support options.
AC_DEFUN([DPKG_COMPILER_SANITIZER], [
  AC_ARG_ENABLE([compiler-sanitizer],
    [AS_HELP_STRING([--enable-compiler-sanitizer],
      [Enable compiler sanitizer support])],
    [], [enable_compiler_sanitizer=no])

  AS_IF([test "x$enable_compiler_sanitizer" = "xyes"], [
    DPKG_CHECK_COMPILER_SANITIZER
    AC_LANG_PUSH([C++])
    DPKG_CHECK_COMPILER_SANITIZER
    AC_LANG_POP([C++])

    LDFLAGS="$DPKG_COMPILER_CFLAGS $LDFLAGS"
    CFLAGS="$DPKG_COMPILER_CFLAGS $CFLAGS"
    CXXFLAGS="$DPKG_COMPILER_CXXFLAGS $CXXFLAGS"
  ])
])

# DPKG_COMPILER_ANALYZER
# ----------------------
# Add configure option to enable compiler analyzer support options.
# Note: This is only intended for development use, as enabling this option
# unconditionally can generate large amounts of false positives that
# require sentient triage intervention.
AC_DEFUN([DPKG_COMPILER_ANALYZER], [
  AC_ARG_ENABLE([compiler-analyzer],
    [AS_HELP_STRING([--enable-compiler-analyzer],
      [Enable compiler analyzer support])],
    [], [enable_compiler_analyzer=no])

  AS_IF([test "x$enable_compiler_analyzer" = "xyes"], [
    DPKG_CHECK_COMPILER_FLAG([-fanalyzer])
    AC_LANG_PUSH([C++])
    DPKG_CHECK_COMPILER_FLAG([-fanalyzer])
    AC_LANG_POP([C++])

    LDFLAGS="$COMPILER_CFLAGS $LDFLAGS"
    CFLAGS="$COMPILER_CFLAGS $CFLAGS"
    CXXFLAGS="$COMPILER_CXXFLAGS $CXXFLAGS"
  ])
])

# DPKG_COMPILER_OPTIMIZATIONS
# ---------------------------
# Add configure option to disable optimizations.
AC_DEFUN([DPKG_COMPILER_OPTIMIZATIONS], [
  AC_ARG_ENABLE([compiler-optimizations],
    [AS_HELP_STRING([--disable-compiler-optimizations],
      [Disable (detected) compiler optimizations])],
    [], [enable_compiler_optimizations=yes])

  AS_IF([test "x$enable_compiler_optimizations" = "xno"], [
    CFLAGS=$(echo "$CFLAGS" | $SED -e "s/ -O[[1-9]]*\b/ -O0/g")
  ])
])

# DPKG_TRY_C99([ACTION-IF-FOUND], [ACTION-IF-NOT-FOUND])
# ------------------------------------------------------
# Try compiling some C99 code to see whether it works
AC_DEFUN([DPKG_TRY_C99], [
  AC_COMPILE_IFELSE([
    AC_LANG_PROGRAM([[
#include <inttypes.h>
#include <stdbool.h>
#include <stdio.h>

/* Variadic macro arguments. */
#define variadic_macro(foo, ...) printf(foo, __VA_ARGS__)
    ]], [[
	int rc;

	/* Designated initializers. */
	struct { int a, b; } foo = { .a = 1, .b = 2 };

	/* Compound literals. */
	struct point { int x, y; } p = (struct point){ .x = 0, .y = 1 };
	p = (struct point){ .x = 2, .y = 4 };

	/* Trailing comma in enum. */
	enum { FIRST, SECOND, } quux;

	/* Boolean type. */
	bool bar = false;

	/* Specific size type. */
	uint32_t baz = 0;
	size_t size = SIZE_MAX;
	intmax_t imax = INTMAX_MAX;

	/* Format modifiers. */
	rc = printf("%jd", imax);
	if (rc == 3)
		return 1;
	rc = printf("%zu", size);
	if (rc == 3)
		return 1;

	/* Magic __func__ variable. */
	printf("%s", __func__);
    ]])
  ], [$1], [$2])dnl
])# DPKG_TRY_C99

# DPKG_C_C99
# ----------
# Check whether the compiler can do C99
AC_DEFUN([DPKG_C_C99], [
  AC_CACHE_CHECK([whether $CC supports C99 features], [dpkg_cv_c99], [
    DPKG_TRY_C99([dpkg_cv_c99=yes], [dpkg_cv_c99=no])
  ])
  AS_IF([test "x$dpkg_cv_c99" != "xyes"], [
    AC_CACHE_CHECK([for $CC option to accept C99 features], [dpkg_cv_c99_arg], [
      dpkg_cv_c99_arg=none
      dpkg_save_CC="$CC"
      for arg in "-std=gnu99" "-std=c99" "-c99" "-AC99" "-xc99=all" \
                 "-qlanglvl=extc99"; do
        CC="$dpkg_save_CC $arg"
        DPKG_TRY_C99([dpkg_arg_worked=yes], [dpkg_arg_worked=no])
        CC="$dpkg_save_CC"

        AS_IF([test "x$dpkg_arg_worked" = "xyes"], [
          dpkg_cv_c99_arg="$arg"
          break
        ])
      done
    ])
    AS_IF([test "x$dpkg_cv_c99_arg" != "xnone"], [
      CC="$CC $dpkg_cv_c99_arg"
      dpkg_cv_c99=1
    ])
  ])
  AS_IF([test "x$dpkg_cv_c99" = "xyes"], [
    AC_DEFINE([HAVE_C99], 1, [Define to 1 if the compiler supports C99.])
  ], [
    AC_MSG_ERROR([unsupported required C99 extensions])
  ])
])# DPKG_C_C99

# DPKG_TRY_CXX11([ACTION-IF-FOUND], [ACTION-IF-NOT-FOUND])
# --------------
# Try compiling some C++11 code to see whether it works.
AC_DEFUN([DPKG_TRY_CXX11], [
  AC_LANG_PUSH([C++])
  AC_COMPILE_IFELSE([
    AC_LANG_PROGRAM([[
    ]], [[
	// Null pointer keyword.
	void *ptr = nullptr;
    ]])
  ], [$1], [$2])
  AC_LANG_POP([C++])dnl
])# DPKG_TRY_CXX11

# DPKG_CXX_CXX11
# --------------
# Check whether the compiler can do C++11.
AC_DEFUN([DPKG_CXX_CXX11], [
  AC_CACHE_CHECK([whether $CXX supports C++11], [dpkg_cv_cxx11], [
    DPKG_TRY_CXX11([dpkg_cv_cxx11=yes], [dpkg_cv_cxx11=no])
  ])
  AS_IF([test "x$dpkg_cv_cxx11" != "xyes"], [
    AC_CACHE_CHECK([for $CXX option to accept C++11], [dpkg_cv_cxx11_arg], [
      dpkg_cv_cxx11_arg=none
      dpkg_save_CXX="$CXX"
      for arg in "-std=gnu++11" "-std=c++11"; do
        CXX="$dpkg_save_CXX $arg"
        DPKG_TRY_CXX11([dpkg_arg_worked=yes], [dpkg_arg_worked=no])
        CXX="$dpkg_save_CXX"

        AS_IF([test "x$dpkg_arg_worked" = "xyes"], [
          dpkg_cv_cxx11_arg="$arg"; break
        ])
      done
    ])
    AS_IF([test "x$dpkg_cv_cxx11_arg" != "xnone"], [
      CXX="$CXX $dpkg_cv_cxx11_arg"
      dpkg_cv_cxx11=yes
    ])
  ])
  AS_IF([test "x$dpkg_cv_cxx11" = "xyes"], [
    AC_DEFINE([HAVE_CXX11], 1, [Define to 1 if the compiler supports C++11.])
  ])[]dnl
])# DPKG_CXX_CXX11
