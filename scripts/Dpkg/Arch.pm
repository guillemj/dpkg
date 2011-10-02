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
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

package Dpkg::Arch;

use strict;
use warnings;

our $VERSION = "0.01";

use base qw(Exporter);
our @EXPORT_OK = qw(get_raw_build_arch get_raw_host_arch
                    get_build_arch get_host_arch get_gcc_host_gnu_type
                    get_valid_arches debarch_eq debarch_is
                    debarch_to_cpuattrs
                    debarch_to_gnutriplet gnutriplet_to_debarch
                    debtriplet_to_gnutriplet gnutriplet_to_debtriplet
                    debtriplet_to_debarch debarch_to_debtriplet
                    gnutriplet_to_multiarch debarch_to_multiarch);

use Dpkg;
use Dpkg::Gettext;
use Dpkg::ErrorHandling;

my (@cpu, @os);
my (%cputable, %ostable);
my (%cputable_re, %ostable_re);
my (%cpubits, %cpuendian);

my %debtriplet_to_debarch;
my %debarch_to_debtriplet;

{
    my $build_arch;
    my $host_arch;
    my $gcc_host_gnu_type;

    sub get_raw_build_arch()
    {
	return $build_arch if defined $build_arch;

	# Note: We *always* require an installed dpkg when inferring the
	# build architecture. The bootstrapping case is handled by
	# dpkg-architecture itself, by avoiding computing the DEB_BUILD_
	# variables when they are not requested.

	my $build_arch = `dpkg --print-architecture`;
	syserr("dpkg --print-architecture failed") if $? >> 8;

	chomp $build_arch;
	return $build_arch;
    }

    sub get_build_arch()
    {
	return $ENV{DEB_BUILD_ARCH} || get_raw_build_arch();
    }

    sub get_gcc_host_gnu_type()
    {
	return $gcc_host_gnu_type if defined $gcc_host_gnu_type;

	my $gcc_host_gnu_type = `\${CC:-gcc} -dumpmachine`;
	if ($? >> 8) {
	    $gcc_host_gnu_type = '';
	} else {
	    chomp $gcc_host_gnu_type;
	}

	return $gcc_host_gnu_type;
    }

    sub get_raw_host_arch()
    {
	return $host_arch if defined $host_arch;

	$gcc_host_gnu_type = get_gcc_host_gnu_type();

	if ($gcc_host_gnu_type eq '') {
	    warning(_g("Couldn't determine gcc system type, falling back to " .
	               "default (native compilation)"));
	} else {
	    my (@host_archtriplet) = gnutriplet_to_debtriplet($gcc_host_gnu_type);
	    $host_arch = debtriplet_to_debarch(@host_archtriplet);

	    if (defined $host_arch) {
		$gcc_host_gnu_type = debtriplet_to_gnutriplet(@host_archtriplet);
	    } else {
		warning(_g("Unknown gcc system type %s, falling back to " .
		           "default (native compilation)"), $gcc_host_gnu_type);
		$gcc_host_gnu_type = '';
	    }
	}

	if (!defined($host_arch)) {
	    # Switch to native compilation.
	    $host_arch = get_raw_build_arch();
	}

	return $host_arch;
    }

    sub get_host_arch()
    {
	return $ENV{DEB_HOST_ARCH} || get_raw_host_arch();
    }
}

sub get_valid_arches()
{
    read_cputable() if (!@cpu);
    read_ostable() if (!@os);

    my @arches;

    foreach my $os (@os) {
	foreach my $cpu (@cpu) {
	    my $arch = debtriplet_to_debarch(split(/-/, $os, 2), $cpu);
	    push @arches, $arch if defined($arch);
	}
    }

    return @arches;
}

