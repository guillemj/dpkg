# Copyright © 2004 Scott James Remnant <scott@netsplit.com>.

# DPKG_LINKER_OPTIMISATIONS
# --------------------------
# Add configure option to disable linker optimisations.
AC_DEFUN([DPKG_LINKER_OPTIMISATIONS],
[AC_ARG_ENABLE(linker-optimisations,
	AS_HELP_STRING([--disable-linker-optimisations],
		       [Disable linker optimisations]),
    [],
    [enable_linker_optimisations=yes])

  AS_IF([test "x$enable_linker_optimisations" = "xno"], [
    LDFLAGS=$(echo "$LDFLAGS" | sed -e "s/ -Wl,-O[[0-9]]*\b//g")
  ], [
    LDFLAGS="$LDFLAGS -Wl,-O1"
  ])
])
