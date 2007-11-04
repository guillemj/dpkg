package Dpkg::Arch;

use strict;
use warnings;

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(get_host_arch get_valid_arches debarch_eq debarch_is
                    debarch_to_gnutriplet gnutriplet_to_debarch
                    debtriplet_to_gnutriplet gnutriplet_to_debtriplet
                    debtriplet_to_debarch debarch_to_debtriplet);

use Dpkg;
use Dpkg::ErrorHandling qw(syserr subprocerr);

my (@cpu, @os);
my (%cputable, %ostable);
my (%cputable_re, %ostable_re);

my %debtriplet_to_debarch;
my %debarch_to_debtriplet;

{
    my $host_arch;

    sub get_host_arch()
    {
	return $host_arch if defined $host_arch;

	$host_arch = `dpkg-architecture -qDEB_HOST_ARCH`;
	$? && subprocerr("dpkg-architecture -qDEB_HOST_ARCH");
	chomp $host_arch;
	return $host_arch;
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

    open CPUTABLE, "$pkgdatadir/cputable"
	or syserr(_g("unable to open cputable"));
    while (<CPUTABLE>) {
	if (m/^(?!\#)(\S+)\s+(\S+)\s+(\S+)/) {
	    $cputable{$1} = $2;
	    $cputable_re{$1} = $3;
	    push @cpu, $1;
	}
    }
    close CPUTABLE;
}

sub read_ostable
{
    local $_;

    open OSTABLE, "$pkgdatadir/ostable"
	or syserr(_g("unable to open ostable"));
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

    open TRIPLETTABLE, "$pkgdatadir/triplettable"
	or syserr(_g("unable to open triplettable"));
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
