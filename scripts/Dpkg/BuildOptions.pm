package Dpkg::BuildOptions;

use strict;
use warnings;

sub parse {
    my ($env) = @_;

    $env ||= $ENV{DEB_BUILD_OPTIONS};

    unless ($env) { return {}; }

    my %opts;
    while ($env =~ s/(noopt|nostrip|nocheck),?//i) {
	$opts{lc $1} = '';
    }
    while ($env =~ s/(parallel)=(-?\d+),?//i) {
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

    $ENV{DEB_BUILD_OPTIONS} = $env if $env;
    return $env;
}

1;
