#!/usr/bin/perl --
chop($v=`pwd`);
$v =~ s,^.*/dpkg-,, || die;
$v =~ s,/\w+$,,;
$v =~ m,^[-0-9.]+$, || die;
while (<STDIN>) {
    $_= $1.$v.$2."\n" if
        m|^(#define DPKG_VERSION ")[-0-9.]+(" /\* This line modified by Makefile \*/)$|;
    $_= $1.$v.$2."\n" if
        m/^(\$version= ')[-0-9.]+('; # This line modified by Makefile)$/;
    $_= $1.$v.$2."\n" if
        m/^(version=")[-0-9.]+("; # This line modified by Makefile)$/;
    print || die;
}
