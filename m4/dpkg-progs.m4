# Copyright © 2005 Scott James Remnant <scott@netsplit.com>
# Copyright © 2007 Frank Lichtenheld <djpig@debian.org>
# Copyright © 2007, 2009, 2011 Guillem Jover <guillem@debian.org>

# DPKG_PROG_PERL
# --------------
# Locate perl interpreter in the path
AC_DEFUN([DPKG_PROG_PERL],
[AC_ARG_VAR([PERL], [Perl interpreter])dnl
AC_PATH_PROG([PERL], [perl], [no])
if test "$PERL" = "no" || test ! -x "$PERL"; then
  AC_MSG_ERROR([cannot find the Perl interpreter])
fi
AC_ARG_VAR([PERL_LIBDIR], [Perl library directory])dnl
# Let the user override the variable.
if test -z "$PERL_LIBDIR"; then
PERL_LIBDIR=$($PERL -MConfig -e 'my $r = $Config{vendorlibexp};
                                 $r =~ s/$Config{vendorprefixexp}/\$(prefix)/;
                                 print $r')
fi
])# DPKG_PROG_PERL

# DPKG_PROG_PO4A
# --------------
AC_DEFUN([DPKG_PROG_PO4A], [
AC_REQUIRE([AM_NLS])
AC_CHECK_PROGS([PO4A], [po4a])
if test "$USE_NLS" = "yes" && test -n "$PO4A"; then
  USE_PO4A=yes
else
  USE_PO4A=no
fi
AC_SUBST([USE_PO4A])
])# DPKG_PROG_PO4A

# DPKG_PROG_POD2MAN
# --------------
AC_DEFUN([DPKG_PROG_POD2MAN], [
AC_CHECK_PROGS([POD2MAN], [pod2man])
AM_CONDITIONAL(BUILD_POD_DOC, [test "x$POD2MAN" != "x"])
])# DPKG_PROG_POD2MAN

# DPKG_DEB_PROG_TAR
# -----------------
# Specify GNU tar program name to use by dpkg-deb. On GNU systems this is
# usually simply tar, on BSD systems this is usually gnutar or gtar.
AC_DEFUN([DPKG_DEB_PROG_TAR], [
AC_ARG_VAR([TAR], [GNU tar program])
AC_CHECK_PROGS([TAR], [gnutar gtar tar], [tar])
AC_DEFINE_UNQUOTED([TAR], ["$TAR"], [GNU tar program])
])# DPKG_DEB_PROG_TAR
