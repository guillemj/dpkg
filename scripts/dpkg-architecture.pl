#!/usr/bin/perl
#
# dpkg-architecture
#
# Copyright © 1999-2001 Marcus Brinkmann <brinkmd@debian.org>
# Copyright © 2004-2005 Scott James Remnant <scott@netsplit.com>,
# Copyright © 2006-2014 Guillem Jover <guillem@debian.org>
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
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

use strict;
use warnings;

use Dpkg ();
use Dpkg::Gettext;
use Dpkg::ErrorHandling;
use Dpkg::Arch qw(get_raw_build_arch get_raw_host_arch get_gcc_host_gnu_type
                  debarch_to_cpuattrs
                  get_valid_arches debarch_eq debarch_is debarch_to_debtriplet
                  debarch_to_gnutriplet gnutriplet_to_debarch
                  debarch_to_multiarch);

textdomain('dpkg-dev');

sub version {
    printf _g("Debian %s version %s.\n"), $Dpkg::PROGNAME, $Dpkg::PROGVERSION;

    printf _g('
This is free software; see the GNU General Public License version 2 or
later for copying conditions. There is NO warranty.
');
}

sub usage {
    printf _g(
'Usage: %s [<option>...] [<command>]')
    . "\n\n" . _g(
'Commands:
  -l                 list variables (default).
  -L                 list valid architectures.
  -e<debian-arch>    compare with host Debian architecture.
  -i<arch-alias>     check if host Debian architecture is <arch-alias>.
  -q<variable>       prints only the value of <variable>.
  -s                 print command to set environment variables.
  -u                 print command to unset environment variables.
  -c <command>       set environment and run the command in it.
  -?, --help         show this help message.
      --version      show the version.')
    . "\n\n" . _g(
'Options:
  -a<debian-arch>    set host Debian architecture.
  -t<gnu-system>     set host GNU system type.
  -A<debian-arch>    set target Debian architecture.
  -T<gnu-system>     set target GNU system type.
  -f                 force flag (override variables set in environment).')
    . "\n", $Dpkg::PROGNAME;
}

sub list_arches()
{
    foreach my $arch (get_valid_arches()) {
	print "$arch\n";
    }
}

sub check_arch_coherency
{
    my ($arch, $gnu_type) = @_;

    if ($arch ne '' && $gnu_type eq '') {
        $gnu_type = debarch_to_gnutriplet($arch);
        error(_g('unknown Debian architecture %s, you must specify ' .
                 'GNU system type, too'), $arch)
            unless defined $gnu_type;
    }

    if ($gnu_type ne '' && $arch eq '') {
        $arch = gnutriplet_to_debarch($gnu_type);
        error(_g('unknown GNU system type %s, you must specify ' .
                 'Debian architecture, too'), $gnu_type)
            unless defined $arch;
    }

    if ($gnu_type ne '' && $arch ne '') {
        my $dfl_gnu_type = debarch_to_gnutriplet($arch);
        error(_g('unknown default GNU system type for Debian architecture %s'),
              $arch)
            unless defined $dfl_gnu_type;
        warning(_g('default GNU system type %s for Debian arch %s does not ' .
                   'match specified GNU system type %s'), $dfl_gnu_type,
                $arch, $gnu_type)
            if $dfl_gnu_type ne $gnu_type;
    }

    return ($arch, $gnu_type);
}

use constant {
    DEB_NONE => 0,
    DEB_BUILD => 1,
    DEB_HOST => 2,
    DEB_TARGET => 64,
    DEB_ARCH_INFO => 4,
    DEB_ARCH_ATTR => 8,
    DEB_MULTIARCH => 16,
    DEB_GNU_INFO => 32,
};

use constant DEB_ALL => DEB_BUILD | DEB_HOST | DEB_TARGET |
                        DEB_ARCH_INFO | DEB_ARCH_ATTR |
                        DEB_MULTIARCH | DEB_GNU_INFO;

my %arch_vars = (
    DEB_BUILD_ARCH => DEB_BUILD,
    DEB_BUILD_ARCH_OS => DEB_BUILD | DEB_ARCH_INFO,
    DEB_BUILD_ARCH_CPU => DEB_BUILD | DEB_ARCH_INFO,
    DEB_BUILD_ARCH_BITS => DEB_BUILD | DEB_ARCH_ATTR,
    DEB_BUILD_ARCH_ENDIAN => DEB_BUILD | DEB_ARCH_ATTR,
    DEB_BUILD_MULTIARCH => DEB_BUILD | DEB_MULTIARCH,
    DEB_BUILD_GNU_CPU => DEB_BUILD | DEB_GNU_INFO,
    DEB_BUILD_GNU_SYSTEM => DEB_BUILD | DEB_GNU_INFO,
    DEB_BUILD_GNU_TYPE => DEB_BUILD | DEB_GNU_INFO,
    DEB_HOST_ARCH => DEB_HOST,
    DEB_HOST_ARCH_OS => DEB_HOST | DEB_ARCH_INFO,
    DEB_HOST_ARCH_CPU => DEB_HOST | DEB_ARCH_INFO,
    DEB_HOST_ARCH_BITS => DEB_HOST | DEB_ARCH_ATTR,
    DEB_HOST_ARCH_ENDIAN => DEB_HOST | DEB_ARCH_ATTR,
    DEB_HOST_MULTIARCH => DEB_HOST | DEB_MULTIARCH,
    DEB_HOST_GNU_CPU => DEB_HOST | DEB_GNU_INFO,
    DEB_HOST_GNU_SYSTEM => DEB_HOST | DEB_GNU_INFO,
    DEB_HOST_GNU_TYPE => DEB_HOST | DEB_GNU_INFO,
    DEB_TARGET_ARCH => DEB_TARGET,
    DEB_TARGET_ARCH_OS => DEB_TARGET | DEB_ARCH_INFO,
    DEB_TARGET_ARCH_CPU => DEB_TARGET | DEB_ARCH_INFO,
    DEB_TARGET_ARCH_BITS => DEB_TARGET | DEB_ARCH_ATTR,
    DEB_TARGET_ARCH_ENDIAN => DEB_TARGET | DEB_ARCH_ATTR,
    DEB_TARGET_MULTIARCH => DEB_TARGET | DEB_MULTIARCH,
    DEB_TARGET_GNU_CPU => DEB_TARGET | DEB_GNU_INFO,
    DEB_TARGET_GNU_SYSTEM => DEB_TARGET | DEB_GNU_INFO,
    DEB_TARGET_GNU_TYPE => DEB_TARGET | DEB_GNU_INFO,
);

my $req_vars = DEB_ALL;
my $req_host_arch = '';
my $req_host_gnu_type = '';
my $req_target_arch = '';
my $req_target_gnu_type = '';
my $req_eq_arch = '';
my $req_is_arch = '';
my $req_variable_to_print;
my $action = 'l';
my $force = 0;

sub action_needs($) {
  my ($bits) = @_;
  return (($req_vars & $bits) == $bits);
}

while (@ARGV) {
    $_=shift(@ARGV);
    if (m/^-a/p) {
	$req_host_arch = ${^POSTMATCH};
    } elsif (m/^-t/p) {
	$req_host_gnu_type = ${^POSTMATCH};
    } elsif (m/^-A/p) {
	$req_target_arch = ${^POSTMATCH};
    } elsif (m/^-T/p) {
	$req_target_gnu_type = ${^POSTMATCH};
    } elsif (m/^-e/p) {
	$req_eq_arch = ${^POSTMATCH};
	$req_vars = $arch_vars{DEB_HOST_ARCH};
	$action = 'e';
    } elsif (m/^-i/p) {
	$req_is_arch = ${^POSTMATCH};
	$req_vars = $arch_vars{DEB_HOST_ARCH};
	$action = 'i';
    } elsif (m/^-u$/) {
	$req_vars = DEB_NONE;
	$action = 'u';
    } elsif (m/^-[ls]$/) {
	$action = $_;
	$action =~ s/^-//;
    } elsif (m/^-f$/) {
        $force=1;
    } elsif (m/^-q/p) {
	my $varname = ${^POSTMATCH};
	error(_g('%s is not a supported variable name'), $varname)
	    unless (exists $arch_vars{$varname});
	$req_variable_to_print = "$varname";
	$req_vars = $arch_vars{$varname};
        $action = 'q';
    } elsif (m/^-c$/) {
       $action = 'c';
       last;
    } elsif (m/^-L$/) {
        list_arches();
        exit unless @ARGV;
    } elsif (m/^-(?:\?|-help)$/) {
        usage();
       exit 0;
    } elsif (m/^--version$/) {
        version();
       exit 0;
    } else {
	usageerr(_g("unknown option \`%s'"), $_);
    }
}

my %v;
my $abi;

#
# Set build variables
#

$v{DEB_BUILD_ARCH} = get_raw_build_arch()
    if (action_needs(DEB_BUILD));
($abi, $v{DEB_BUILD_ARCH_OS}, $v{DEB_BUILD_ARCH_CPU}) = debarch_to_debtriplet($v{DEB_BUILD_ARCH})
    if (action_needs(DEB_BUILD | DEB_ARCH_INFO));
($v{DEB_BUILD_ARCH_BITS}, $v{DEB_BUILD_ARCH_ENDIAN}) = debarch_to_cpuattrs($v{DEB_BUILD_ARCH})
    if (action_needs(DEB_BUILD | DEB_ARCH_ATTR));

$v{DEB_BUILD_MULTIARCH} = debarch_to_multiarch($v{DEB_BUILD_ARCH})
    if (action_needs(DEB_BUILD | DEB_MULTIARCH));

if (action_needs(DEB_BUILD | DEB_GNU_INFO)) {
  $v{DEB_BUILD_GNU_TYPE} = debarch_to_gnutriplet($v{DEB_BUILD_ARCH});
  ($v{DEB_BUILD_GNU_CPU}, $v{DEB_BUILD_GNU_SYSTEM}) = split(/-/, $v{DEB_BUILD_GNU_TYPE}, 2);
}

#
# Set host variables
#

# First perform some sanity checks on the host arguments passed.

($req_host_arch, $req_host_gnu_type) = check_arch_coherency($req_host_arch, $req_host_gnu_type);

# Proceed to compute the host variables if needed.

if (action_needs(DEB_HOST)) {
    if ($req_host_arch eq '') {
        $v{DEB_HOST_ARCH} = get_raw_host_arch();
    } else {
        $v{DEB_HOST_ARCH} = $req_host_arch;
    }
}
($abi, $v{DEB_HOST_ARCH_OS}, $v{DEB_HOST_ARCH_CPU}) = debarch_to_debtriplet($v{DEB_HOST_ARCH})
    if (action_needs(DEB_HOST | DEB_ARCH_INFO));
($v{DEB_HOST_ARCH_BITS}, $v{DEB_HOST_ARCH_ENDIAN}) = debarch_to_cpuattrs($v{DEB_HOST_ARCH})
    if (action_needs(DEB_HOST | DEB_ARCH_ATTR));

$v{DEB_HOST_MULTIARCH} = debarch_to_multiarch($v{DEB_HOST_ARCH})
    if (action_needs(DEB_HOST | DEB_MULTIARCH));

if (action_needs(DEB_HOST | DEB_GNU_INFO)) {
    if ($req_host_gnu_type eq '') {
        $v{DEB_HOST_GNU_TYPE} = debarch_to_gnutriplet($v{DEB_HOST_ARCH});
    } else {
        $v{DEB_HOST_GNU_TYPE} = $req_host_gnu_type;
    }
    ($v{DEB_HOST_GNU_CPU}, $v{DEB_HOST_GNU_SYSTEM}) = split(/-/, $v{DEB_HOST_GNU_TYPE}, 2);

    my $gcc = get_gcc_host_gnu_type();

    warning(_g('specified GNU system type %s does not match gcc system ' .
               'type %s, try setting a correct CC environment variable'),
            $v{DEB_HOST_GNU_TYPE}, $gcc)
        if ($gcc ne '') && ($gcc ne $v{DEB_HOST_GNU_TYPE});
}

#
# Set target variables
#

# First perform some sanity checks on the target arguments passed.

($req_target_arch, $req_target_gnu_type) = check_arch_coherency($req_target_arch, $req_target_gnu_type);

# Proceed to compute the target variables if needed.

if (action_needs(DEB_TARGET)) {
    if ($req_target_arch eq '') {
        $v{DEB_TARGET_ARCH} = $v{DEB_HOST_ARCH};
    } else {
        $v{DEB_TARGET_ARCH} = $req_target_arch;
    }
}
($abi, $v{DEB_TARGET_ARCH_OS}, $v{DEB_TARGET_ARCH_CPU}) = debarch_to_debtriplet($v{DEB_TARGET_ARCH})
    if (action_needs(DEB_TARGET | DEB_ARCH_INFO));
($v{DEB_TARGET_ARCH_BITS}, $v{DEB_TARGET_ARCH_ENDIAN}) = debarch_to_cpuattrs($v{DEB_TARGET_ARCH})
    if (action_needs(DEB_TARGET | DEB_ARCH_ATTR));

$v{DEB_TARGET_MULTIARCH} = debarch_to_multiarch($v{DEB_TARGET_ARCH})
    if (action_needs(DEB_TARGET | DEB_MULTIARCH));

if (action_needs(DEB_TARGET | DEB_GNU_INFO)) {
    if ($req_target_gnu_type eq '') {
        $v{DEB_TARGET_GNU_TYPE} = debarch_to_gnutriplet($v{DEB_TARGET_ARCH});
    } else {
        $v{DEB_TARGET_GNU_TYPE} = $req_target_gnu_type;
    }
    ($v{DEB_TARGET_GNU_CPU}, $v{DEB_TARGET_GNU_SYSTEM}) = split(/-/, $v{DEB_TARGET_GNU_TYPE}, 2);
}


for my $k (keys %arch_vars) {
    $v{$k} = $ENV{$k} if (length $ENV{$k} && !$force);
}

if ($action eq 'l') {
    foreach my $k (sort keys %arch_vars) {
	print "$k=$v{$k}\n";
    }
} elsif ($action eq 's') {
    foreach my $k (sort keys %arch_vars) {
	print "$k=$v{$k}; ";
    }
    print 'export ' . join(' ', sort keys %arch_vars) . "\n";
} elsif ($action eq 'u') {
    print 'unset ' . join(' ', sort keys %arch_vars) . "\n";
} elsif ($action eq 'e') {
    exit !debarch_eq($v{DEB_HOST_ARCH}, $req_eq_arch);
} elsif ($action eq 'i') {
    exit !debarch_is($v{DEB_HOST_ARCH}, $req_is_arch);
} elsif ($action eq 'c') {
    @ENV{keys %v} = values %v;
    exec @ARGV;
} elsif ($action eq 'q') {
    print "$v{$req_variable_to_print}\n";
}
