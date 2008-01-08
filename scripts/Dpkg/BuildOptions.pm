package Dpkg::BuildOptions;

use strict;
use warnings;

sub parse {
    my ($env) = @_;

    $env ||= $ENV{DEB_BUILD_OPTIONS};

    unless ($env) { return {}; }

    my %opts;

    foreach (split(/[\s,]+/, $env)) {
	# FIXME: This is pending resolution of Debian bug #430649
	/^([a-z][a-z0-9_-]*)(=(\w*))?$/;

	my ($k, $v) = ($1, $3 || '');

	# Sanity checks
	if (!$k) {
	    next;
	} elsif ($k =~ /^(noopt|nostrip|nocheck)$/ && length($v)) {
	    $v = '';
	} elsif ($k eq 'parallel' && $v !~ /^-?\d+$/) {
	    next;
	}

	$opts{$k} = $v;
    }

    return \%opts;
}

sub set {
    my ($opts, $overwrite) = @_;
    $overwrite = 1 if not defined($overwrite);

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
