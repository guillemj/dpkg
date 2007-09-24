# DPKG_PROG_PERL
# --------------
# Locate perl interpreter in the path
AC_DEFUN([DPKG_PROG_PERL],
[AC_ARG_VAR([PERL], [Perl interpreter])dnl
AC_PATH_PROG([PERL], [perl], [/usr/bin/perl])dnl
AC_ARG_VAR([PERL_LIBDIR], [Perl library directory])dnl
PERL_LIBDIR=`$PERL -MConfig -e 'my $r=$Config{vendorlibexp};$r=~s/$Config{vendorprefixexp}/\\$(prefix)/; print $r'`dnl
])# DPKG_PROG_PERL
