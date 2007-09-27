package Dpkg::BuildOptions;

use strict;
use warnings;

sub parse {
    my ($env) = @_;

    $env ||= $ENV{DEB_BUILD_OPTIONS};

    unless ($env) { return {}; }

    my %opts;
    if ($env =~ s/(noopt|nostrip),?//ig) {
	$opts{lc $1} = '';
    } elsif ($env =~ s/(parallel)=(-?\d+),?//ig) {
	$opts{lc $1} = $2;
    }

    return \%opts;
}

sub set {
    my ($opts, $overwrite) = @_;

    my $env = $overwrite ? '' : $ENV{DEB_BUILD_OPTIONS}||'';
    if ($env) { $env .= ',' }

    while (my ($k, $v) = each %$opts) {
	if ($v) {
	    $env .= "$k=$v,";
	} else {
	    $env .= "$k,";
	}
    }
}

1;
