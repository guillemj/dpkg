# DPKG_CPU_TYPE
# -------------
# Parse the target cpu name and check it against a list of special cases to
# determine what type it is.
AC_DEFUN([DPKG_CPU_TYPE],
[AC_MSG_CHECKING([cpu type])
case "$target_cpu" in
    i386|i486|i586|i686|pentium)
	cpu_type="i386"
	;;
    alpha*)
	cpu_type="alpha"
	;;
    arm*)
	cpu_type="arm"
	;;
    hppa*)
	cpu_type="hppa"
	;;
    sparc|sparc64)
	cpu_type="sparc"
	;;
    mips|mipseb)
	cpu_type="mips"
	;;
    powerpc|ppc)
	cpu_type="powerpc"
	;;
    *)
	cpu_type=$target_cpu
	;;
esac
AC_MSG_RESULT([$cpu_type])
])# DPKG_CPU_TYPE

# DPKG_OS_TYPE
# ------------
# Parse the target operating system name and check it against a list of
# special cases to determine what type it is.
AC_DEFUN([DPKG_OS_TYPE],
[AC_MSG_CHECKING([operating system type])
case "$target_os" in
    linux*-gnu*)
	os_type="linux"
	;;
    darwin*)
	os_type="darwin"
	;;
    freebsd*)
	os_type="freebsd"
	;;
    gnu*)
	os_type="gnu"
	;;
    kfreebsd*-gnu*)
	os_type="kfreebsd-gnu"
	;;
    knetbsd*-gnu*)
	os_type="knetbsd-gnu"
	;;
    netbsd*)
	os_type="netbsd"
	;;
    openbsd*)
	os_type="openbsd"
	;;
    *)
	os_type=$target_os
	;;
esac
AC_MSG_RESULT([$os_type])
])# DPKG_OS_TYPE

# DPKG_ARCHITECTURE
# ------------------------
# Locate the target operating system in the archtable, sets ARCHITECTURE
AC_DEFUN([DPKG_ARCHITECTURE],
[DPKG_CPU_TYPE
DPKG_OS_TYPE
AC_MSG_CHECKING([Debian architecture name])
dpkg_archset="`awk '[$]1 == "'$cpu_type-$os_type'" { print [$]2 }' $srcdir/archtable`"
if test "x$dpkg_archset" = "x"; then
	dpkg_archset=$cpu_type-$os_type
	AC_MSG_RESULT([$dpkg_archset, but not found in archtable])
else
	AC_MSG_RESULT([$dpkg_archset])
fi
AC_DEFINE_UNQUOTED(ARCHITECTURE, "${dpkg_archset}",
	[Set this to the canonical Debian architecture string for this CPU type.])
])# DPKG_ARCHITECTURE
