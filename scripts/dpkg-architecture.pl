#! /usr/bin/perl
#
# dpkg-architecture
#
# Copyright © 1999 Marcus Brinkmann <brinkmd@debian.org>,
# Copyright © 2004 Scott James Remnant <scott@netsplit.com>.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307 USA

$version="1.0.0"; # This line modified by Makefile
$0 = `basename $0`; chomp $0;

$dpkglibdir="/usr/lib/dpkg";
push(@INC,$dpkglibdir);
require 'controllib.pl';

$pkgdatadir="/usr/share/dpkg";


sub usageversion {
    print STDERR
"Debian $0 $version.
Copyright (C) 1999-2001 Marcus Brinkmann <brinkmd@debian.org>,
Copyright (C) 2004 Scott James Remnant <scott@netsplit.com>.
This is free software; see the GNU General Public Licence
version 2 or later for copying conditions.  There is NO warranty.

Usage:
  $0 [<option> ...] [<action>]
Options:
       -a<debian-arch>    set Debian architecture
       -t<gnu-system>     set GNU system type 
       -f                 force flag (override variables set in environment)
Actions:
       -l                 list variables (default)
       -q<variable>       prints only the value of <variable>.
       -s                 print command to set environment variables
       -u                 print command to unset environment variables
       -c <command>       set environment and run the command in it.

Known Debian Architectures are ".join(", ",keys %archtable)."
Known GNU System Types are ".join(", ",map ($archtable{$_},keys %archtable))."
";
}

