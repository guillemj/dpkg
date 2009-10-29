# DPKG_PROG_PERL
# --------------
# Locate perl interpreter in the path
AC_DEFUN([DPKG_PROG_PERL],
[AC_ARG_VAR([PERL], [Perl interpreter])dnl
AC_PATH_PROG([PERL], [perl], [/usr/bin/perl])dnl
AC_ARG_VAR([PERL_LIBDIR], [Perl library directory])dnl
PERL_LIBDIR=$($PERL -MConfig -e 'my $r = $Config{vendorlibexp};
                                 $r =~ s/$Config{vendorprefixexp}/\$(prefix)/;
                                 print $r')dnl
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