sub read_cputable
{
    local $_;
    local $/ = "\n";

    open CPUTABLE, "$pkgdatadir/cputable"
	or syserr(_g("cannot open %s"), "cputable");
    while (<CPUTABLE>) {
	if (m/^(?!\#)(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)/) {
	    $cputable{$1} = $2;
	    $cputable_re{$1} = $3;
	    $cpubits{$1} = $4;
	    $cpuendian{$1} = $5;
	    push @cpu, $1;
	}
    }
    close CPUTABLE;
}

sub read_ostable
{
    local $_;
    local $/ = "\n";

    open OSTABLE, "$pkgdatadir/ostable"
	or syserr(_g("cannot open %s"), "ostable");
    while (<OSTABLE>) {
	if (m/^(?!\#)(\S+)\s+(\S+)\s+(\S+)/) {
	    $ostable{$1} = $2;
	    $ostable_re{$1} = $3;
	    push @os, $1;
	}
    }
    close OSTABLE;
}

sub read_triplettable()
{
    read_cputable() if (!@cpu);

    local $_;
    local $/ = "\n";

    open TRIPLETTABLE, "$pkgdatadir/triplettable"
	or syserr(_g("cannot open %s"), "triplettable");
    while (<TRIPLETTABLE>) {
	if (m/^(?!\#)(\S+)\s+(\S+)/) {
	    my $debtriplet = $1;
	    my $debarch = $2;

	    if ($debtriplet =~ /<cpu>/) {
		foreach my $_cpu (@cpu) {
		    (my $dt = $debtriplet) =~ s/<cpu>/$_cpu/;
		    (my $da = $debarch) =~ s/<cpu>/$_cpu/;

		    $debarch_to_debtriplet{$da} = $dt;
		    $debtriplet_to_debarch{$dt} = $da;
		}
	    } else {
		$debarch_to_debtriplet{$2} = $1;
		$debtriplet_to_debarch{$1} = $2;
	    }
	}
    }
    close TRIPLETTABLE;
}

sub debtriplet_to_gnutriplet(@)
{
    read_cputable() if (!@cpu);
    read_ostable() if (!@os);

    my ($abi, $os, $cpu) = @_;

    return undef unless defined($abi) && defined($os) && defined($cpu) &&
        exists($cputable{$cpu}) && exists($ostable{"$abi-$os"});
    return join("-", $cputable{$cpu}, $ostable{"$abi-$os"});
}

sub gnutriplet_to_debtriplet($)
{
    my ($gnu) = @_;
    return undef unless defined($gnu);
    my ($gnu_cpu, $gnu_os) = split(/-/, $gnu, 2);
    return undef unless defined($gnu_cpu) && defined($gnu_os);

    read_cputable() if (!@cpu);
    read_ostable() if (!@os);

    my ($os, $cpu);

    foreach my $_cpu (@cpu) {
	if ($gnu_cpu =~ /^$cputable_re{$_cpu}$/) {
	    $cpu = $_cpu;
	    last;
	}
    }

    foreach my $_os (@os) {
	if ($gnu_os =~ /^(.*-)?$ostable_re{$_os}$/) {
	    $os = $_os;
	    last;
	}
    }

    return undef if !defined($cpu) || !defined($os);
    return (split(/-/, $os, 2), $cpu);
}

sub gnutriplet_to_multiarch($)
{
    my ($gnu) = @_;
    my ($cpu, $cdr) = split('-', $gnu, 2);

    if ($cpu =~ /^i[456]86$/) {
	return "i386-$cdr";
    } else {
	return $gnu;
    }
}

sub debarch_to_multiarch($)
{
    my ($arch) = @_;

    return gnutriplet_to_multiarch(debarch_to_gnutriplet($arch));
}

sub debtriplet_to_debarch(@)
{
    read_triplettable() if (!%debtriplet_to_debarch);

    my ($abi, $os, $cpu) = @_;

    if (!defined($abi) || !defined($os) || !defined($cpu)) {
	return undef;
    } elsif (exists $debtriplet_to_debarch{"$abi-$os-$cpu"}) {
	return $debtriplet_to_debarch{"$abi-$os-$cpu"};
    } else {
	return undef;
    }
}

sub debarch_to_debtriplet($)
{
    read_triplettable() if (!%debarch_to_debtriplet);

    local ($_) = @_;
    my $arch;

    if (/^linux-([^-]*)/) {
	# XXX: Might disappear in the future, not sure yet.
	$arch = $1;
    } else {
	$arch = $_;
    }

    my $triplet = $debarch_to_debtriplet{$arch};

    if (defined($triplet)) {
	return split('-', $triplet, 3);
    } else {
	return undef;
    }
}

sub debarch_to_gnutriplet($)
{
    my ($arch) = @_;

    return debtriplet_to_gnutriplet(debarch_to_debtriplet($arch));
}

sub gnutriplet_to_debarch($)
{
    my ($gnu) = @_;

    return debtriplet_to_debarch(gnutriplet_to_debtriplet($gnu));
}

sub debwildcard_to_debtriplet($)
{
    local ($_) = @_;

    if (/any/) {
	if (/^([^-]*)-([^-]*)-(.*)/) {
	    return ($1, $2, $3);
	} elsif (/^([^-]*)-([^-]*)$/) {
	    return ('any', $1, $2);
	} else {
	    return ($_, $_, $_);
	}
    } else {
	return debarch_to_debtriplet($_);
    }
}

sub debarch_to_cpuattrs($)
{
    my ($arch) = @_;
    my ($abi, $os, $cpu) = debarch_to_debtriplet($arch);

    if (defined($cpu)) {
        return ($cpubits{$cpu}, $cpuendian{$cpu});
    } else {
        return undef;
    }
}

sub debarch_eq($$)
{
    my ($a, $b) = @_;

    return 1 if ($a eq $b);

    my @a = debarch_to_debtriplet($a);
    my @b = debarch_to_debtriplet($b);

    return 0 if grep(!defined, (@a, @b));

    return ($a[0] eq $b[0] && $a[1] eq $b[1] && $a[2] eq $b[2]);
}

sub debarch_is($$)
{
    my ($real, $alias) = @_;

    return 1 if ($alias eq $real or $alias eq 'any');

    my @real = debarch_to_debtriplet($real);
    my @alias = debwildcard_to_debtriplet($alias);

    return 0 if grep(!defined, (@real, @alias));

    if (($alias[0] eq $real[0] || $alias[0] eq 'any') &&
        ($alias[1] eq $real[1] || $alias[1] eq 'any') &&
        ($alias[2] eq $real[2] || $alias[2] eq 'any')) {
	return 1;
    }

    return 0;
}

1;