sub read_archtable {
    open ARCHTABLE, "$pkgdatadir/archtable"
	or &syserr("unable to open archtable");
    while (<ARCHTABLE>) {
	$archtable{$2} = $1
	    if m/^(?!\s*\#)\s*(\S+)\s+(\S+)\s*$/;
    }
    close ARCHTABLE;
}

sub rewrite_gnu {
    local ($_) = @_;

    # Rewrite CPU type
    s/^(i386|i486|i586|i686|pentium)-/i386-/;
    s/^alpha[^-]*/alpha/;
    s/^arm[^-]*/arm/;
    s/^hppa[^-]*/hppa/;
    s/^(sparc|sparc64)-/sparc64-/;
    s/^(mips|mipseb)-/mips-/;
    s/^(powerpc|ppc)-/powerpc-/;

    # Rewrite OS type
    s/-linux.*-gnu.*/-linux/;
    s/-darwin.*/-darwin/;
    s/-freebsd.*/-freebsd/;
    s/-gnu.*/-gnu/;
    s/-kfreebsd.*-gnu.*/-kfreebsd-gnu/;
    s/-knetbsd.*-gnu.*/-knetbsd-gnu/;
    s/-netbsd.*/-netbsd/;
    s/-openbsd.*/-openbsd/;

    # Nuke the vendor bit
    s/^([^-]*)-([^-]*)-(.*)/$1-$3/;

    return $_;
}

sub gnu_to_debian {
	local ($gnu) = @_;
	local (@list);
	local ($a);

	$gnu = &rewrite_gnu($gnu);

	foreach $a (keys %archtable) {
		push @list, $a if $archtable{$a} eq $gnu;
	}
	return @list;
}

&read_archtable;

# Set default values:

$deb_build_arch = `dpkg --print-architecture`;
if ($?>>8) {
	&syserr("dpkg --print-architecture failed");
}
chomp $deb_build_arch;
$deb_build_gnu_type = $archtable{$deb_build_arch};
@deb_build_gnu_triple = split(/-/, $deb_build_gnu_type, 2);
$deb_build_gnu_cpu = $deb_build_gnu_triple[0];
$deb_build_gnu_system = $deb_build_gnu_triple[1];

# Default host: Current gcc.
$gcc = `\${CC:-gcc} -dumpmachine`;
if ($?>>8) {
    &warn("Couldn't determine gcc system type, falling back to default (native compilation)");
    $gcc = '';
} else {
    chomp $gcc;
}

if ($gcc ne '') {
    @list = &gnu_to_debian($gcc);
    if ($#list == -1) {
	&warn ("Unknown gcc system type $gcc, falling back to default (native compilation)"),
	$gcc = '';
    } elsif ($#list > 0) {
	&warn ("Ambiguous gcc system type $gcc, you must specify Debian architecture, too (one of ".join(", ",@list).")");
	$gcc = '';
    } else {
	$deb_host_arch = $list[0];
	$deb_host_gnu_type = $archtable{$deb_host_arch};
	@deb_host_gnu_triple = split(/-/, $deb_host_gnu_type, 2);
	$deb_host_gnu_cpu = $deb_host_gnu_triple[0];
	$deb_host_gnu_system = $deb_host_gnu_triple[1];
	$gcc = $deb_host_gnu_type;
    }
}
if (!defined($deb_host_arch)) {
    # Default host: Native compilation.
    $deb_host_arch = $deb_build_arch;
    $deb_host_gnu_cpu = $deb_build_gnu_cpu;
    $deb_host_gnu_system = $deb_build_gnu_system;
    $deb_host_gnu_type = $deb_build_gnu_type;
}


$req_host_arch = '';
$req_host_gnu_type = '';
$action='l';
$force=0;

while (@ARGV) {
    $_=shift(@ARGV);
    if (m/^-a/) {
	$req_host_arch = "$'";
    } elsif (m/^-t/) {
	$req_host_gnu_type = &rewrite_gnu("$'");
    } elsif (m/^-[lsu]$/) {
	$action = $_;
	$action =~ s/^-//;
    } elsif (m/^-f$/) {
        $force=1;
    } elsif (m/^-q/) {
        $req_variable_to_print = "$'";
        $action = 'q';
    } elsif (m/^-c$/) {
       $action = 'c';
       last;
    } else {
	usageerr("unknown option \`$_'");
    }
}

if ($req_host_arch ne '' && $req_host_gnu_type eq '') {
    die ("unknown Debian architecture $req_host_arch, you must specify \GNU system type, too") if !exists $archtable{$req_host_arch};
    $req_host_gnu_type = $archtable{$req_host_arch}
}

if ($req_host_gnu_type ne '' && $req_host_arch eq '') {
    @list = &gnu_to_debian ($req_host_gnu_type);
    die ("unknown GNU system type $req_host_gnu_type, you must specify Debian architecture, too") if $#list == -1;
    die ("ambiguous GNU system type $req_host_gnu_type, you must specify Debian architecture, too (one of ".join(", ",@list).")") if $#list > 0;
    $req_host_arch = $list[0];
}

if (exists $archtable{$req_host_arch}) {
    &warn("Default GNU system type $archtable{$req_host_arch} for Debian arch $req_host_arch does not match specified GNU system type $req_host_gnu_type") if $archtable{$req_host_arch} ne $req_host_gnu_type;
}

die "couldn't parse GNU system type $req_host_gnu_type, must be arch-os or arch-vendor-os" if $req_host_gnu_type !~ m/^([\w\d]+(-[\w\d]+){1,2})?$/;

$deb_host_arch = $req_host_arch if $req_host_arch ne '';
if ($req_host_gnu_type ne '') {
    $deb_host_gnu_type = $req_host_gnu_type;
    @deb_host_gnu_triple = split(/-/, $deb_host_gnu_type, 2);
    $deb_host_gnu_cpu = $deb_host_gnu_triple[0];
    $deb_host_gnu_system = $deb_host_gnu_triple[1];
}

#$gcc = `\${CC:-gcc} --print-libgcc-file-name`;
#$gcc =~ s!^.*gcc-lib/(.*)/\d+(?:.\d+)*/libgcc.*$!$1!s;
&warn("Specified GNU system type $deb_host_gnu_type does not match gcc system type $gcc.") if ($gcc ne '') && ($gcc ne $deb_host_gnu_type);

%env = ();
if (!$force) {
    $deb_build_arch = $ENV{DEB_BUILD_ARCH} if (exists $ENV{DEB_BUILD_ARCH});
    $deb_build_gnu_cpu = $ENV{DEB_BUILD_GNU_CPU} if (exists $ENV{DEB_BUILD_GNU_CPU});
    $deb_build_gnu_system = $ENV{DEB_BUILD_GNU_SYSTEM} if (exists $ENV{DEB_BUILD_GNU_SYSTEM});
    $deb_build_gnu_type = $ENV{DEB_BUILD_GNU_TYPE} if (exists $ENV{DEB_BUILD_GNU_TYPE});
    $deb_host_arch = $ENV{DEB_HOST_ARCH} if (exists $ENV{DEB_HOST_ARCH});
    $deb_host_gnu_cpu = $ENV{DEB_HOST_GNU_CPU} if (exists $ENV{DEB_HOST_GNU_CPU});
    $deb_host_gnu_system = $ENV{DEB_HOST_GNU_SYSTEM} if (exists $ENV{DEB_HOST_GNU_SYSTEM});
    $deb_host_gnu_type = $ENV{DEB_HOST_GNU_TYPE} if (exists $ENV{DEB_HOST_GNU_TYPE});
}

@ordered = qw(DEB_BUILD_ARCH DEB_BUILD_GNU_CPU
	      DEB_BUILD_GNU_SYSTEM DEB_BUILD_GNU_TYPE
	      DEB_HOST_ARCH DEB_HOST_GNU_CPU
	      DEB_HOST_GNU_SYSTEM DEB_HOST_GNU_TYPE);

$env{'DEB_BUILD_ARCH'}=$deb_build_arch;
$env{'DEB_BUILD_GNU_CPU'}=$deb_build_gnu_cpu;
$env{'DEB_BUILD_GNU_SYSTEM'}=$deb_build_gnu_system;
$env{'DEB_BUILD_GNU_TYPE'}=$deb_build_gnu_type;
$env{'DEB_HOST_ARCH'}=$deb_host_arch;
$env{'DEB_HOST_GNU_CPU'}=$deb_host_gnu_cpu;
$env{'DEB_HOST_GNU_SYSTEM'}=$deb_host_gnu_system;
$env{'DEB_HOST_GNU_TYPE'}=$deb_host_gnu_type;

if ($action eq 'l') {
    foreach $k (@ordered) {
	print "$k=$env{$k}\n";
    }
} elsif ($action eq 's') {
    foreach $k (@ordered) {
	print "$k=$env{$k}; ";
    }
    print "export ".join(" ",@ordered)."\n";
} elsif ($action eq 'u') {
    print "unset ".join(" ",@ordered)."\n";
} elsif ($action eq 'c') {
    @ENV{keys %env} = values %env;
    exec @ARGV;
} elsif ($action eq 'q') {
    if (exists $env{$req_variable_to_print}) {
        print "$env{$req_variable_to_print}\n";
    } else {
        die "$req_variable_to_print is not a supported variable name";
    }
}
