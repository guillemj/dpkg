#! /usr/bin/perl
#
# dpkg-architecture
#
# Copyright 1999 Marcus Brinkmann <brinkmd@debian.org>
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

# History
#  0.0.1  Initial release.
#  0.0.2  Don't use dpkg to get default gnu system, so the default is
#         correct even on non-linux system.
#         Warn if the host gnu system does not match the gcc system.
#         Determine default from gcc if possible, else fall back to native
#         compilation.
#         Do not set environment variables which are already defined unless
#         force flag is given.
#  1.0.0  Changed target to host, because this complies with GNU
#         nomenclature.
#         Added command facility.
#  1.0.1  Moved to GNU nomenclature arch->cpu, system->type, os->system
#  1.0.2  Add facility to query single values, suggested by Richard Braakman.
#  1.0.3  Make it work with egcs, too.
#  1.0.4  Suppress single "export" with "-s" when all env variables are already set
#  1.0.5  Update default for rules files (i386->i486).
#         Print out overridden values, so make gets them, too.
#  1.0.6  Revert to i386 to comply with policy § 5.1.
#  1.0.7  -q should not imply -f, because this prevents setting
#         make variables with non-standard names correctly.

$version="1.0.0";
$0 = `basename $0`; chomp $0;

$dpkglibdir="/usr/lib/dpkg";
push(@INC,$dpkglibdir);
require 'controllib.pl';

%archtable=('i386',      'i386-linux',
	    'sparc',     'sparc-linux',
	    'sparc64',   'sparc64-linux',
	    'alpha',     'alpha-linux',
	    'm68k',      'm68k-linux',
            'arm',       'arm-linux',
            'powerpc',   'powerpc-linux',
	    'mips',      'mips-linux',
	    'mipsel',    'mipsel-linux',
	    'sh',        'sh-linux',
	    'shed',      'shed-linux',
	    'hppa',      'hppa-linux',
	    'hurd-i386', 'i386-gnu',
	    's390',	 's390-linux');
	    'freebsd-i386', 'i386-freebsd');

sub usageversion {
    print STDERR
"Debian GNU/Linux $0 $version.  Copyright (C) 1999 Marcus Brinkmann.
This is free software; see the GNU General Public Licence version 2
or later for copying conditions.  There is NO warranty.

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

sub rewrite_gnu_cpu {
	local ($_) = @_;

	s/(?:i386|i486|i586|i686|pentium)(.*linux)/i386$1/;
	s/ppc/powerpc/;
	return $_;
}

sub gnu_to_debian {
	local ($gnu) = @_;
	local (@list);
	local ($a);

	$gnu = &rewrite_gnu_cpu($gnu);

	foreach $a (keys %archtable) {
		push @list, $a if $archtable{$a} eq $gnu;
	}
	return @list;
}

# Set default values:

$deb_build_arch = `dpkg --print-installation-architecture`;
chomp $deb_build_arch;
$deb_build_gnu_type = $archtable{$deb_build_arch};
$deb_build_gnu_cpu = $deb_build_gnu_type;
$deb_build_gnu_system = $deb_build_gnu_type;
$deb_build_gnu_cpu =~ s/-.*$//;
$deb_build_gnu_system =~ s/^.*-//;

# Default host: Current gcc.
$gcc = `\${CC:-gcc} --print-libgcc-file-name`;
$gcc =~ s!^.*gcc-lib/(.*)/(?:egcs-)?\d+(?:.\d+)*/libgcc.*$!$1!s;
if ($gcc eq '') {
    &warn ("Couldn't determine gcc system type, falling back to default (native compilation)");
} else {
    @list = &gnu_to_debian($gcc);
    if (!defined(@list)) {
	&warn ("Unknown gcc system type $gcc, falling back to default (native compilation)"),
    } elsif ($#list > 0) {
	&warn ("Ambiguous gcc system type $gcc, you must specify Debian architecture, too (one of ".join(", ",@list).")");
    } else {
	$gcc=$archtable{$list[0]};
	$deb_host_arch = $list[0];
	$deb_host_gnu_type = $gcc;
        $deb_host_gnu_cpu = $gcc;
        $deb_host_gnu_system = $gcc;
        $deb_host_gnu_cpu =~ s/-.*$//;
        $deb_host_gnu_system =~ s/^.*-//;
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
	$req_host_arch = $';
    } elsif (m/^-t/) {
	$req_host_gnu_type = &rewrite_gnu_cpu($');
    } elsif (m/^-[lsu]$/) {
	$action = $_;
	$action =~ s/^-//;
    } elsif (m/^-f$/) {
        $force=1;
    } elsif (m/^-q/) {
        $req_variable_to_print = $';
        $action = 'q';
    } elsif (m/^-c$/) {
       $action = 'c';
       last;
    } else {
	usageerr("unknown option \`$_'");
    }
}

if ($req_host_arch ne '' && $req_host_gnu_type eq '') {
    die ("unknown Debian architecture $req_host_arch, you must specify GNU system type, too") if !exists $archtable{$req_host_arch};
    $req_host_gnu_type = $archtable{$req_host_arch}
}

if ($req_host_gnu_type ne '' && $req_host_arch eq '') {
    @list = &gnu_to_debian ($req_host_gnu_type);
    die ("unknown GNU system type $req_host_gnu_type, you must specify Debian architecture, too") if !defined(@list);
    die ("ambiguous GNU system type $req_host_gnu_type, you must specify Debian architecture, too (one of ".join(", ",@list).")") if $#list > 0;
    $req_host_arch = $list[0];
}

if (exists $archtable{$req_host_arch}) {
    &warn("Default GNU system type $archtable{$req_host_arch} for Debian arch $req_host_arch does not match specified GNU system type $req_host_gnu_type\n") if $archtable{$req_host_arch} ne $req_host_gnu_type;
}

die "couldn't parse GNU system type $req_host_gnu_type, must be arch-os or arch-vendor-os" if $req_host_gnu_type !~ m/^([\w\d]+(-[\w\d]+){1,2})?$/;

$deb_host_arch = $req_host_arch if $req_host_arch ne '';
if ($req_host_gnu_type ne '') {
    $deb_host_gnu_cpu = $deb_host_gnu_system = $deb_host_gnu_type = $req_host_gnu_type;
    $deb_host_gnu_cpu =~ s/-.*$//;
    $deb_host_gnu_system =~ s/^.*-//;
}

#$gcc = `\${CC:-gcc} --print-libgcc-file-name`;
#$gcc =~ s!^.*gcc-lib/(.*)/\d+(?:.\d+)*/libgcc.*$!$1!s;
&warn("Specified GNU system type $deb_host_gnu_type does not match gcc system type $gcc.") if ($gcc ne '') && ($gcc ne $deb_host_gnu_type);

undef @env;
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

push @env, "DEB_BUILD_ARCH=$deb_build_arch";
push @env, "DEB_BUILD_GNU_CPU=$deb_build_gnu_cpu";
push @env, "DEB_BUILD_GNU_SYSTEM=$deb_build_gnu_system";
push @env, "DEB_BUILD_GNU_TYPE=$deb_build_gnu_type";
push @env, "DEB_HOST_ARCH=$deb_host_arch";
push @env, "DEB_HOST_GNU_CPU=$deb_host_gnu_cpu";
push @env, "DEB_HOST_GNU_SYSTEM=$deb_host_gnu_system";
push @env, "DEB_HOST_GNU_TYPE=$deb_host_gnu_type";

if ($action eq 'l') {
    print join("\n",@env)."\n";
} elsif ($action eq 's') {
    print "export ".join("\n",@env)."\n" if ($#env != 0);
} elsif ($action eq 'u') {
    print "unset DEB_BUILD_ARCH DEB_BUILD_GNU_CPU DEB_BUILD_GNU_SYSTEM DEB_BUILD_GNU_TYPE DEB_HOST_ARCH DEB_HOST_GNU_CPU DEB_HOST_GNU_SYSTEM DEB_HOST_GNU_TYPE\n";
} elsif ($action eq 'c') {
    foreach $_ (@env) {
       m/^(.*)=(.*)$/;
       $ENV{$1}=$2;
    }
    exec @ARGV;
} elsif ($action eq 'q') {
    undef %env;
    foreach $_ (@env) {
       m/^(.*)=(.*)$/;
       $env{$1}=$2;
    }
    if (exists $env{$req_variable_to_print}) {
        print "$env{$req_variable_to_print}\n";     # works because -q implies -f !
    } else {
        die "$req_variable_to_print is not a supported variable name";
    }
}

__END__

=head1 NAME

dpkg-architecture - set and determine the architecture for package building

=head1 SYNOPSIS

dpkg-architecture [options] [action]

Valid options:
B<-a>Debian-Architecture
B<-t>Gnu-System-Type
B<-f>

Valid actions:
B<-l>, B<-q>Variable-Name, B<-s>, B<-u>, B<-c> Command

=head1 DESCRIPTION

dpkg-architecture does provide a facility to determine and set the build and
host architecture for package building.

=head1 OVERVIEW

The build architecture is always determined by an external call to dpkg, and
can not be set at the command line.

You can specify the host architecture by providing one or both of the options B<-a>
and B<-t>. The default is determined by an external call to gcc, or the same as
the build architecture if CC or gcc are both not available. One out of B<-a> and B<-t>
is sufficient, the value of the other will be set to a usable default.
Indeed, it is often better to only specify one, because dpkg-architecture
will warn you if your choice doesn't match the default.

The default action is B<-l>, which prints the environment variales, one each line,
in the format VARIABLE=value. If you are only interested in the value of a
single variable, you can use B<-q>. If you specify B<-s>, it will output an export
command. This can be used to set the environment variables using eval. B<-u>
does return a similar command to unset all variables. B<-c> does execute a
command in an environment which has all variables set to the determined
value.

Existing environment variables with the same name as used by the scripts are
not overwritten, except if the B<-f> force flag is present. This allows the user
to override a value even when the call to dpkg-architecture is buried in
some other script (for example dpkg-buildpackage).

=head1 TERMS

=over 4

=item build machine

The machine the package is build on.

=item host machine

The machine the package is build for.

=item Debian Architecture

The Debian archietcture string, which specifies the binary tree in the FTP
archive. Examples: i386, sparc, hurd-i386.

=item GNU System Type

An architecture specification string consisting of two or three parts,
cpu-system or cpu-vendor-system. Examples: i386-linux, sparc-linux, i386-gnu.

=back

=head1 EXAMPLES

dpkg-buildpackage accepts the B<-a> option and passes it to dpkg-architecture.
Other examples:

CC=i386-gnu-gcc dpkg-architecture C<-c> debian/rules build

eval `dpkg-architecture C<-u>`

=head1 VARIABLES

The following variables are set by dpkg-architecture:

=over 4

=item DEB_BUILD_ARCH

The Debian architecture of the build machine.

=item DEB_BUILD_GNU_TYPE

The GNU system type of the build machine.

=item DEB_BUILD_GNU_CPU

The CPU part of DEB_BUILD_GNU_TYPE

=item DEB_BUILD_GNU_SYSTEM

The System part of DEB_BUILD_GNU_TYPE

=item DEB_HOST_ARCH

The Debian architecture of the host machine.

=item DEB_HOST_GNU_TYPE

The GNU system type of the host machine.

=item DEB_HOST_GNU_CPU

The CPU part of DEB_HOST_GNU_TYPE

=item DEB_HOST_GNU_SYSTEM

The System part of DEB_HOST_GNU_TYPE

=back

=head1 DEBIAN/RULES

The environment variables set by dpkg-architecture are passed to
debian/rules as make variables (see make documentation). You can and should
use them in the build process as needed. Here are some examples, which also
show how you can improve the cross compilation support in your package:

Instead:

ARCH=`dpkg --print-architecture`
configure $(ARCH)-linux

please use the following:

B_ARCH=$(DEB_BUILD_GNU_TYPE)
H_ARCH=$(DEB_HOST_GNU_TYPE)
configure --build=$(B_ARCH) --host=$(H_ARCH)

Instead:

ARCH=`dpkg --print-architecture`
ifeq ($(ARCH),alpha)
  ...
endif

please use:

ARCH=$(DEB_HOST_ARCH)
ifeq ($(ARCH),alpha)
  ...
endif

In general, calling dpkg in the rules file to get architecture information
is deprecated (until you want to provide backward compatibility, see below).
Especially the --print-architecture option is unreliable since we have
Debian architectures which don't equal a processor name.

=head1 BACKWARD COMPATIBILITY

When providing a new facility, it is always a good idea to stay compatible with old
versions of the programs. Note that dpkg-architecture does not affect old
debian/rules files, so the only thing to consider is using old building
scripts with new debian/rules files. The following does the job:

DEB_BUILD_ARCH := $(shell dpkg --print-installation-architecture)
DEB_BUILD_GNU_CPU := $(patsubst hurd-%,%,$(DEB_BUILD_ARCH))
ifeq ($(filter-out hurd-%,$(DEB_BUILD_ARCH)),)
  DEB_BUILD_GNU_SYSTEM := gnu
else
  DEB_BUILD_GNU_SYSTEM := linux
endif
DEB_BUILD_GNU_TYPE=$(DEB_BUILD_GNU_CPU)-$(DEB_BUILD_GNU_SYSTEM)

DEB_HOST_ARCH=$(DEB_BUILD_ARCH)
DEB_HOST_GNU_CPU=$(DEB_BUILD_GNU_CPU)
DEB_HOST_GNU_SYSTEM=$(DEB_BUILD_GNU_SYSTEM)
DEB_HOST_GNU_TYPE=$(DEB_BUILD_GNU_TYPE)

Put a subset of these lines at the top of your debian/rules file; these
default values will be overwritten if dpkg-architecture is used.

You don't need the full set. Choose a consistent set which contains the
values you use in the rules file. For example, if you only need the host
Debian architecture, `DEB_HOST_ARCH=`dpkg --print-installation-architecture`
is sufficient (this is indeed the Debian architecture of the build machine,
but remember that we are only trying to be backward compatible with native
compilation).

You may not want to care about old build packages (for example, if you have
sufficient source dependencies declared anyway). But you should at least
support the traditional way to build packages by calling `debian/rules
build' directly, without setting environment variables. To do this, use the
B<-q> option to query suitable default values:

DEB_BUILD_ARCH=`dpkg-architecture -qDEB_BUILD_ARCH`
DEB_BUILD_GNU=`dpkg-architecture -qDEB_BUILD_GNU`

etc. You get the idea. This way, you can ensure that the variables are never
undeclared. Note that this breaks backwards compatibility with old build
scripts, and you should only do that if source dependencies are implemented
and declared accordingly.

=head1 SEE ALSO

dpkg-buildpackage
dpkg-cross

=head1 CONTACT

If you have questions about the usage of the make variables in your rules
files, or about cross compilation support in your packages, please email me.
The addresse is Marcus Brinkmann <brinkmd@debian.org>.
